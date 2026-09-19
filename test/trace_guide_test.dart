import 'package:flutter_test/flutter_test.dart';
import 'package:kidsdreamland/geometry.dart';
import 'package:kidsdreamland/trace_guide.dart';

void main() {
  final line = [
    [const Vec2(0, 0), const Vec2(1000, 0)],
  ];

  group('snapToOutline', () {
    test('a point on the line is left where it is', () {
      final r = snapToOutline(const Vec2(500, 0), line);
      expect(r.snapped, isTrue);
      expect(r.distance, closeTo(0, 1e-9));
      expect(r.position.y, closeTo(0, 1e-9));
    });

    test('a near miss is pulled most of the way onto the line', () {
      final r = snapToOutline(const Vec2(500, 5), line);
      expect(r.snapped, isTrue);
      // Close in, the pull is strong — but never all the way, or the line
      // stops feeling like the child's own. At 5 units off a 46-unit
      // tolerance that works out at about 79%.
      expect(r.position.y, lessThan(5 * 0.25));
      expect(r.position.y, greaterThan(0));
    });

    test('the pull eases out to nothing at the tolerance edge', () {
      final justInside =
          snapToOutline(const Vec2(500, kSnapTolerance - 0.01), line);
      expect(justInside.snapped, isTrue);
      // Essentially uncorrected at the boundary: no snag to feel.
      expect(
        justInside.position.y,
        closeTo(kSnapTolerance - 0.01, 0.05),
      );
    });

    test('beyond tolerance the point is untouched', () {
      final r = snapToOutline(const Vec2(500, kSnapTolerance + 10), line);
      expect(r.snapped, isFalse);
      expect(r.position, const Vec2(500, kSnapTolerance + 10));
    });

    test('correction is monotonic — never pulls harder further away', () {
      var previous = 0.0;
      for (var d = 1.0; d < kSnapTolerance; d += 1) {
        final r = snapToOutline(Vec2(500, d), line);
        final corrected = r.position.y;
        // The drawn point must move outward as the finger moves outward,
        // or the line jitters backwards under a steadily moving finger.
        expect(corrected, greaterThanOrEqualTo(previous - 1e-9));
        previous = corrected;
      }
    });

    test('an empty outline snaps nothing', () {
      final r = snapToOutline(const Vec2(5, 5), const []);
      expect(r.snapped, isFalse);
      expect(r.distance, double.infinity);
    });

    test('picks the nearest of several subpaths', () {
      final two = [
        [const Vec2(0, 0), const Vec2(100, 0)],
        [const Vec2(0, 200), const Vec2(100, 200)],
      ];
      final r = snapToOutline(const Vec2(50, 195), two);
      expect(r.snapped, isTrue);
      expect(r.position.y, greaterThan(190));
    });
  });

  group('TraceProgress', () {
    List<Vec2> dotsAlong(int n) =>
        [for (var i = 0; i < n; i++) Vec2(i * 100.0, 0)];

    test('starts empty', () {
      final p = TraceProgress(dotsAlong(10));
      expect(p.hitCount, 0);
      expect(p.fraction, 0);
      expect(p.isComplete, isFalse);
    });

    test('a point lights only the dots within tolerance', () {
      final p = TraceProgress(dotsAlong(10));
      final newly = p.registerPoint(const Vec2(0, 0));
      expect(newly, [0]);
      expect(p.isHit(0), isTrue);
      expect(p.isHit(1), isFalse);
    });

    test('a dot is reported newly hit exactly once', () {
      final p = TraceProgress(dotsAlong(5));
      expect(p.registerPoint(const Vec2(0, 0)), [0]);
      // Second pass over the same dot must report nothing, or the sound
      // for it fires on every touch event while a finger rests there.
      expect(p.registerPoint(const Vec2(0, 0)), isEmpty);
      expect(p.hitCount, 1);
    });

    test('a fast drag sweeps every dot it passed over', () {
      final p = TraceProgress(dotsAlong(10));
      // Two touch events 900 units apart: by-point testing would catch the
      // two ends and miss the eight dots in between.
      final newly = p.registerSegment(const Vec2(0, 0), const Vec2(900, 0));
      expect(newly.length, 10);
      expect(p.isComplete, isTrue);
    });

    test('a segment that misses the line lights nothing', () {
      final p = TraceProgress(dotsAlong(10));
      final newly = p.registerSegment(
          const Vec2(0, 500), const Vec2(900, 500));
      expect(newly, isEmpty);
    });

    test('completion does not demand every last dot', () {
      final p = TraceProgress(dotsAlong(20));
      for (var i = 0; i < 17; i++) {
        p.registerPoint(Vec2(i * 100.0, 0));
      }
      expect(p.fraction, closeTo(0.85, 1e-9));
      expect(p.isComplete, isTrue);
      expect(p.hitCount, lessThan(p.total));
    });

    test('just under the threshold is not complete', () {
      final p = TraceProgress(dotsAlong(20));
      for (var i = 0; i < 16; i++) {
        p.registerPoint(Vec2(i * 100.0, 0));
      }
      expect(p.isComplete, isFalse);
    });

    test('order does not matter', () {
      final forwards = TraceProgress(dotsAlong(20));
      final backwards = TraceProgress(dotsAlong(20));
      for (var i = 0; i < 18; i++) {
        forwards.registerPoint(Vec2(i * 100.0, 0));
      }
      for (var i = 19; i >= 2; i--) {
        backwards.registerPoint(Vec2(i * 100.0, 0));
      }
      expect(forwards.isComplete, backwards.isComplete);
      expect(forwards.hitCount, backwards.hitCount);
    });

    test('no dots is never complete rather than trivially complete', () {
      final p = TraceProgress(const []);
      expect(p.isComplete, isFalse);
      expect(p.fraction, 0);
    });

    test('reset clears progress', () {
      final p = TraceProgress(dotsAlong(5));
      p.registerSegment(const Vec2(0, 0), const Vec2(400, 0));
      expect(p.hitCount, 5);
      p.reset();
      expect(p.hitCount, 0);
    });
  });
}
