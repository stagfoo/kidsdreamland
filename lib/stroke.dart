/// Strokes: what a finger leaves behind.
///
/// Pure data plus the smoothing and width maths, so the awkward parts —
/// what a fast flick does, what a single tap does — are testable without
/// a touchscreen.
library;

import 'dart:math' as math;

import 'geometry.dart';
import 'palette.dart';

class StrokePoint {
  const StrokePoint(this.position, this.width);

  final Vec2 position;
  final double width;
}

class Stroke {
  Stroke({
    required this.colorKey,
    required this.brushKey,
    List<StrokePoint>? points,
  }) : points = points ?? <StrokePoint>[];

  final String colorKey;
  final String brushKey;
  final List<StrokePoint> points;

  PaintColor get color => PaintColor.byKey(colorKey) ?? PaintColor.blue;
  BrushKind get brush => BrushKind.byKey(brushKey) ?? BrushKind.marker;

  bool get isEmpty => points.isEmpty;

  /// A stroke that never moved — a tap. It still has to draw something, or
  /// tapping the canvas looks broken.
  bool get isDot => points.length == 1;

  Map<String, dynamic> toJson() => {
        'color': colorKey,
        'brush': brushKey,
        // Flat triples rather than objects: a long session is thousands of
        // points, and `{"x":..,"y":..,"w":..}` each triples the file.
        'points': [
          for (final p in points) ...[
            _round(p.position.x),
            _round(p.position.y),
            _round(p.width),
          ],
        ],
      };

  static Stroke fromJson(Map<String, dynamic> json) {
    final raw = (json['points'] as List).cast<num>();
    final points = <StrokePoint>[];
    for (var i = 0; i + 2 < raw.length; i += 3) {
      points.add(StrokePoint(
        Vec2(raw[i].toDouble(), raw[i + 1].toDouble()),
        raw[i + 2].toDouble(),
      ));
    }
    return Stroke(
      colorKey: json['color'] as String,
      brushKey: json['brush'] as String,
      points: points,
    );
  }

  /// One decimal is finer than a canvas unit at any real display size, and
  /// keeps the saved file roughly half the size of full doubles.
  static double _round(double v) => (v * 10).roundToDouble() / 10;
}

/// Builds a stroke from raw touch positions, deciding what to keep.
class StrokeBuilder {
  StrokeBuilder({
    required this.brush,
    required this.colorKey,
    this.minSpacing = 2.0,
  }) : _stroke = Stroke(colorKey: colorKey, brushKey: brush.key);

  final BrushKind brush;
  final String colorKey;

  /// Touch events arrive far faster than the finger moves. Dropping points
  /// closer together than this keeps the stroke list from growing without
  /// bound while standing still, which is what makes a long session slow.
  final double minSpacing;

  final Stroke _stroke;
  var _distance = 0.0;

  Stroke get stroke => _stroke;

  void add(Vec2 p) {
    if (_stroke.points.isEmpty) {
      _stroke.points.add(StrokePoint(p, _widthAt(0)));
      return;
    }
    final last = _stroke.points.last.position;
    final step = last.distanceTo(p);
    if (step < minSpacing) return;
    _distance += step;
    _stroke.points.add(StrokePoint(p, _widthAt(_distance)));
  }

  /// Width along the stroke. The crayon's grain is a sum of two sine waves
  /// at unrelated wavelengths, so the wobble never visibly repeats —
  /// a single sine reads as a corrugation rather than as texture.
  double _widthAt(double distance) {
    if (brush.grain == 0) return brush.width;
    final wobble = math.sin(distance * 0.09) * 0.6 +
        math.sin(distance * 0.23 + 1.7) * 0.4;
    return brush.width * (1 + wobble * brush.grain);
  }
}
