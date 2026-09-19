/// Snap-to-line tracing, and knowing when a drawing is "finished".
///
/// Forgiveness is the whole design here. A five-year-old's line wanders,
/// and the app's job is to make that land on the drawing anyway — while
/// still not rewarding a scribble across the middle of the canvas.
library;

import 'dart:math' as math;

import 'geometry.dart';

/// How far off the outline a stroke may stray and still be pulled onto it.
///
/// In canvas units at the authored 1024 scale, so the tolerance scales with
/// the art rather than with the tablet: the same drawing forgives the same
/// amount whether it is shown on a 7" or an 11" screen.
const double kSnapTolerance = 46;

/// How close a stroke must pass to a checkpoint to light it up. Larger than
/// the snap tolerance on purpose — a dot you have visibly drawn through
/// should never fail to count, because "I did that bit and it didn't
/// notice" is the one thing that makes a child give up.
const double kDotTolerance = 58;

/// The fraction of checkpoints that have to be hit before the drawing is
/// celebrated. Not 1.0: insisting on every last dot turns a finished
/// picture into a hunt for the one dot behind the tail.
const double kCompletionThreshold = 0.85;

/// Pulls a drawn point towards the outline.
///
/// Fully snapped within [kSnapTolerance] would make the line feel magnetic
/// and not like the child's own; ignoring the outline entirely makes a
/// wobbly trace look like a scribble. So the pull eases in: near the line
/// it is almost complete, and it falls to nothing at the tolerance edge,
/// where the stroke is left exactly where the finger put it.
class SnapResult {
  const SnapResult(this.position, this.snapped, this.distance);

  final Vec2 position;

  /// Whether the point was near enough to be pulled at all.
  final bool snapped;

  /// How far the raw point was from the outline, in canvas units.
  final double distance;
}

SnapResult snapToOutline(
  Vec2 p,
  List<List<Vec2>> outlineSubpaths, {
  double tolerance = kSnapTolerance,
}) {
  var bestDistSq = double.infinity;
  Vec2? bestPoint;

  for (final sub in outlineSubpaths) {
    for (var i = 0; i < sub.length - 1; i++) {
      final a = sub[i], b = sub[i + 1];
      final dSq = distanceSquaredToSegment(p, a, b);
      if (dSq < bestDistSq) {
        bestDistSq = dSq;
        bestPoint = _closestPointOnSegment(p, a, b);
      }
    }
  }

  if (bestPoint == null) return SnapResult(p, false, double.infinity);

  final dist = _sqrt(bestDistSq);
  if (dist > tolerance) return SnapResult(p, false, dist);

  // Quadratic falloff: strong correction close in, releasing smoothly
  // rather than at a hard edge the finger can feel as a snag.
  final t = dist / tolerance;
  final pull = (1 - t) * (1 - t);
  return SnapResult(p.lerpTo(bestPoint, pull), true, dist);
}

Vec2 _closestPointOnSegment(Vec2 p, Vec2 a, Vec2 b) {
  final abx = b.x - a.x, aby = b.y - a.y;
  final lenSq = abx * abx + aby * aby;
  if (lenSq == 0) return a;
  var t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq;
  if (t < 0) {
    t = 0;
  } else if (t > 1) {
    t = 1;
  }
  return Vec2(a.x + abx * t, a.y + aby * t);
}

double _sqrt(double v) => v <= 0 ? 0 : math.sqrt(v);

/// Tracks which checkpoints have been drawn through.
///
/// Order-free: a child who starts at the tail and works backwards has
/// traced the dinosaur just as much as one who started at the nose.
/// Requiring a sequence would fail them for doing it their own way.
class TraceProgress {
  TraceProgress(this.dots)
      : _hit = List<bool>.filled(dots.length, false);

  final List<Vec2> dots;
  final List<bool> _hit;

  int get total => dots.length;
  int get hitCount => _hit.where((h) => h).length;

  bool isHit(int index) => _hit[index];

  double get fraction => total == 0 ? 0 : hitCount / total;

  bool get isComplete =>
      total > 0 && fraction >= kCompletionThreshold;

  /// Marks every checkpoint within [tolerance] of [p]. Returns the indices
  /// newly lit by this point, so the caller can make a sound for each one
  /// exactly once.
  List<int> registerPoint(Vec2 p, {double tolerance = kDotTolerance}) {
    final tolSq = tolerance * tolerance;
    final newly = <int>[];
    for (var i = 0; i < dots.length; i++) {
      if (_hit[i]) continue;
      if (p.distanceSquaredTo(dots[i]) <= tolSq) {
        _hit[i] = true;
        newly.add(i);
      }
    }
    return newly;
  }

  /// Marks checkpoints along a whole segment of travel.
  ///
  /// A fast drag delivers touch events a long way apart, and testing only
  /// the sampled positions skips every dot the finger swept straight over —
  /// which reads as the app not noticing you did the easy, fast part.
  List<int> registerSegment(
    Vec2 from,
    Vec2 to, {
    double tolerance = kDotTolerance,
  }) {
    final tolSq = tolerance * tolerance;
    final newly = <int>[];
    for (var i = 0; i < dots.length; i++) {
      if (_hit[i]) continue;
      if (distanceSquaredToSegment(dots[i], from, to) <= tolSq) {
        _hit[i] = true;
        newly.add(i);
      }
    }
    return newly;
  }

  void reset() {
    for (var i = 0; i < _hit.length; i++) {
      _hit[i] = false;
    }
  }

  List<bool> get snapshot => List.unmodifiable(_hit);
}
