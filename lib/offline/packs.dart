// Offline region packs (Magic Earth-style manager, app study §S8). A pack is
// three files: the map (.pmtiles), the place index (.search) and the road
// network (.roads). Downloads resume with HTTP Range after a drop.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../core/geo.dart';

class PackFile {
  final String name;
  final int bytes;
  final String url;
  const PackFile(this.name, this.bytes, this.url);
  factory PackFile.fromJson(Map<String, dynamic> j) =>
      PackFile(j['name'] as String, (j['bytes'] as num).toInt(), j['url'] as String);
}

class PackInfo {
  final String id;
  final String nameMs, nameEn;
  final Bounds bounds;
  final String dataDate;
  final List<PackFile> files;
  const PackInfo({
    required this.id,
    required this.nameMs,
    required this.nameEn,
    required this.bounds,
    required this.dataDate,
    required this.files,
  });
  int get bytes => files.fold(0, (a, f) => a + f.bytes);

  factory PackInfo.fromJson(Map<String, dynamic> j) {
    final b = (j['bbox'] as List).cast<num>();
    return PackInfo(
      id: j['id'] as String,
      nameMs: j['name_ms'] as String,
      nameEn: j['name_en'] as String,
      bounds: Bounds(b[1].toDouble(), b[0].toDouble(), b[3].toDouble(), b[2].toDouble()),
      dataDate: j['date'] as String,
      files: [for (final f in j['files'] as List) PackFile.fromJson(f as Map<String, dynamic>)],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name_ms': nameMs,
    'name_en': nameEn,
    'bbox': [bounds.west, bounds.south, bounds.east, bounds.north],
    'date': dataDate,
    'files': [
      for (final f in files) {'name': f.name, 'bytes': f.bytes, 'url': f.url},
    ],
  };
}

enum DownloadState { idle, running, paused, failed, done }

class DownloadProgress {
  final DownloadState state;
  final int done, total;
  final String? error;
  const DownloadProgress(this.state, this.done, this.total, [this.error]);
  double get fraction => total == 0 ? 0 : done / total;
}

/// Catalog used until the online catalog has been fetched once. Same packs,
/// same URLs as the published catalog.json.
const _builtInCatalog = '''
{"packs":[
 {"id":"semenanjung","name_ms":"Semenanjung Malaysia","name_en":"Peninsular Malaysia",
  "bbox":[99.6,1.2,104.6,6.8],"date":"","files":[]},
 {"id":"sabah-sarawak","name_ms":"Sabah & Sarawak","name_en":"Sabah & Sarawak",
  "bbox":[109.5,0.85,119.3,7.4],"date":"","files":[]}
]}''';

class PackManager extends ChangeNotifier {
  PackManager._(this.dir);
  final Directory dir;

  List<PackInfo> catalog = [];
  final Map<String, PackInfo> installed = {};
  final Map<String, DownloadProgress> progress = {};
  final Map<String, bool> _cancel = {};

  static Future<PackManager> create() async {
    // The web app has no file system: no packs, online only.
    if (kIsWeb) return PackManager._(Directory(''))..catalog = _parseCatalog(_builtInCatalog);
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/packs')..createSync(recursive: true);
    final m = PackManager._(dir);
    m._loadInstalled();
    m.catalog = _parseCatalog(_builtInCatalog);
    final cached = File('${dir.path}/catalog.json');
    if (cached.existsSync()) {
      try {
        m.catalog = _parseCatalog(cached.readAsStringSync());
      } catch (_) {}
    }
    return m;
  }

  static List<PackInfo> _parseCatalog(String s) => [
    for (final p in (jsonDecode(s) as Map<String, dynamic>)['packs'] as List)
      PackInfo.fromJson(p as Map<String, dynamic>),
  ];

  void _loadInstalled() {
    for (final d in dir.listSync().whereType<Directory>()) {
      final manifest = File('${d.path}/pack.json');
      if (manifest.existsSync()) {
        try {
          final p = PackInfo.fromJson(jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>);
          installed[p.id] = p;
        } catch (_) {}
      }
    }
  }

  Future<void> refreshCatalog() async {
    if (kIsWeb) return;
    try {
      final res = await http.get(Uri.parse(ArahConfig.packCatalogUrl)).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        catalog = _parseCatalog(res.body);
        File('${dir.path}/catalog.json').writeAsStringSync(res.body);
        notifyListeners();
      }
    } catch (_) {
      // Offline: keep what we have.
    }
  }

  String path(String packId, String fileName) => '${dir.path}/$packId/$fileName';

  /// The installed pack covering a point, if any.
  PackInfo? packAt(Geo p) {
    for (final pack in installed.values) {
      if (pack.bounds.contains(p)) return pack;
    }
    return null;
  }

  String? fileOf(PackInfo pack, String ext) {
    for (final f in pack.files) {
      if (f.name.endsWith(ext)) {
        final p = path(pack.id, f.name);
        if (File(p).existsSync()) return p;
      }
    }
    return null;
  }

  bool hasUpdate(String id) {
    final inst = installed[id];
    if (inst == null) return false;
    final cat = catalog.where((c) => c.id == id).firstOrNull;
    return cat != null && cat.dataDate.isNotEmpty && cat.dataDate != inst.dataDate;
  }

  Future<void> download(PackInfo pack) async {
    if (pack.files.isEmpty) {
      progress[pack.id] = const DownloadProgress(DownloadState.failed, 0, 0, 'catalog');
      notifyListeners();
      return;
    }
    _cancel[pack.id] = false;
    final folder = Directory('${dir.path}/${pack.id}')..createSync(recursive: true);
    var doneBefore = 0;
    progress[pack.id] = DownloadProgress(DownloadState.running, 0, pack.bytes);
    notifyListeners();
    try {
      for (final f in pack.files) {
        final target = File('${folder.path}/${f.name}');
        final part = File('${target.path}.part');
        if (target.existsSync() && target.lengthSync() == f.bytes && installed[pack.id]?.dataDate == pack.dataDate) {
          doneBefore += f.bytes;
          continue;
        }
        await _fetch(pack, f, part, doneBefore);
        if (_cancel[pack.id] == true) {
          progress[pack.id] = DownloadProgress(
            DownloadState.paused,
            doneBefore + (part.existsSync() ? part.lengthSync() : 0),
            pack.bytes,
          );
          notifyListeners();
          return;
        }
        if (part.lengthSync() != f.bytes) throw Exception('size mismatch for ${f.name}');
        if (target.existsSync()) target.deleteSync();
        part.renameSync(target.path);
        doneBefore += f.bytes;
      }
      File('${folder.path}/pack.json').writeAsStringSync(jsonEncode(pack.toJson()));
      installed[pack.id] = pack;
      progress[pack.id] = DownloadProgress(DownloadState.done, pack.bytes, pack.bytes);
    } catch (e) {
      final p = progress[pack.id];
      progress[pack.id] = DownloadProgress(DownloadState.failed, p?.done ?? 0, pack.bytes, '$e');
    }
    notifyListeners();
  }

  Future<void> _fetch(PackInfo pack, PackFile f, File part, int doneBefore) async {
    final have = part.existsSync() ? part.lengthSync() : 0;
    if (have >= f.bytes) return;
    final req = http.Request('GET', Uri.parse(f.url));
    if (have > 0) req.headers['Range'] = 'bytes=$have-';
    req.headers.addAll(ArahConfig.userAgent);
    final client = http.Client();
    try {
      final res = await client.send(req);
      if (res.statusCode != 200 && res.statusCode != 206) throw Exception('HTTP ${res.statusCode}');
      // A server that ignored Range sends the whole file: start over.
      final sink = part.openWrite(mode: res.statusCode == 206 ? FileMode.append : FileMode.write);
      var got = res.statusCode == 206 ? have : 0;
      var lastNotify = DateTime.now();
      await for (final chunk in res.stream) {
        if (_cancel[pack.id] == true) break;
        sink.add(chunk);
        got += chunk.length;
        if (DateTime.now().difference(lastNotify) > const Duration(milliseconds: 300)) {
          lastNotify = DateTime.now();
          progress[pack.id] = DownloadProgress(DownloadState.running, doneBefore + got, pack.bytes);
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
  }

  void pause(String id) => _cancel[id] = true;

  Future<void> delete(String id) async {
    final d = Directory('${dir.path}/$id');
    if (d.existsSync()) d.deleteSync(recursive: true);
    installed.remove(id);
    progress.remove(id);
    notifyListeners();
  }

  int diskBytes(String id) {
    final d = Directory('${dir.path}/$id');
    if (!d.existsSync()) return 0;
    return d.listSync().whereType<File>().fold(0, (a, f) => a + f.lengthSync());
  }
}
