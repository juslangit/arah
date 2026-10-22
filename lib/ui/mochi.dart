// Mochi, Arah's mascot: a rice cake with a leaf that points the way. Drawn in
// code (no image files) so it is sharp at any size: as a widget in the app's
// cards and as a PNG for the map (your location marker).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/theme.dart';

enum MochiMood { happy, alert }

/// Paints Mochi into a square of side [size] at the canvas origin
/// (drawn on a 100×100 grid, like the design file's SVG).
void paintMochi(Canvas c, double size, {MochiMood mood = MochiMood.happy}) {
  c.save();
  c.scale(size / 100);
  // Ground shadow.
  c.drawOval(const Rect.fromLTRB(20, 89, 80, 99), Paint()..color = const Color(0x1A000000));
  // Body: a soft dome.
  final body = Path()
    ..moveTo(14, 66)
    ..cubicTo(14, 42, 30, 22, 50, 22)
    ..cubicTo(70, 22, 86, 42, 86, 66)
    ..cubicTo(86, 81, 70, 90, 50, 90)
    ..cubicTo(30, 90, 14, 81, 14, 66)
    ..close();
  c.drawPath(body, Paint()..color = Colors.white);
  c.drawPath(
    body,
    Paint()
      ..color = const Color(0xFFF3C9D8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5,
  );
  // The leaf on top, pointing the way.
  c.drawPath(
    Path()
      ..moveTo(50, 22)
      ..cubicTo(48, 13, 54, 7, 63, 8)
      ..cubicTo(62, 16, 57, 21, 50, 22)
      ..close(),
    Paint()..color = ArahColors.leaf,
  );
  c.drawPath(
    Path()
      ..moveTo(50, 22)
      ..cubicTo(51, 15, 47, 10, 41, 10)
      ..cubicTo(41, 16, 44, 20, 50, 22)
      ..close(),
    Paint()..color = const Color(0xFF9ADBA9),
  );
  // Face.
  final ink = Paint()..color = ArahColors.ink;
  final eyeR = mood == MochiMood.alert ? 5.0 : 4.2;
  c.drawCircle(const Offset(37, 60), eyeR, ink);
  c.drawCircle(const Offset(63, 60), eyeR, ink);
  c.drawCircle(const Offset(38.5, 58.5), 1.3, Paint()..color = Colors.white);
  c.drawCircle(const Offset(64.5, 58.5), 1.3, Paint()..color = Colors.white);
  final blush = Paint()..color = ArahColors.blush;
  c.drawOval(Rect.fromCenter(center: const Offset(29, 69), width: 12, height: 7.2), blush);
  c.drawOval(Rect.fromCenter(center: const Offset(71, 69), width: 12, height: 7.2), blush);
  final mouth = Paint()
    ..color = ArahColors.ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round;
  if (mood == MochiMood.alert) {
    c.drawOval(Rect.fromCenter(center: const Offset(50, 69), width: 7, height: 6), mouth);
  } else {
    c.drawPath(
      Path()
        ..moveTo(45, 67)
        ..quadraticBezierTo(50, 72, 55, 67),
      mouth,
    );
  }
  c.restore();
}

class Mochi extends StatelessWidget {
  final double size;
  final MochiMood mood;
  const Mochi({super.key, this.size = 40, this.mood = MochiMood.happy});

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _MochiPainter(mood));
}

class _MochiPainter extends CustomPainter {
  final MochiMood mood;
  _MochiPainter(this.mood);
  @override
  void paint(Canvas canvas, Size size) => paintMochi(canvas, size.shortestSide, mood: mood);
  @override
  bool shouldRepaint(_MochiPainter old) => old.mood != mood;
}

/// Mochi as a PNG for the map, [size] in physical pixels.
Future<Uint8List> mochiImage({double size = 120}) async {
  final rec = ui.PictureRecorder();
  paintMochi(Canvas(rec), size);
  final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

/// A pink chevron that shows which way you are heading, drawn under Mochi.
Future<Uint8List> headingImage({double size = 120}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final s = size / 100;
  c.drawCircle(Offset(50 * s, 50 * s), 46 * s, Paint()..color = ArahColors.pink.withValues(alpha: 0.18));
  c.drawPath(
    Path()
      ..moveTo(50 * s, 0)
      ..lineTo(64 * s, 18 * s)
      ..quadraticBezierTo(50 * s, 13 * s, 36 * s, 18 * s)
      ..close(),
    Paint()..color = ArahColors.pink,
  );
  final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}
