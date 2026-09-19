/// The one asset format all three modes read, and its JSON parsing.
///
/// Authoring an image once and letting each mode take what it needs is the
/// whole point: trace wants the outline and the checkpoints, mirror wants
/// the axis, paint-by-number wants the regions and their numbers.
///
/// `number` and `symmetryAxis` are optional, so art production can stay
/// ahead of mode development — an asset drawn today is trace-ready now and
/// gains its numbers whenever Phase 3 arrives, rather than blocking on
/// fields for modes that do not exist yet.
library;

import 'geometry.dart';
import 'svg_path.dart';

class AssetFormatException implements Exception {
  AssetFormatException(this.message);
  final String message;
  @override
  String toString() => 'AssetFormatException: $message';
}

/// Where a mirror-drawing axis runs. Only vertical for now — it is the one
/// a child reads instantly (butterfly, face) and the only one Phase 2
/// commits to.
enum SymmetryType { vertical, horizontal }

class SymmetryAxis {
  const SymmetryAxis(this.type, this.position);

  final SymmetryType type;

  /// x for a vertical axis, y for a horizontal one, in canvas units.
  final double position;
}

/// One fillable area of the drawing.
class ArtRegion {
  ArtRegion({
    required this.id,
    required this.path,
    required this.suggestedColor,
    this.number,
  });

  final String id;
  final ParsedPath path;

  /// Phase 1's default fill hint, and Phase 3's answer key. An ARGB value.
  final int suggestedColor;

  /// Phase 3's label. Null until an asset has been given numbers.
  final int? number;

  late final Bounds bounds = path.bounds;

  /// Whether [p], in canvas units, falls inside this region.
  ///
  /// Even-odd across every subpath, which is what makes a hole behave like
  /// a hole: a point inside both the head and the eye cut out of it
  /// crosses two boundaries and lands outside.
  bool contains(Vec2 p) {
    if (!bounds.contains(p)) return false;
    var inside = false;
    for (final sub in path.subpaths) {
      if (pointInPolygon(p, sub)) inside = !inside;
    }
    return inside;
  }
}

class DrawingAsset {
  DrawingAsset({
    required this.id,
    required this.category,
    required this.title,
    required this.canvasSize,
    required this.outline,
    required this.guideDots,
    required this.regions,
    this.symmetryAxis,
  });

  final String id;
  final String category;

  /// Shown nowhere in the app — the audience cannot read. It exists for
  /// the asset files to stay legible to whoever is authoring them, and for
  /// accessibility labels.
  final String title;

  final Vec2 canvasSize;
  final ParsedPath outline;

  /// Checkpoints along the outline, in drawing order. Authored explicitly
  /// where an asset wants them, otherwise spaced evenly along the outline
  /// at load time — even spacing by arc length, not by vertex, so dots do
  /// not bunch up on the curves.
  final List<Vec2> guideDots;

  final List<ArtRegion> regions;
  final SymmetryAxis? symmetryAxis;

  /// The axis Phase 2 will actually use: the authored one, or a vertical
  /// line down the middle of the canvas. Every asset is mirror-drawable
  /// whether or not anyone thought about it at authoring time.
  SymmetryAxis get effectiveSymmetryAxis =>
      symmetryAxis ??
      SymmetryAxis(SymmetryType.vertical, canvasSize.x / 2);

  /// Whether this asset has been given paint-by-number labels yet.
  bool get supportsNumbers =>
      regions.isNotEmpty && regions.every((r) => r.number != null);

  /// 1, 2 or 3 — the "how much detail" mark on a category card.
  ///
  /// Derived from the art rather than authored, so it can never drift out
  /// of step with the drawing it describes, and so adding an image is one
  /// file and no bookkeeping. Region count leads because it is what a
  /// child actually feels: more pieces to fill is more work than a longer
  /// line.
  int get difficulty {
    final score = regions.length * 2 + guideDots.length ~/ 8;
    if (score <= 6) return 1;
    if (score <= 12) return 2;
    return 3;
  }

  static DrawingAsset fromJson(Map<String, dynamic> json) {
    String str(String key) {
      final v = json[key];
      if (v is! String || v.isEmpty) {
        throw AssetFormatException('"$key" must be a non-empty string');
      }
      return v;
    }

    final canvas = json['canvas'];
    if (canvas is! Map) throw AssetFormatException('"canvas" is required');
    final size = Vec2(
      (canvas['width'] as num).toDouble(),
      (canvas['height'] as num).toDouble(),
    );
    if (size.x <= 0 || size.y <= 0) {
      throw AssetFormatException('canvas must have a positive size');
    }

    final outline = parseSvgPath(str('outline'));
    if (outline.subpaths.isEmpty) {
      throw AssetFormatException('"outline" flattened to nothing');
    }

    final regions = <ArtRegion>[];
    for (final raw in (json['regions'] as List? ?? const [])) {
      final r = raw as Map;
      final path = parseSvgPath(r['path'] as String);
      if (path.subpaths.isEmpty) {
        throw AssetFormatException(
          'region "${r['id']}" flattened to nothing',
        );
      }
      regions.add(ArtRegion(
        id: r['id'] as String,
        path: path,
        suggestedColor: parseHexColor(r['suggestedColor'] as String),
        number: (r['number'] as num?)?.toInt(),
      ));
    }

    final dotsJson = json['guideDots'] as List?;
    final dots = dotsJson == null || dotsJson.isEmpty
        // Unauthored: space them along the outline. 1 dot per ~90 canvas
        // units at the authored 1024 scale, floored at 8 and capped at 60 —
        // below 8 there is nothing to follow, above 60 they crowd into a
        // dotted line and stop reading as checkpoints.
        ? sampleEvenly(
            outline.allPoints,
            (polylineLength(outline.allPoints) / 90).round().clamp(8, 60),
          )
        : [
            for (final d in dotsJson)
              Vec2(
                ((d as Map)['x'] as num).toDouble(),
                (d['y'] as num).toDouble(),
              ),
          ];

    SymmetryAxis? axis;
    final axisJson = json['symmetryAxis'];
    if (axisJson is Map) {
      final type = axisJson['type'] == 'horizontal'
          ? SymmetryType.horizontal
          : SymmetryType.vertical;
      final pos = type == SymmetryType.vertical
          ? (axisJson['x'] as num?)?.toDouble() ?? size.x / 2
          : (axisJson['y'] as num?)?.toDouble() ?? size.y / 2;
      axis = SymmetryAxis(type, pos);
    }

    return DrawingAsset(
      id: str('id'),
      category: str('category'),
      title: json['title'] as String? ?? str('id'),
      canvasSize: size,
      outline: outline,
      guideDots: dots,
      regions: regions,
      symmetryAxis: axis,
    );
  }
}

/// `#RRGGBB` or `#AARRGGBB` to an ARGB int. Throws rather than falling back
/// to a default: a typo in an asset file should fail loudly at load, not
/// paint one region an unexplained black on a child's tablet.
int parseHexColor(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) {
    throw AssetFormatException('"$hex" is not #RRGGBB or #AARRGGBB');
  }
  final v = int.tryParse(h, radix: 16);
  if (v == null) throw AssetFormatException('"$hex" is not hexadecimal');
  return v;
}
