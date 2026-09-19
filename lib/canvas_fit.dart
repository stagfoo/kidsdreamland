/// Mapping between the asset's 1024-unit space and whatever box the tablet
/// actually gives us.
///
/// Pure, because getting it wrong is subtle and awful: a drawing that fits
/// but whose touches land somewhere else. Both directions are tested as
/// exact inverses, which is the only property that actually matters.
library;

import 'geometry.dart';

class CanvasFit {
  const CanvasFit(this.scale, this.offset);

  final double scale;
  final Vec2 offset;

  /// Fits [canvas] inside [box], centred, preserving aspect.
  ///
  /// Contain rather than cover: cropping a drawing to fill the screen
  /// would cut off the bit of the animal a child is trying to trace.
  factory CanvasFit.contain(Vec2 canvas, Vec2 box, {double padding = 0}) {
    final availW = box.x - padding * 2;
    final availH = box.y - padding * 2;
    if (canvas.x <= 0 || canvas.y <= 0 || availW <= 0 || availH <= 0) {
      return const CanvasFit(1, Vec2(0, 0));
    }
    final scale =
        availW / canvas.x < availH / canvas.y
            ? availW / canvas.x
            : availH / canvas.y;
    final offset = Vec2(
      (box.x - canvas.x * scale) / 2,
      (box.y - canvas.y * scale) / 2,
    );
    return CanvasFit(scale, offset);
  }

  /// Canvas units to screen.
  Vec2 toScreen(Vec2 p) => Vec2(p.x * scale + offset.x, p.y * scale + offset.y);

  /// Screen to canvas units. The one that decides where a finger landed.
  Vec2 toCanvas(Vec2 p) =>
      Vec2((p.x - offset.x) / scale, (p.y - offset.y) / scale);

  /// A length in canvas units, on screen. Stroke widths and the snap
  /// tolerance are authored at the 1024 scale and have to come along.
  double lengthToScreen(double v) => v * scale;
}
