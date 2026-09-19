import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'gallery_store.dart';
import 'mascot.dart';
import 'sound_policy.dart';
import 'squishy_button.dart';
import 'theme.dart';

/// "Finished!" — shown when a drawing is saved.
///
/// No score, no stars out of three, no time taken. The reward for
/// finishing is seeing the thing you made, big, with the mascot pleased
/// about it. Anything measurable invites doing better next time, which is
/// a fail state by another name.
Future<void> showCelebration(
  BuildContext context, {
  required SavedPiece piece,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Sky.ink.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, _, _) => _CelebrationScreen(piece: piece),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.85, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      ),
    ),
  );
}

class _CelebrationScreen extends StatefulWidget {
  const _CelebrationScreen({required this.piece});

  final SavedPiece piece;

  @override
  State<_CelebrationScreen> createState() => _CelebrationScreenState();
}

class _CelebrationScreenState extends State<_CelebrationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confetti = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward();

  bool _exported = false;
  bool _exporting = false;

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (_exporting || _exported) return;
    setState(() => _exporting = true);
    final ok = await GalleryStore.exportToDeviceGallery(widget.piece.pngPath);
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _exported = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _confetti,
              builder: (_, _) => CustomPaint(
                painter: _ConfettiPainter(_confetti.value),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Mascot(size: 200, mood: MascotMood.delighted),
                  const SizedBox(width: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Sky.card,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Sky.ink.withValues(alpha: 0.3),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.file(
                        // The saved PNG, so what is shown is exactly what
                        // was kept — not a re-render that could differ.
                        File(widget.piece.pngPath),
                        width: 280,
                        height: 280,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SquishyButton(
                        semanticLabel: 'save to photos',
                        enabled: !_exporting,
                        onPressed: _export,
                        child: Container(
                          width: kMinTouchTarget + 8,
                          height: kMinTouchTarget + 8,
                          decoration: BoxDecoration(
                            color: _exported ? Sky.dotHit : Sky.card,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _exported
                                ? Icons.check_rounded
                                : Icons.photo_library_rounded,
                            size: 38,
                            color: _exported ? Colors.white : Sky.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: kControlGap),
                      SquishyButton(
                        semanticLabel: 'done',
                        sfx: Sfx.transition,
                        onPressed: () => Navigator.of(context).pop(),
                        child: Container(
                          width: kMinTouchTarget + 8,
                          height: kMinTouchTarget + 8,
                          decoration: const BoxDecoration(
                            color: Sky.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.home_rounded,
                              size: 38, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);

  final double t;

  static final _colors = [
    const Color(0xFFE53935),
    const Color(0xFFFB8C00),
    const Color(0xFFFDD835),
    const Color(0xFF43A047),
    const Color(0xFF1E88E5),
    const Color(0xFF8E24AA),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Deterministic from the index, so there is no random source to seed
    // and every frame agrees on where a given piece is.
    for (var i = 0; i < 44; i++) {
      final seed = i * 7919 % 1000 / 1000;
      final x = ((i * 137.5) % size.width);
      final fall = (t + seed) % 1.0;
      final y = fall * (size.height + 80) - 40;
      final spin = (t * 4 + seed * 6) * math.pi;
      final fade = (1 - t).clamp(0.0, 1.0);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(spin);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-7, -4, 14, 8),
          const Radius.circular(2),
        ),
        Paint()
          ..color = _colors[i % _colors.length]
              .withValues(alpha: fade * 0.9),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
