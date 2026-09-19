import 'package:flutter_test/flutter_test.dart';
import 'package:kidsdreamland/geometry.dart';

void main() {
  group('distanceSquaredToSegment', () {
    test('projects onto the segment interior', () {
      final d = distanceSquaredToSegment(
          const Vec2(5, 3), const Vec2(0, 0), const Vec2(10, 0));
      expect(d, closeTo(9, 1e-9));
    });

    test('clamps past the ends rather than using the infinite line', () {
      // Level with the line but well past its end: the infinite-line
      // distance would be 0, which is exactly the bug this guards.
      final d = distanceSquaredToSegment(
          const Vec2(50, 0), const Vec2(0, 0), const Vec2(10, 0));
      expect(d, closeTo(1600, 1e-9));
    });

    test('handles a degenerate zero-length segment', () {
      final d = distanceSquaredToSegment(
          const Vec2(3, 4), const Vec2(0, 0), const Vec2(0, 0));
      expect(d, closeTo(25, 1e-9));
    });
  });

  group('distanceSquaredToPolyline', () {
    test('is infinity for an empty polyline', () {
      expect(distanceSquaredToPolyline(const Vec2(0, 0), const []),
          double.infinity);
    });

    test('falls back to the point for a single-point polyline', () {
      expect(
        distanceSquaredToPolyline(const Vec2(3, 4), const [Vec2(0, 0)]),
        closeTo(25, 1e-9),
      );
    });

    test('takes the nearest of several segments', () {
      final poly = [
        const Vec2(0, 0),
        const Vec2(10, 0),
        const Vec2(10, 10),
      ];
      expect(distanceSquaredToPolyline(const Vec2(11, 5), poly),
          closeTo(1, 1e-9));
    });
  });

  group('pointInPolygon', () {
    final square = [
      const Vec2(0, 0),
      const Vec2(10, 0),
      const Vec2(10, 10),
      const Vec2(0, 10),
    ];

    test('inside and outside', () {
      expect(pointInPolygon(const Vec2(5, 5), square), isTrue);
      expect(pointInPolygon(const Vec2(15, 5), square), isFalse);
      expect(pointInPolygon(const Vec2(-1, 5), square), isFalse);
    });

    test('a ray through a vertex still crosses exactly once', () {
      // y=10 passes through two vertices. A naive test double-counts or
      // misses them and reports the interior as outside.
      expect(pointInPolygon(const Vec2(5, 10), square), isFalse);
      expect(pointInPolygon(const Vec2(5, 0), square), isTrue);
    });

    test('degenerate polygons contain nothing', () {
      expect(pointInPolygon(const Vec2(0, 0), const [Vec2(0, 0)]), isFalse);
      expect(
        pointInPolygon(const Vec2(0, 0), const [Vec2(0, 0), Vec2(1, 1)]),
        isFalse,
      );
    });

    test('concave shapes exclude the notch', () {
      // An L, with the missing quadrant at the top right.
      final l = [
        const Vec2(0, 0),
        const Vec2(10, 0),
        const Vec2(10, 5),
        const Vec2(5, 5),
        const Vec2(5, 10),
        const Vec2(0, 10),
      ];
      expect(pointInPolygon(const Vec2(2, 2), l), isTrue);
      expect(pointInPolygon(const Vec2(8, 8), l), isFalse);
    });
  });

  group('sampleEvenly', () {
    test('spaces by arc length, not by vertex index', () {
      // Vertices bunch at the start; even sampling must ignore that.
      final poly = [
        const Vec2(0, 0),
        const Vec2(1, 0),
        const Vec2(2, 0),
        const Vec2(100, 0),
      ];
      final s = sampleEvenly(poly, 3);
      expect(s.length, 3);
      expect(s.first.x, closeTo(0, 1e-6));
      expect(s[1].x, closeTo(50, 1e-6));
      expect(s.last.x, closeTo(100, 1e-6));
    });

    test('keeps both endpoints', () {
      final poly = [const Vec2(0, 0), const Vec2(9, 0)];
      final s = sampleEvenly(poly, 4);
      expect(s.first, const Vec2(0, 0));
      expect(s.last, const Vec2(9, 0));
      expect(s.length, 4);
    });

    test('edge cases do not throw', () {
      expect(sampleEvenly(const [], 5), isEmpty);
      expect(sampleEvenly(const [Vec2(1, 1)], 5), [const Vec2(1, 1)]);
      expect(sampleEvenly(const [Vec2(1, 1), Vec2(2, 2)], 0), isEmpty);
      // A zero-length polyline still has to return the requested count
      // rather than dividing by its own length.
      final degenerate =
          sampleEvenly(const [Vec2(1, 1), Vec2(1, 1)], 3);
      expect(degenerate.length, 3);
    });
  });

  group('Bounds', () {
    test('around a set of points', () {
      final b = Bounds.around(
          const [Vec2(1, 5), Vec2(-2, 3), Vec2(4, -1)]);
      expect(b.left, -2);
      expect(b.top, -1);
      expect(b.right, 4);
      expect(b.bottom, 5);
    });

    test('around nothing is empty rather than infinite', () {
      final b = Bounds.around(const []);
      expect(b.width, 0);
      expect(b.height, 0);
    });

    test('inflate grows every side', () {
      final b = const Bounds(0, 0, 10, 10).inflate(2);
      expect(b.contains(const Vec2(-1, -1)), isTrue);
      expect(b.contains(const Vec2(-3, 0)), isFalse);
    });
  });

  test('polylineLength sums the segments', () {
    expect(
      polylineLength(const [Vec2(0, 0), Vec2(3, 4), Vec2(3, 14)]),
      closeTo(15, 1e-9),
    );
    expect(polylineLength(const [Vec2(0, 0)]), 0);
  });
}
