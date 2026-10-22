// Report sheet (app study §S7): first tap picks the kind, an optional second
// tap the detail, then it sends itself after 3 s — no confirm step while
// driving, like Waze.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state.dart';
import '../core/geo.dart';
import '../reports/reports.dart';
import 'map_kit.dart';

String reportName(BuildContext c, ReportKind k) => switch (k) {
  ReportKind.polis => c.tr('Polis', 'Police'),
  ReportKind.kemalangan => c.tr('Kemalangan', 'Crash'),
  ReportKind.kesesakan => c.tr('Kesesakan', 'Traffic'),
  ReportKind.bahaya => c.tr('Bahaya', 'Hazard'),
  ReportKind.banjir => c.tr('Banjir', 'Flood'),
  ReportKind.ditutup => c.tr('Jalan ditutup', 'Closure'),
};

List<(String, String, String)> _subs(ReportKind k) => switch (k) {
  ReportKind.polis => [('tersorok', 'Tersorok', 'Hidden'), ('seberang', 'Seberang jalan', 'Other side')],
  ReportKind.kemalangan => [
    ('kecil', 'Kecil', 'Minor'),
    ('besar', 'Besar', 'Major'),
    ('seberang', 'Seberang jalan', 'Other side'),
  ],
  ReportKind.kesesakan => [
    ('sederhana', 'Sederhana', 'Moderate'),
    ('teruk', 'Teruk', 'Heavy'),
    ('henti', 'Tidak bergerak', 'Standstill'),
  ],
  ReportKind.bahaya => [
    ('objek', 'Objek di jalan', 'Object on road'),
    ('bahu', 'Kenderaan di bahu jalan', 'Car on shoulder'),
    ('lubang', 'Lubang jalan', 'Pothole'),
    ('lampu', 'Lampu isyarat rosak', 'Broken traffic light'),
    ('kerja', 'Kerja jalan', 'Roadworks'),
  ],
  ReportKind.banjir => [('boleh', 'Boleh lalu', 'Passable'), ('tidak', 'Tidak boleh lalu', 'Not passable')],
  ReportKind.ditutup => [('sjr', 'Sekatan jalan raya', 'Roadblock'), ('ditutup', 'Ditutup sepenuhnya', 'Fully closed')],
};

Future<void> showReportSheet(BuildContext context, Geo pos, double heading, {bool driving = false}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReportSheet(pos: pos, heading: heading, driving: driving),
  );
}

class _ReportSheet extends StatefulWidget {
  final Geo pos;
  final double heading;
  final bool driving;
  const _ReportSheet({required this.pos, required this.heading, required this.driving});
  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportKind? _kind;
  String _sub = '';
  Timer? _timer;
  int _count = 3;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _pick(ReportKind k) {
    HapticFeedback.selectionClick();
    setState(() {
      _kind = k;
      _sub = '';
    });
    _countdown();
  }

  void _countdown() {
    _timer?.cancel();
    _count = 3;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _count--);
      if (_count <= 0) {
        t.cancel();
        _send();
      }
    });
  }

  Future<void> _send() async {
    final app = context.appRead;
    final k = _kind;
    if (k == null) return;
    final r = await app.reports.send(k, _sub, widget.pos, widget.heading);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          r == null
              ? app.tr('Had laporan dicapai — cuba lagi nanti', 'Report limit reached — try again later')
              : app.reports.shared
              ? app.tr('Terima kasih! Laporan dihantar', 'Thanks! Report sent')
              : app.tr('Laporan disimpan pada telefon ini', 'Report saved on this phone'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = _kind;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              k == null ? context.tr('Apa yang anda nampak?', 'What do you see?') : reportName(context, k),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (k == null)
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final kind in ReportKind.values)
                    Material(
                      color: reportColor(kind),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _pick(kind),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(reportIcon(kind), color: Colors.white, size: 40),
                            const SizedBox(height: 6),
                            Text(
                              reportName(context, kind),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (id, ms, en) in _subs(k))
                    ChoiceChip(
                      label: Text(context.tr(ms, en), style: const TextStyle(fontSize: 16)),
                      selected: _sub == id,
                      onSelected: (_) {
                        setState(() => _sub = id);
                        _countdown();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _timer?.cancel();
                        setState(() => _kind = null);
                      },
                      child: Text(context.tr('Batal', 'Cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        _timer?.cancel();
                        _send();
                      },
                      child: Text('${context.tr('Hantar', 'Send')} ($_count)'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
