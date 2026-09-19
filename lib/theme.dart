import 'package:flutter/material.dart';

import 'palette.dart';

/// The app's own colours — distinct from [PaintColor], which is what a
/// child paints *with*. Keeping them apart means the chrome can be retuned
/// without changing what any saved drawing looks like.
class Sky {
  static const background = Color(0xFFFFF8E7);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF3E2723);

  /// The line art itself. Warm near-black rather than pure black: on a
  /// cream ground, true black reads as a hole punched in the page.
  static const outline = Color(0xFF4E342E);

  /// A checkpoint not yet drawn through, and one that has been.
  static const dotPending = Color(0xFFBCAAA4);
  static const dotHit = Color(0xFF66BB6A);

  static const accent = Color(0xFF7E57C2);
  static const accentSoft = Color(0xFFD1C4E9);

  /// Category tints, in index order.
  static const categoryTints = [
    Color(0xFFA5D6A7),
    Color(0xFFFFCC80),
    Color(0xFF90CAF9),
    Color(0xFFF48FB1),
  ];
}

/// The smallest a tappable thing is ever allowed to be.
///
/// Well above the platform's 48dp: that figure is for an adult index
/// finger on a phone held deliberately, and this is a five-year-old's
/// whole hand on a tablet on a carpet.
const double kMinTouchTarget = 72;

/// The gap between adjacent controls. Generous on purpose — palette
/// swatches packed tight are how a child picks green while reaching for
/// blue, and then thinks the app did it.
const double kControlGap = 18;

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Sky.accent,
      surface: Sky.background,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: Sky.background,
    splashFactory: NoSplash.splashFactory,
    // Every button in this app animates its own press. Material's ripple
    // on top of that reads as a second, competing response to one touch.
    highlightColor: Colors.transparent,
  );
}
