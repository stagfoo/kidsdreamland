import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Dreamy — the mascot.
///
/// Drawn rather than bundled as an image: he has to appear at half a dozen
/// sizes and stay crisp, and a vector he can be animated from costs less
/// than a set of PNGs that would each need redrawing to change anything
/// about him.
///
/// He is a round, soft, eyeless-until-you-look creature with a single horn
/// — deliberately not a known animal, so he does not compete with the
/// dinosaurs and cows a child came here to draw.
class Mascot extends StatefulWidget {
  const Mascot({
    super.key,
    this.size = 180,
    this.mood = MascotMood.happy,
    this.animate = true,
  });

  final double size;
  final MascotMood mood;

  /// Off for the small static appearances, where a bobbing character in
  /// the corner would pull attention away from the drawing.
  final bool animate;

  @override
  State<Mascot> createState() => _MascotState();
}

enum MascotMood {
  /// Resting. Eyes open, gentle smile.
  happy,

  /// On the celebration screen: eyes squeezed shut, big grin.
  delighted,

  /// While the child is drawing: watching, mouth small.
  watching,
}

class _MascotState extends State<Mascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return CustomPaint(
        size: Size.square(widget.size),
        painter: _MascotPainter(0, widget.mood),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _MascotPainter(_c.value, widget.mood),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  _MascotPainter(this.t, this.mood);

  /// 0..1, looping.
  final double t;
  final MascotMood mood;

  static const _bodyColor = Color(0xFF9575CD);
  static const _bellyColor = Color(0xFFD1C4E9);
  static const _hornColor = Color(0xFFFFD54F);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    canvas.save();
    canvas.scale(s);

    // A slow breath: he rises and squashes very slightly, which is what
    // makes him read as alive rather than as a sticker.
    final breathe = math.sin(t * math.pi * 2);
    final lift = breathe * 1.6;
    final squash = 1 + breathe * 0.02;

    canvas.translate(50, 56 + lift);
    canvas.scale(1 / squash, squash);
    canvas.translate(-50, -56);

    final body = Paint()..color = _bodyColor;

    // Feet, drawn first so the body overlaps them.
    canvas.drawOval(Rect.fromCenter(
        center: const Offset(38, 84), width: 22, height: 14), body);
    canvas.drawOval(Rect.fromCenter(
        center: const Offset(62, 84), width: 22, height: 14), body);

    // Body.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 56), width: 68, height: 62),
      body,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 64), width: 40, height: 38),
      Paint()..color = _bellyColor,
    );

    // Ears, which swing a little out of phase with the breath so he does
    // not look rigid.
    final earSwing = math.sin(t * math.pi * 2 + 0.8) * 2;
    for (final side in [-1, 1]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(50 + side * 30, 34 + earSwing * side),
          width: 20,
          height: 26,
        ),
        body,
      );
    }

    // Horn.
    final horn = Path()
      ..moveTo(44, 26)
      ..lineTo(50, 6)
      ..lineTo(56, 26)
      ..close();
    canvas.drawPath(horn, Paint()..color = _hornColor);

    _paintFace(canvas);
    canvas.restore();
  }

  void _paintFace(Canvas canvas) {
    final ink = Paint()
      ..color = Sky.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    switch (mood) {
      case MascotMood.happy:
      case MascotMood.watching:
        // A blink, briefly, once per loop — the cheapest signal of life
        // there is, and the one people notice least consciously.
        final blinking = t > 0.86 && t < 0.91;
        for (final side in [-1, 1]) {
          final cx = 50 + side * 12.0;
          if (blinking) {
            canvas.drawLine(Offset(cx - 5, 48), Offset(cx + 5, 48), ink);
          } else {
            canvas.drawCircle(Offset(cx, 48), 5.5, Paint()..color = Sky.ink);
            // A highlight, which is what stops a black dot looking dead.
            canvas.drawCircle(
              Offset(cx + 2, 46),
              1.8,
              Paint()..color = Colors.white,
            );
          }
        }
        final mouth = Path();
        if (mood == MascotMood.happy) {
          mouth.moveTo(43, 60);
          mouth.quadraticBezierTo(50, 68, 57, 60);
        } else {
          mouth.moveTo(46, 62);
          mouth.quadraticBezierTo(50, 65, 54, 62);
        }
        canvas.drawPath(mouth, ink);

      case MascotMood.delighted:
        // Eyes squeezed shut into happy arcs.
        for (final side in [-1, 1]) {
          final cx = 50 + side * 12.0;
          final eye = Path()
            ..moveTo(cx - 6, 50)
            ..quadraticBezierTo(cx, 42, cx + 6, 50);
          canvas.drawPath(eye, ink);
        }
        final grin = Path()
          ..moveTo(40, 58)
          ..quadraticBezierTo(50, 72, 60, 58)
          ..close();
        canvas.drawPath(grin, Paint()..color = Sky.ink);
        canvas.drawPath(
          Path()
            ..moveTo(44, 63)
            ..quadraticBezierTo(50, 69, 56, 63)
            ..close(),
          Paint()..color = const Color(0xFFEF9A9A),
        );
        // Cheeks.
        for (final side in [-1, 1]) {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(50 + side * 24.0, 58),
              width: 12,
              height: 8,
            ),
            Paint()..color = const Color(0x55EF9A9A),
          );
        }
    }
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.t != t || old.mood != mood;
}
