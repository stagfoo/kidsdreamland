/// Turning a transparent line-art PNG into a traceable drawing asset.
///
/// The input is what a person draws in a paint app: dark ink on
/// transparency, the enclosed areas left empty. What the app needs is the
/// opposite shape of data — closed vector loops it can stroke as a trace
/// guide and fill as regions. This file is the bridge.
///
/// The key move is that **regions come first and the outline is derived
/// from them**. Tracing the ink itself would give the boundary of every
/// brush stroke — a double line down each side of the pencil mark, which
/// re-strokes into a fat outline of an outline. The enclosed empty cells
/// between the lines have exactly one boundary each, and that boundary is
/// the line the artist meant to draw. So: flood the gaps, take their
/// edges, and the drawn line falls out for free.
///
/// No Flutter imports. A PNG arrives here already decoded to RGBA bytes,
/// which keeps the whole pipeline testable against synthetic pixel grids
/// with no device and no image file.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';

/// The knobs the editor exposes as sliders.
///
/// Every one of these is continuous rather than a set of presets: the
/// right value for a given drawing is found by dragging until the overlay
/// looks right, and a stepped control always lands beside the number you
/// wanted.
class TraceOptions {
  const TraceOptions({
    this.alphaThreshold = 0.5,
    this.maxMaskEdge = 512,
    this.minRegionFraction = 0.004,
    this.simplify = 1.6,
    this.smoothing = 1,
    this.canvasSize = 1024,
    this.fillFraction = 0.88,
  });

  /// How opaque a pixel must be to count as ink, 0..1. Antialiased edges
  /// ramp through the middle, so the midpoint is the honest default.
  final double alphaThreshold;

  /// The mask is worked at most this many pixels on its long edge.
  ///
  /// A 2048-square PNG is four million flood-fill steps on a tablet CPU,
  /// and the extra resolution buys nothing: the result is simplified down
  /// to a few dozen points per loop anyway. Downsampling also swallows
  /// stray specks from a stylus.
  final int maxMaskEdge;

  /// Enclosed areas smaller than this fraction of the whole drawing are
  /// discarded as noise rather than offered as regions. A gap a child
  /// cannot land a fingertip in is not a region, it is a leak in the line.
  final double minRegionFraction;

  /// Douglas-Peucker tolerance in mask pixels. The raw boundary is a
  /// staircase of unit steps; this is what turns it back into a line.
  final double simplify;

  /// Rounds of Chaikin corner-cutting after simplification. One round
  /// takes the corners off the simplified polygon so a stroked loop reads
  /// as drawn rather than as a polygon. Zero keeps hard corners, which is
  /// what a drawing with real spikes — horns, teeth, a star — wants.
  final int smoothing;

  /// Assets are authored at 1024 square, and every tolerance in the app
  /// is expressed in those units.
  final double canvasSize;

  /// How much of the canvas the drawing is scaled to fill. Short of 1.0
  /// so a stroked outline is not clipped at the edge, and comfortably
  /// past the 0.5-wide / 0.3-tall floor the asset tests enforce.
  final double fillFraction;

  TraceOptions copyWith({
    double? alphaThreshold,
    int? maxMaskEdge,
    double? minRegionFraction,
    double? simplify,
    int? smoothing,
    double? canvasSize,
    double? fillFraction,
  }) {
    return TraceOptions(
      alphaThreshold: alphaThreshold ?? this.alphaThreshold,
      maxMaskEdge: maxMaskEdge ?? this.maxMaskEdge,
      minRegionFraction: minRegionFraction ?? this.minRegionFraction,
      simplify: simplify ?? this.simplify,
      smoothing: smoothing ?? this.smoothing,
      canvasSize: canvasSize ?? this.canvasSize,
      fillFraction: fillFraction ?? this.fillFraction,
    );
  }
}

/// One enclosed area the tracer found, already in canvas units.
class TracedRegion {
  TracedRegion({
    required this.id,
    required this.loops,
    required this.area,
    required this.interiorPoint,
  });

  /// A point known to be inside, in canvas units.
  ///
  /// Not the centre of the bounding box, which for a ring-shaped area —
  /// a body with a spot on it, the gap between two legs — lands in the
  /// hole rather than in the region. Taken instead from the widest
  /// horizontal run of pixels the area actually occupies, which is inside
  /// by construction and away from the edges.
  ///
  /// It is what proves a traced polygon really encloses the pixels it came
  /// from, and it is where Phase 3 will put the number.
  final Vec2 interiorPoint;

  /// Auto-assigned at trace time (`r1`, `r2`, ...) and renamed in the
  /// editor. Ids only ever have to be unique within one drawing.
  String id;

  /// The outer boundary first, then any islands of ink it surrounds.
  /// `ArtRegion.contains` is even-odd across subpaths, so a hole traced
  /// as a second loop cuts itself out with no extra machinery.
  final List<List<Vec2>> loops;

  /// Enclosed pixel area at mask scale. Used to order regions big-to-small
  /// and to reject specks; never shown.
  final double area;

  Bounds get bounds => Bounds.around(loops.first);

  String get pathData => loops.map(polygonToPath).join(' ');
}

/// What came back from a trace, before anybody has named anything.
class TracedArt {
  TracedArt({
    required this.silhouette,
    required this.regions,
    required this.canvasSize,
    required this.warnings,
    this.imageBounds = const Bounds(0, 0, 0, 0),
  });

  /// Where the whole source image lands in canvas units.
  ///
  /// The drawing is scaled and centred on its own ink, so the image it
  /// came from no longer sits at the origin. The editor needs this to lay
  /// the original back underneath the trace — which is the only way to
  /// see whether the trace is actually following the line.
  final Bounds imageBounds;

  /// The outer edge of the whole drawing — ink and everything it encloses.
  final List<List<Vec2>> silhouette;

  /// Big-to-small, which is also the order `Artwork.regionAt` needs: it
  /// searches last-first, so the smallest region is the one a tap on an
  /// eye finds rather than the head behind it.
  final List<TracedRegion> regions;

  final double canvasSize;

  /// Things worth telling the person at the tablet, in pictures-and-counts
  /// terms rather than as exceptions. A trace that found nothing is a
  /// normal outcome of a bad threshold, not an error.
  final List<TraceWarning> warnings;

  bool get isEmpty => silhouette.isEmpty;

  /// The whole drawn line: the silhouette plus every region boundary.
  /// Together these are the strokes the artist actually put down.
  List<List<Vec2>> get outlineLoops => [
        ...silhouette,
        for (final r in regions) ...r.loops,
      ];

  String get outlinePath => outlineLoops.map(polygonToPath).join(' ');
}

/// Why a trace might not be what you wanted, without saying so in words.
enum TraceWarning {
  /// Nothing crossed the alpha threshold. Almost always a PNG with no
  /// transparency, or the threshold dragged past the ink.
  noInk,

  /// Ink, but no enclosed areas — the line does not close, so there is
  /// nothing to fill. Still traceable, just not colourable.
  noRegions,

  /// Enclosed areas were found but every one was too small to keep.
  allRegionsTooSmall,

  /// The drawing touches the edge of the image, so its silhouette is
  /// partly the image border rather than the artist's line.
  touchesImageEdge,
}

/// Traces a decoded PNG.
///
/// [rgba] is row-major, four bytes per pixel, which is what
/// `Image.toByteData` hands back and what a test can write by hand.
TracedArt traceLineArt(
  Uint8List rgba,
  int width,
  int height, {
  TraceOptions options = const TraceOptions(),
}) {
  final warnings = <TraceWarning>[];

  final mask = _InkMask.fromRgba(rgba, width, height, options);
  if (!mask.anyInk) {
    return TracedArt(
      silhouette: const [],
      regions: const [],
      canvasSize: options.canvasSize,
      warnings: [TraceWarning.noInk],
    );
  }
  if (mask.inkTouchesBorder) warnings.add(TraceWarning.touchesImageEdge);

  // Flood the empty space. Whatever the outside reaches is background;
  // every other pocket of emptiness is an area the artist enclosed.
  final labels = _labelEmptySpace(mask);

  // Inside the drawing = not background. That is ink plus everything the
  // ink wraps around, which is exactly the silhouette.
  bool insideDrawing(int x, int y) {
    if (x < 0 || y < 0 || x >= mask.w || y >= mask.h) return false;
    return labels.at(x, y) != _kBackgroundLabel;
  }

  final rawSilhouette = traceLoops(insideDrawing, mask.w, mask.h);
  if (rawSilhouette.isEmpty) {
    return TracedArt(
      silhouette: const [],
      regions: const [],
      canvasSize: options.canvasSize,
      warnings: [TraceWarning.noInk],
    );
  }

  // Everything is scaled by one transform derived from the silhouette, so
  // regions stay registered to the outline they were cut from.
  final fit = _CanvasFit.forLoops(rawSilhouette, options);

  // Half a stroke, in canvas units. Both sides of every drawn line move
  // this far towards the middle of the ink, which is where the artist
  // actually put it.
  final nudge = mask.halfStrokeWidth * fit.scale;

  final silhouette = [
    for (final loop in rawSilhouette)
      offsetLoop(fit.apply(_finish(loop, options)), nudge),
  ];

  final silhouetteArea = rawSilhouette.fold<double>(
    0,
    (sum, loop) => sum + signedArea(loop).abs(),
  );

  final regions = <TracedRegion>[];
  var foundEnclosed = 0;
  var droppedSmall = 0;

  for (final label in labels.enclosedLabels) {
    foundEnclosed++;
    final area = labels.areaOf(label);
    if (area < silhouetteArea * options.minRegionFraction) {
      droppedSmall++;
      continue;
    }

    bool isThis(int x, int y) {
      if (x < 0 || y < 0 || x >= mask.w || y >= mask.h) return false;
      return labels.at(x, y) == label;
    }

    final loops = traceLoops(isThis, mask.w, mask.h);
    if (loops.isEmpty) continue;

    // Regions move the other way — outwards — so they meet the silhouette
    // on the line rather than stopping short of it.
    final placed = [
      for (final loop in loops)
        offsetLoop(fit.apply(_finish(loop, options)), -nudge),
    ];

    // The rule the asset tests enforce: 30 canvas units is about a
    // fingertip on a tablet, and a region narrower than that is a bit of
    // the picture that refuses to colour. Checked after scaling, because
    // that is the only place the number means anything.
    final b = Bounds.around(placed.first);
    if (b.width <= 32 || b.height <= 32) {
      droppedSmall++;
      continue;
    }

    regions.add(TracedRegion(
      id: '',
      loops: placed,
      area: area,
      interiorPoint: fit.apply([labels.widestPoint(label)]).first,
    ));
  }

  // Big-to-small. `Artwork.regionAt` searches last-first, so this ordering
  // is what makes a tap on a small part hit the small part.
  regions.sort((a, b) => b.area.compareTo(a.area));
  for (var i = 0; i < regions.length; i++) {
    regions[i].id = 'r${i + 1}';
  }

  if (foundEnclosed == 0) {
    warnings.add(TraceWarning.noRegions);
  } else if (regions.isEmpty && droppedSmall > 0) {
    warnings.add(TraceWarning.allRegionsTooSmall);
  }

  final topLeft = fit.apply([const Vec2(0, 0)]).first;
  final bottomRight =
      fit.apply([Vec2(mask.w.toDouble(), mask.h.toDouble())]).first;

  return TracedArt(
    silhouette: silhouette,
    regions: regions,
    canvasSize: options.canvasSize,
    warnings: warnings,
    imageBounds:
        Bounds(topLeft.x, topLeft.y, bottomRight.x, bottomRight.y),
  );
}

/// Simplify, then smooth. In that order: Chaikin on a raw staircase just
/// rounds off pixel steps, whereas Chaikin on an already-simplified
/// polygon rounds the corners that are actually in the drawing.
List<Vec2> _finish(List<Vec2> loop, TraceOptions o) {
  var pts = simplifyClosed(loop, o.simplify);
  for (var i = 0; i < o.smoothing; i++) {
    pts = chaikinClosed(pts);
  }
  return pts;
}

/// Slides a loop sideways by [distance], along the inward normal.
///
/// This is what stops every drawn line coming back as two.
///
/// A pencil line has thickness. The silhouette follows the *outside* of
/// that thickness and a region boundary follows the *inside*, so a body
/// outlined once by the artist arrives as two curves a stroke-width
/// apart — a tramline, most obvious exactly where the drawing is
/// simplest. Pushing the silhouette in by half a stroke and each region
/// out by half a stroke lands both on the middle of the ink, where the
/// artist's line actually is, and the two curves become one.
///
/// The side effect is worth having on its own: regions then reach the
/// centre of the line rather than stopping at its inner edge, so a filled
/// drawing has no pale halo left between the colour and the outline.
///
/// A corner has to travel further than [distance] to end up [distance]
/// from both of its edges — by `1/cos(half the turn)`, which at a right
/// angle is already a factor of √2. Moving every point the same amount
/// along its bisector instead leaves corners short, and on a shape the
/// simplifier has reduced to four points, *every* point is a corner: the
/// whole drawing then offsets by 70% of what it was asked for and the
/// tramline is narrower rather than gone.
///
/// The correction is clamped, because it runs away towards a spike. A
/// doubling-back point would otherwise fly off as a spur, which is far
/// more visible than the corner being a little round.
List<Vec2> offsetLoop(List<Vec2> loop, double distance) {
  if (loop.length < 3 || distance == 0) return loop;

  final out = <Vec2>[];
  for (var i = 0; i < loop.length; i++) {
    final prev = loop[(i - 1 + loop.length) % loop.length];
    final cur = loop[i];
    final next = loop[(i + 1) % loop.length];

    final n = _normal(prev, cur) + _normal(cur, next);
    final len = n.length;
    if (len < 1e-9) {
      // A point that doubles straight back has no meaningful side.
      // Leaving it where it is beats inventing a direction for it.
      out.add(cur);
      continue;
    }

    // For unit normals, |n1 + n2| is twice the cosine of the half-turn.
    final halfTurnCos = math.max(len / 2, 0.35);
    out.add(cur + n * (distance / (len * halfTurnCos)));
  }
  return out;
}

/// The inward normal of a directed edge, given that [traceLoops] always
/// leaves the inside on the right.
Vec2 _normal(Vec2 a, Vec2 b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len == 0) return const Vec2(0, 0);
  return Vec2(-dy / len, dx / len);
}

// ---------------------------------------------------------------- masking

/// A boolean ink grid, downsampled from the source pixels.
class _InkMask {
  _InkMask(this.w, this.h, this._bits, this.anyInk, this.inkTouchesBorder);

  final int w, h;
  final Uint8List _bits;
  final bool anyInk;
  final bool inkTouchesBorder;

  bool at(int x, int y) => _bits[y * w + x] != 0;

  bool _inside(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && at(x, y);

  /// How thick the artist's line is, in mask pixels.
  ///
  /// From area over perimeter, which for any long thin shape settles at
  /// half its width regardless of how it curves: a stroke of width `w` and
  /// length `L` has area `wL` and a boundary of about `2L`, so the ratio
  /// is `w/2`. Measuring the strokes directly — run lengths, say — reads
  /// a near-horizontal line as enormously wide and a vertical one as thin,
  /// which is the one thing this must not do.
  double get halfStrokeWidth {
    var area = 0;
    var perimeter = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (!at(x, y)) continue;
        area++;
        if (!_inside(x, y - 1)) perimeter++;
        if (!_inside(x, y + 1)) perimeter++;
        if (!_inside(x - 1, y)) perimeter++;
        if (!_inside(x + 1, y)) perimeter++;
      }
    }
    if (perimeter == 0) return 0;
    return area / perimeter;
  }

  /// Downsamples by taking the **most** opaque source pixel in each cell,
  /// never the average. A one-pixel line averaged down to a quarter scale
  /// fades below any threshold and the line develops gaps — and a gap in
  /// the line is not a cosmetic problem, it is two regions merging into
  /// one and the fill escaping into the next part of the animal.
  static _InkMask fromRgba(
    Uint8List rgba,
    int width,
    int height,
    TraceOptions o,
  ) {
    final longEdge = math.max(width, height);
    final step = longEdge <= o.maxMaskEdge
        ? 1
        : (longEdge / o.maxMaskEdge).ceil();
    final w = (width / step).ceil();
    final h = (height / step).ceil();

    final cutoff = (o.alphaThreshold.clamp(0.0, 1.0) * 255).round();
    final bits = Uint8List(w * h);
    var anyInk = false;
    var border = false;

    for (var my = 0; my < h; my++) {
      for (var mx = 0; mx < w; mx++) {
        var peak = 0;
        final y1 = math.min((my + 1) * step, height);
        final x1 = math.min((mx + 1) * step, width);
        for (var y = my * step; y < y1 && peak < cutoff; y++) {
          final row = y * width * 4;
          for (var x = mx * step; x < x1; x++) {
            final a = rgba[row + x * 4 + 3];
            if (a > peak) {
              peak = a;
              if (peak >= cutoff) break;
            }
          }
        }
        if (peak >= cutoff && cutoff > 0) {
          bits[my * w + mx] = 1;
          anyInk = true;
          if (mx == 0 || my == 0 || mx == w - 1 || my == h - 1) border = true;
        }
      }
    }

    return _InkMask(w, h, bits, anyInk, border);
  }
}

// ------------------------------------------------------------- components

const int _kBackgroundLabel = 1;

/// Connected-component labels over the *empty* pixels.
class _EmptySpaceLabels {
  _EmptySpaceLabels(this._labels, this._areas, this.w, this.h);

  final Int32List _labels;
  final Map<int, double> _areas;
  final int w, h;

  /// 0 is ink, 1 is the outside world, 2+ are enclosed pockets.
  int at(int x, int y) => _labels[y * w + x];

  double areaOf(int label) => _areas[label] ?? 0;

  /// The midpoint of the widest unbroken horizontal run of [label].
  ///
  /// A cheap stand-in for "the most interior point": it is inside by
  /// definition, and sitting in the middle of the widest part keeps it
  /// clear of the boundary, which matters because the boundary moves
  /// inwards slightly when the loop is simplified and smoothed.
  Vec2 widestPoint(int label) {
    var bestRun = 0;
    var best = const Vec2(0, 0);
    for (var y = 0; y < h; y++) {
      var run = 0;
      for (var x = 0; x <= w; x++) {
        if (x < w && at(x, y) == label) {
          run++;
          continue;
        }
        if (run > bestRun) {
          bestRun = run;
          best = Vec2(x - run / 2, y + 0.5);
        }
        run = 0;
      }
    }
    return best;
  }

  List<int> get enclosedLabels =>
      (_areas.keys.where((l) => l > _kBackgroundLabel).toList()
        ..sort());
}

/// Four-connected flood fill over everything that is not ink.
///
/// Four-connected rather than eight on purpose: an eight-connected fill
/// squeezes through a diagonal pinhole in the line, and one pinhole is
/// enough to merge a head into a body. Under four-connectivity a diagonal
/// touch of ink still counts as a closed wall, which is the forgiving
/// reading — and the artist's intention when two strokes meet.
_EmptySpaceLabels _labelEmptySpace(_InkMask mask) {
  final w = mask.w, h = mask.h;
  final labels = Int32List(w * h); // 0 = ink or unvisited empty
  final areas = <int, double>{};

  // The outside is flooded first, from every border pixel, so it owns
  // label 1 no matter how the drawing is placed.
  var next = _kBackgroundLabel;
  final queue = <int>[];

  void seed(int x, int y, int label) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    if (mask.at(x, y)) return;
    if (labels[y * w + x] != 0) return;
    labels[y * w + x] = label;
    queue.add(y * w + x);
  }

  double flood(int label) {
    var area = 0.0;
    while (queue.isNotEmpty) {
      final i = queue.removeLast();
      area++;
      final x = i % w, y = i ~/ w;
      seed(x + 1, y, label);
      seed(x - 1, y, label);
      seed(x, y + 1, label);
      seed(x, y - 1, label);
    }
    return area;
  }

  for (var x = 0; x < w; x++) {
    seed(x, 0, next);
    seed(x, h - 1, next);
  }
  for (var y = 0; y < h; y++) {
    seed(0, y, next);
    seed(w - 1, y, next);
  }
  areas[next] = flood(next);

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (mask.at(x, y) || labels[y * w + x] != 0) continue;
      next++;
      seed(x, y, next);
      areas[next] = flood(next);
    }
  }

  return _EmptySpaceLabels(labels, areas, w, h);
}

// ---------------------------------------------------------------- tracing

/// Walks the boundary of a pixel set and returns it as closed loops, in
/// grid-corner coordinates.
///
/// Works on the *cracks* between pixels rather than on pixel centres, so
/// the loop returned is the true edge of the shape and two shapes sharing
/// a wall get one boundary each rather than a shared half-pixel.
///
/// Every boundary edge is emitted with the inside on its right, which
/// makes each loop close on itself and makes the winding consistent —
/// worth having because the outer loop and an enclosed island then come
/// back with opposite signed area and can be told apart without a
/// point-in-polygon test.
List<List<Vec2>> traceLoops(
  bool Function(int x, int y) inside,
  int w,
  int h,
) {
  // Directed unit edges, keyed by their start corner. A corner has two
  // outgoing edges only where the shape pinches diagonally.
  final outgoing = <int, List<int>>{};
  final used = <int>{};
  int key(int x, int y) => y * (w + 3) + x;

  void edge(int x0, int y0, int x1, int y1) {
    (outgoing[key(x0, y0)] ??= <int>[]).add(key(x1, y1));
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!inside(x, y)) continue;
      if (!inside(x, y - 1)) edge(x, y, x + 1, y);
      if (!inside(x + 1, y)) edge(x + 1, y, x + 1, y + 1);
      if (!inside(x, y + 1)) edge(x + 1, y + 1, x, y + 1);
      if (!inside(x - 1, y)) edge(x, y + 1, x, y);
    }
  }

  Vec2 corner(int k) =>
      Vec2((k % (w + 3)).toDouble(), (k ~/ (w + 3)).toDouble());

  final loops = <List<Vec2>>[];

  for (final start in outgoing.keys.toList()..sort()) {
    for (final firstEnd in outgoing[start]!) {
      final firstStep = _edgeId(start, firstEnd);
      if (used.contains(firstStep)) continue;

      final loop = <Vec2>[corner(start)];
      var from = start;
      var to = firstEnd;

      while (true) {
        used.add(_edgeId(from, to));
        loop.add(corner(to));
        if (to == start) break;

        final candidates = outgoing[to];
        if (candidates == null) break; // open chain: cannot happen, but
        // a malformed mask should not hang the tablet.

        final incoming = corner(to) - corner(from);
        int? pick;
        var bestTurn = double.infinity;
        for (final c in candidates) {
          if (used.contains(_edgeId(to, c))) continue;
          // Prefer the sharpest right turn. At a diagonal pinch that
          // splits the figure-eight into two clean loops instead of one
          // self-crossing one.
          final turn = _turnCost(incoming, corner(c) - corner(to));
          if (turn < bestTurn) {
            bestTurn = turn;
            pick = c;
          }
        }
        if (pick == null) break;
        from = to;
        to = pick;
      }

      // A loop needs a triangle's worth of corners to enclose anything.
      if (loop.length > 3) loops.add(loop..removeLast());
    }
  }

  // Largest first, so a caller taking `.first` gets the outer boundary
  // rather than whichever island happened to be scanned first.
  loops.sort((a, b) => signedArea(b).abs().compareTo(signedArea(a).abs()));
  return loops;
}

int _edgeId(int from, int to) => from * 0x40000000 ^ to;

/// 0 for a right turn, 1 for straight on, 2 for a left turn, 3 for going
/// back the way we came. Only the ordering matters.
double _turnCost(Vec2 incoming, Vec2 outgoing) {
  final cross = incoming.x * outgoing.y - incoming.y * outgoing.x;
  final dot = incoming.x * outgoing.x + incoming.y * outgoing.y;
  if (cross > 0) return 0; // right, in screen coordinates with y down
  if (dot > 0) return 1;
  if (cross < 0) return 2;
  return 3;
}

/// Shoelace. Positive or negative tells you the winding; the magnitude is
/// twice the enclosed area, which is only ever compared against itself
/// here so the factor does not matter.
double signedArea(List<Vec2> loop) {
  var sum = 0.0;
  for (var i = 0; i < loop.length; i++) {
    final a = loop[i], b = loop[(i + 1) % loop.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum / 2;
}

// ------------------------------------------------------------ simplifying

/// Douglas-Peucker over a closed loop.
///
/// Anchored at the two points furthest apart rather than at index zero:
/// a loop has no natural start, and anchoring at an arbitrary one leaves
/// a kink there that survives every later smoothing pass.
List<Vec2> simplifyClosed(List<Vec2> loop, double epsilon) {
  if (loop.length < 4 || epsilon <= 0) return loop;

  var a = 0, b = 0;
  var best = -1.0;
  for (var i = 1; i < loop.length; i++) {
    final d = loop[0].distanceSquaredTo(loop[i]);
    if (d > best) {
      best = d;
      b = i;
    }
  }
  best = -1.0;
  for (var i = 0; i < loop.length; i++) {
    final d = loop[b].distanceSquaredTo(loop[i]);
    if (d > best) {
      best = d;
      a = i;
    }
  }
  if (a == b) return loop;

  final firstHalf = <Vec2>[];
  for (var i = a; i != b; i = (i + 1) % loop.length) {
    firstHalf.add(loop[i]);
  }
  firstHalf.add(loop[b]);

  final secondHalf = <Vec2>[];
  for (var i = b; i != a; i = (i + 1) % loop.length) {
    secondHalf.add(loop[i]);
  }
  secondHalf.add(loop[a]);

  final out = <Vec2>[
    ..._douglasPeucker(firstHalf, epsilon),
    ..._douglasPeucker(secondHalf, epsilon).skip(1),
  ];
  if (out.length > 1) out.removeLast(); // the closing point is implicit
  return out.length < 3 ? loop : out;
}

List<Vec2> _douglasPeucker(List<Vec2> pts, double epsilon) {
  if (pts.length < 3) return pts;
  final epsSq = epsilon * epsilon;

  var worst = 0.0;
  var index = 0;
  for (var i = 1; i < pts.length - 1; i++) {
    final d = distanceSquaredToSegment(pts[i], pts.first, pts.last);
    if (d > worst) {
      worst = d;
      index = i;
    }
  }

  if (worst <= epsSq) return [pts.first, pts.last];

  final left = _douglasPeucker(pts.sublist(0, index + 1), epsilon);
  final right = _douglasPeucker(pts.sublist(index), epsilon);
  return [...left, ...right.skip(1)];
}

/// One round of Chaikin corner-cutting on a closed loop.
///
/// Each corner is replaced by the points a quarter and three quarters
/// along its edges, which rounds it without chasing the curve through a
/// spline fit. Two rounds is already mush at this scale; the default is
/// one, and a drawing with real spikes wants zero.
List<Vec2> chaikinClosed(List<Vec2> loop) {
  if (loop.length < 3) return loop;
  final out = <Vec2>[];
  for (var i = 0; i < loop.length; i++) {
    final a = loop[i], b = loop[(i + 1) % loop.length];
    out.add(a.lerpTo(b, 0.25));
    out.add(a.lerpTo(b, 0.75));
  }
  return out;
}

// --------------------------------------------------------------- fitting

/// The one scale-and-centre that takes mask pixels to canvas units.
class _CanvasFit {
  const _CanvasFit(this.scale, this.dx, this.dy);

  final double scale, dx, dy;

  static _CanvasFit forLoops(List<List<Vec2>> loops, TraceOptions o) {
    final b = Bounds.around(loops.expand((l) => l));
    final target = o.canvasSize * o.fillFraction;
    final scale = b.width <= 0 || b.height <= 0
        ? 1.0
        : math.min(target / b.width, target / b.height);
    return _CanvasFit(
      scale,
      o.canvasSize / 2 - b.centre.x * scale,
      o.canvasSize / 2 - b.centre.y * scale,
    );
  }

  List<Vec2> apply(List<Vec2> pts) => [
        for (final p in pts) Vec2(p.x * scale + dx, p.y * scale + dy),
      ];
}

/// A closed polygon as SVG path data. Polylines only — the app's parser
/// handles curves, but a traced boundary has no curve information to
/// preserve, and `M/L/Z` keeps the file honest about that.
String polygonToPath(List<Vec2> pts) {
  if (pts.isEmpty) return '';
  final b = StringBuffer('M ${pts.first.x.toStringAsFixed(1)} '
      '${pts.first.y.toStringAsFixed(1)}');
  for (final p in pts.skip(1)) {
    b.write(' L ${p.x.toStringAsFixed(1)} ${p.y.toStringAsFixed(1)}');
  }
  b.write(' Z');
  return b.toString();
}
