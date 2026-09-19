/// The colour palette and the three brushes.
///
/// Colours are stored by key, never as raw values, so retuning the palette
/// restyles saved work rather than stranding it, and artwork written by a
/// future build with a colour this one does not know still opens.
library;

/// Six colours, per the MVP scope. Chosen to stay apart from each other for
/// a child naming them out loud — no two blues, no two reds — and all dark
/// enough that a white canvas reads as unfilled.
enum PaintColor {
  red('red', 0xFFE53935),
  orange('orange', 0xFFFB8C00),
  yellow('yellow', 0xFFFDD835),
  green('green', 0xFF43A047),
  blue('blue', 0xFF1E88E5),
  purple('purple', 0xFF8E24AA);

  const PaintColor(this.key, this.argb);

  final String key;
  final int argb;

  static PaintColor? byKey(String key) {
    for (final c in values) {
      if (c.key == key) return c;
    }
    return null;
  }
}

/// The three tools, which differ in how the stroke is laid down rather than
/// in what they can do — a child picks by feel, not by capability.
enum BrushKind {
  /// Thin, hard-edged, fully opaque.
  pencil('pencil', 8, 1.0, 0.0),

  /// Fat and slightly translucent, so overlapping passes build up the way
  /// a real crayon does.
  crayon('crayon', 26, 0.72, 0.35),

  /// Fat, opaque, smooth.
  marker('marker', 20, 0.95, 0.0);

  const BrushKind(this.key, this.width, this.opacity, this.grain);

  final String key;

  /// Stroke width in canvas units, at the authored 1024 scale.
  final double width;

  final double opacity;

  /// How much the stroke's width wobbles along its length. Zero is a clean
  /// line; the crayon's wobble is what stops it looking like a fat marker.
  final double grain;

  static BrushKind? byKey(String key) {
    for (final b in values) {
      if (b.key == key) return b;
    }
    return null;
  }
}
