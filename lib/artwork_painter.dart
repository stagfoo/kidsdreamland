import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'artwork.dart';
import 'canvas_fit.dart';
import 'drawing_asset.dart';
import 'geometry.dart';
import 'palette.dart';
import 'stroke.dart';
import 'svg_path.dart';
import 'theme.dart';
import 'trace_guide.dart';

/// Builds a `ui.Path` from parsed commands.
///
/// The painter uses the commands (real curves, so the line is smooth at
/// any zoom) while the geometry uses the flattened points. Both come from
/// one parse, so they cannot disagree about where the drawing is.
ui.Path buildUiPath(ParsedPath parsed) {
  final path = ui.Path()..fillType = PathFillType.evenOdd;
  for (final c in parsed.commands) {
    switch (c) {
      case MoveTo(:final to):
        path.moveTo(to.x, to.y);
      case LineTo(:final to):
        path.lineTo(to.x, to.y);
      case CubicTo(:final c1, :final c2, :final to):
        path.cubicTo(c1.x, c1.y, c2.x, c2.y, to.x, to.y);
      case QuadraticTo(:final c, :final to):
        path.quadraticBezierTo(c.x, c.y, to.x, to.y);
      case ClosePath():
        path.close();
    }
  }
  return path;
}

/// Turns a stroke into a fillable outline.
///
/// A variable-width stroke cannot be a `drawPath` with a stroke paint —
/// that has one width for the whole path. Building the outline as a
/// polygon is what lets the crayon's grain actually vary along its length.
ui.Path buildStrokePath(Stroke stroke) {
  final pts = stroke.points;
  final path = ui.Path();
  if (pts.isEmpty) return path;

  if (pts.length == 1) {
    // A tap still has to leave a mark, or the canvas looks broken to
    // anyone who pokes it rather than dragging.
    final p = pts.first;
    path.addOval(Rect.fromCircle(
      center: Offset(p.position.x, p.position.y),
      radius: p.width / 2,
    ));
    return path;
  }

  // Walk one side then back down the other, offsetting by half the width
  // along each segment's normal.
  final left = <Offset>[];
  final right = <Offset>[];
  for (var i = 0; i < pts.length; i++) {
    final cur = pts[i].position;
    // The direction at a point is the segment it is joined to; at the
    // ends there is only one.
    final prev = i > 0 ? pts[i - 1].position : cur;
    final next = i < pts.length - 1 ? pts[i + 1].position : cur;
    var dir = next - prev;
    if (dir.length == 0) dir = const Vec2(1, 0);
    final len = dir.length;
    final nx = -dir.y / len, ny = dir.x / len;
    final half = pts[i].width / 2;
    left.add(Offset(cur.x + nx * half, cur.y + ny * half));
    right.add(Offset(cur.x - nx * half, cur.y - ny * half));
  }

  path.moveTo(left.first.dx, left.first.dy);
  for (final p in left.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  for (final p in right.reversed) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();

  // Round caps, so a stroke does not end in a visible chisel edge.
  for (final end in [pts.first, pts.last]) {
    path.addOval(Rect.fromCircle(
      center: Offset(end.position.x, end.position.y),
      radius: end.width / 2,
    ));
  }
  return path;
}

/// Everything that only changes when the child finishes an action: the
/// line art, the filled regions, and completed strokes.
///
/// Separate from the live stroke so it can sit behind a `RepaintBoundary`
/// and stay put while a finger is moving. Repainting a whole afternoon's
/// strokes on every touch event is what makes a drawing app go sludgy
/// twenty minutes in, which is exactly when a child is most invested.
class ArtworkPainter extends CustomPainter {
  ArtworkPainter({
    required this.asset,
    required this.artwork,
    required this.progress,
    required this.showGuide,
    required this.revision,
  });

  final DrawingAsset asset;
  final Artwork artwork;
  final TraceProgress progress;

  /// Whether to draw the dashed guide and its checkpoints. Off once the
  /// drawing is complete, so the finished picture is the child's, not a
  /// worksheet.
  final bool showGuide;

  /// Bumped by the screen whenever anything here changed. Comparing this
  /// is cheaper and more honest than deep-comparing a stroke list.
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final fit = CanvasFit.contain(
      asset.canvasSize,
      Vec2(size.width, size.height),
      padding: 12,
    );

    canvas.save();
    canvas.translate(fit.offset.x, fit.offset.y);
    canvas.scale(fit.scale);

    // Fills sit under the line art, so the outline always stays readable
    // however enthusiastically a region has been coloured.
    for (final region in asset.regions) {
      final key = artwork.fills[region.id];
      if (key == null) continue;
      final colour = PaintColor.byKey(key);
      if (colour == null) continue;
      canvas.drawPath(
        buildUiPath(region.path),
        Paint()..color = Color(colour.argb),
      );
    }

    for (final stroke in artwork.strokes) {
      _paintStroke(canvas, stroke);
    }

    final outline = buildUiPath(asset.outline);

    if (showGuide) {
      // The guide is a dashed version of the same line, drawn under the
      // solid outline so the two never fight.
      canvas.drawPath(
        _dash(outline, 22, 18),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = Sky.accentSoft,
      );
    }

    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = Sky.outline,
    );

    if (showGuide) {
      for (var i = 0; i < progress.dots.length; i++) {
        final d = progress.dots[i];
        final hit = progress.isHit(i);
        canvas.drawCircle(
          Offset(d.x, d.y),
          hit ? 13 : 10,
          Paint()..color = hit ? Sky.dotHit : Sky.dotPending,
        );
        if (hit) {
          // A ring on a completed checkpoint, so progress reads at a
          // glance from arm's length — which is how a tablet is held.
          canvas.drawCircle(
            Offset(d.x, d.y),
            13,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = Colors.white,
          );
        }
      }
    }

    canvas.restore();
  }

  static void _paintStroke(Canvas canvas, Stroke stroke) {
    final colour = stroke.color;
    canvas.drawPath(
      buildStrokePath(stroke),
      Paint()
        ..color = Color(colour.argb)
            .withValues(alpha: stroke.brush.opacity)
        ..isAntiAlias = true,
    );
  }

  /// Chops a path into dashes.
  ///
  /// Flutter has no dashed stroke, and a dashed guide is what says "draw
  /// along here" to someone who cannot read an instruction.
  static ui.Path _dash(ui.Path source, double on, double off) {
    final out = ui.Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + on).clamp(0.0, metric.length);
        out.addPath(metric.extractPath(distance, end), Offset.zero);
        distance = end + off;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(ArtworkPainter old) =>
      old.revision != revision ||
      old.showGuide != showGuide ||
      old.asset.id != asset.id;
}

/// Just the stroke currently under the finger.
///
/// Repaints every touch event, which is fine because it is one stroke.
class LiveStrokePainter extends CustomPainter {
  LiveStrokePainter({required this.asset, required this.stroke});

  final DrawingAsset asset;
  final Stroke? stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final s = stroke;
    if (s == null || s.isEmpty) return;

    final fit = CanvasFit.contain(
      asset.canvasSize,
      Vec2(size.width, size.height),
      padding: 12,
    );
    canvas.save();
    canvas.translate(fit.offset.x, fit.offset.y);
    canvas.scale(fit.scale);
    ArtworkPainter._paintStroke(canvas, s);
    canvas.restore();
  }

  @override
  bool shouldRepaint(LiveStrokePainter old) =>
      // Identity plus length: the builder mutates one stroke in place, so
      // comparing the object alone would never report a change.
      !identical(old.stroke, stroke) ||
      (old.stroke?.points.length ?? 0) != (stroke?.points.length ?? 0);
}

/// The little preview on a category card.
class ThumbnailPainter extends CustomPainter {
  ThumbnailPainter(this.asset, {this.tinted = true});

  final DrawingAsset asset;

  /// Cards show the art in its suggested colours so a child can tell a cow
  /// from a pig at thumbnail size — a b/w line drawing shrunk to a tile is
  /// a grey smudge.
  final bool tinted;

  @override
  void paint(Canvas canvas, Size size) {
    final fit = CanvasFit.contain(
      asset.canvasSize,
      Vec2(size.width, size.height),
      padding: 6,
    );
    canvas.save();
    canvas.translate(fit.offset.x, fit.offset.y);
    canvas.scale(fit.scale);

    if (tinted) {
      for (final r in asset.regions) {
        canvas.drawPath(
          buildUiPath(r.path),
          Paint()..color = Color(r.suggestedColor),
        );
      }
    }
    canvas.drawPath(
      buildUiPath(asset.outline),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeJoin = StrokeJoin.round
        ..color = Sky.outline,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(ThumbnailPainter old) =>
      old.asset.id != asset.id || old.tinted != tinted;
}
