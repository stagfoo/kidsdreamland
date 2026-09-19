/// Plain-Dart geometry. No Flutter imports, so every one of these is
/// testable with `flutter test` and no device attached — which matters
/// because tracing tolerance and region hit-testing are exactly the
/// things that are miserable to debug on a tablet held by a five-year-old.
library;

import 'dart:math' as math;

/// A point. Deliberately not `Offset`: that would drag in dart:ui and put
/// this file on the wrong side of the pure/UI line.
class Vec2 {
  const Vec2(this.x, this.y);

  final double x, y;

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double s) => Vec2(x * s, y * s);

  double get length => math.sqrt(x * x + y * y);

  double distanceTo(Vec2 o) {
    final dx = x - o.x, dy = y - o.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Squared distance. Comparing squares avoids a `sqrt` per candidate in
  /// the hot loops below, where this runs once per outline segment per
  /// touch event.
  double distanceSquaredTo(Vec2 o) {
    final dx = x - o.x, dy = y - o.y;
    return dx * dx + dy * dy;
  }

  Vec2 lerpTo(Vec2 o, double t) => Vec2(x + (o.x - x) * t, y + (o.y - y) * t);

  @override
  bool operator ==(Object other) =>
      other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() =>
      'Vec2(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

/// An axis-aligned box. Used for cheap rejection before the expensive
/// per-segment work, and to fit a 1024x1024 asset onto whatever canvas
/// the tablet actually gives us.
class Bounds {
  const Bounds(this.left, this.top, this.right, this.bottom);

  final double left, top, right, bottom;

  double get width => right - left;
  double get height => bottom - top;
  Vec2 get centre => Vec2((left + right) / 2, (top + bottom) / 2);

  bool contains(Vec2 p) =>
      p.x >= left && p.x <= right && p.y >= top && p.y <= bottom;

  /// Grown by [d] on every side. A tap just outside a region should still
  /// count for a child, so hit-testing inflates before it rejects.
  Bounds inflate(double d) =>
      Bounds(left - d, top - d, right + d, bottom + d);

  static Bounds around(Iterable<Vec2> points) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    if (minX > maxX) return const Bounds(0, 0, 0, 0);
    return Bounds(minX, minY, maxX, maxY);
  }

  @override
  String toString() => 'Bounds($left, $top, $right, $bottom)';
}

/// Shortest distance from [p] to the segment [a]-[b], squared.
///
/// Segment rather than infinite line: a trace guide is made of short
/// segments, and the infinite-line distance would report a stroke as
/// "on the line" when it is level with a segment but far past its end.
double distanceSquaredToSegment(Vec2 p, Vec2 a, Vec2 b) {
  final abx = b.x - a.x, aby = b.y - a.y;
  final apx = p.x - a.x, apy = p.y - a.y;
  final abLenSq = abx * abx + aby * aby;
  if (abLenSq == 0) return p.distanceSquaredTo(a);
  // Projection of ap onto ab, clamped to the segment's own extent.
  var t = (apx * abx + apy * aby) / abLenSq;
  if (t < 0) {
    t = 0;
  } else if (t > 1) {
    t = 1;
  }
  final cx = a.x + abx * t, cy = a.y + aby * t;
  final dx = p.x - cx, dy = p.y - cy;
  return dx * dx + dy * dy;
}

/// Shortest distance from [p] to a polyline, squared. `infinity` for a
/// polyline with no points, so callers comparing against a tolerance
/// treat "no guide" as "nothing is near it" rather than as a match.
double distanceSquaredToPolyline(Vec2 p, List<Vec2> points) {
  if (points.isEmpty) return double.infinity;
  if (points.length == 1) return p.distanceSquaredTo(points.first);
  var best = double.infinity;
  for (var i = 0; i < points.length - 1; i++) {
    final d = distanceSquaredToSegment(p, points[i], points[i + 1]);
    if (d < best) best = d;
  }
  return best;
}

/// Even-odd point-in-polygon, matching how the renderer fills a path with
/// holes. A dinosaur's eye is a hole punched in its head, and a fill that
/// used a different rule to the painter would colour the eye in.
bool pointInPolygon(Vec2 p, List<Vec2> polygon) {
  if (polygon.length < 3) return false;
  var inside = false;
  var j = polygon.length - 1;
  for (var i = 0; i < polygon.length; i++) {
    final pi = polygon[i], pj = polygon[j];
    // Half-open vertical test: a vertex exactly at p.y counts for the
    // segment below it only, so a ray through a vertex crosses once, not
    // twice or zero times.
    if ((pi.y > p.y) != (pj.y > p.y)) {
      final xCross = (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x;
      if (p.x < xCross) inside = !inside;
    }
    j = i;
  }
  return inside;
}

/// Total length along a polyline. Used to space trace checkpoints evenly
/// rather than by vertex index — an authored path has dense vertices on
/// curves and sparse ones on straights, so by-index spacing bunches the
/// dots up exactly where the drawing is fiddliest.
double polylineLength(List<Vec2> points) {
  var total = 0.0;
  for (var i = 0; i < points.length - 1; i++) {
    total += points[i].distanceTo(points[i + 1]);
  }
  return total;
}

/// [count] points spread at equal arc-length along [points], endpoints
/// included. Returns an empty list if there is nothing to walk.
List<Vec2> sampleEvenly(List<Vec2> points, int count) {
  if (points.isEmpty || count <= 0) return const [];
  if (points.length == 1 || count == 1) return [points.first];
  final total = polylineLength(points);
  if (total == 0) return List.filled(count, points.first);

  final step = total / (count - 1);
  final out = <Vec2>[points.first];
  var segment = 0;
  var walked = 0.0; // distance consumed within the current segment
  for (var i = 1; i < count - 1; i++) {
    var remaining = step;
    while (segment < points.length - 1) {
      final segLen = points[segment].distanceTo(points[segment + 1]);
      final left = segLen - walked;
      if (left > remaining) {
        walked += remaining;
        remaining = 0;
        break;
      }
      remaining -= left;
      walked = 0;
      segment++;
    }
    if (segment >= points.length - 1) break;
    final segLen = points[segment].distanceTo(points[segment + 1]);
    final t = segLen == 0 ? 0.0 : walked / segLen;
    out.add(points[segment].lerpTo(points[segment + 1], t));
  }
  out.add(points.last);
  return out;
}
