import 'package:flutter/material.dart';

import 'sound_manager.dart';
import 'sound_policy.dart';
import 'theme.dart';

/// The press behaviour every tappable thing in the app is built from.
///
/// Squash on touch-down, overshoot past its own size on release, then
/// settle. Not an ease: a linear return feels like a rendering step, and
/// the overshoot is the entire reason a button reads as made of something
/// rather than drawn on glass.
///
/// One wrapper rather than per-widget animations, so category tiles,
/// swatches, tool icons and the finish button cannot drift apart in feel
/// — which they would, immediately, if each did its own.
class SquishyButton extends StatefulWidget {
  const SquishyButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.sfx = Sfx.tap,
    this.rate,
    this.enabled = true,
    this.shadow = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onPressed;

  /// Which sound this press makes. Colour swatches override [rate] so the
  /// palette rings as a scale.
  final Sfx sfx;
  final double? rate;

  final bool enabled;

  /// A drop shadow that shrinks as the button sinks. Off for controls that
  /// sit flat inside another surface, where a shadow reads as a seam.
  final bool shadow;

  /// The audience cannot read, so nothing here is labelled visually — but
  /// a screen reader still needs to name it.
  final String? semanticLabel;

  @override
  State<SquishyButton> createState() => _SquishyButtonState();
}

class _SquishyButtonState extends State<SquishyButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    // The spring below governs the actual timing; this duration only has
    // to be long enough for it to settle.
    duration: const Duration(milliseconds: 420),
  );

  // 1.0 = at rest, 0.0 = fully pressed. The spring runs on release.
  late final Animation<double> _release = CurvedAnimation(
    parent: _c,
    // Overshoot to ~1.05 then settle, per the feel spec.
    curve: Curves.elasticOut,
  );

  bool _down = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _onDown(_) {
    if (!widget.enabled || widget.onPressed == null) return;
    setState(() => _down = true);
    _c.stop();
  }

  void _onUp(_) {
    if (!_down) return;
    setState(() => _down = false);
    _c.forward(from: 0);
    SoundManager.instance.play(widget.sfx, rate: widget.rate);
    widget.onPressed?.call();
  }

  void _onCancel() {
    if (!_down) return;
    setState(() => _down = false);
    // Same spring home, but no sound and no callback: the finger left the
    // button, which at this age is usually a change of mind mid-press.
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = !widget.enabled || widget.onPressed == null;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.semanticLabel,
      child: Listener(
        // Listener, not GestureDetector: a press must squash the instant a
        // finger lands, with no wait to see whether the gesture arena is
        // about to hand the touch to a scroll instead. On a tile inside a
        // scrolling grid that delay is clearly visible.
        onPointerDown: _onDown,
        onPointerUp: _onUp,
        onPointerCancel: (_) => _onCancel(),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            double scale;
            if (_down) {
              scale = 0.90;
            } else if (_c.isAnimating) {
              // elasticOut runs 0 -> 1 with overshoot; map it from the
              // pressed size back up through ~1.05 to 1.0.
              scale = 0.90 + 0.10 * _release.value;
            } else {
              scale = 1.0;
            }

            final sink = ((1 - scale) / 0.10).clamp(0.0, 1.0);
            return Transform.scale(
              scale: disabled ? 1.0 : scale,
              child: widget.shadow
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Sky.ink.withValues(alpha: 0.18),
                            // The shadow shrinks and tightens as the button
                            // sinks, so it reads as moving towards the page
                            // rather than just getting smaller.
                            blurRadius: 16 - 10 * sink,
                            offset: Offset(0, 8 - 6 * sink),
                          ),
                        ],
                      ),
                      child: child,
                    )
                  : child,
            );
          },
          child: Opacity(
            opacity: disabled ? 0.4 : 1.0,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
