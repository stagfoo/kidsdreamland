import 'package:flutter_test/flutter_test.dart';
import 'package:kidsdreamland/geometry.dart';
import 'package:kidsdreamland/svg_path.dart';

void main() {
  group('parsing', () {
    test('absolute move and lines', () {
      final p = parseSvgPath('M 0 0 L 10 0 L 10 10');
      expect(p.subpaths.length, 1);
      expect(p.subpaths.first, [
        const Vec2(0, 0),
        const Vec2(10, 0),
        const Vec2(10, 10),
      ]);
    });

    test('relative commands accumulate from the cursor', () {
      final p = parseSvgPath('m 5 5 l 10 0 l 0 10');
      expect(p.subpaths.first, [
        const Vec2(5, 5),
        const Vec2(15, 5),
        const Vec2(15, 15),
      ]);
    });

    test('H and V move on one axis only', () {
      final p = parseSvgPath('M 1 2 H 9 V 8 h -4 v -3');
      expect(p.subpaths.first, [
        const Vec2(1, 2),
        const Vec2(9, 2),
        const Vec2(9, 8),
        const Vec2(5, 8),
        const Vec2(5, 5),
      ]);
    });

    test('a repeated pair after M is an implicit L', () {
      final p = parseSvgPath('M 0 0 5 0 10 0');
      expect(p.subpaths.first.length, 3);
      expect(p.subpaths.first.last, const Vec2(10, 0));
    });

    test('Z closes the subpath back to its start', () {
      final p = parseSvgPath('M 0 0 L 10 0 L 10 10 Z');
      // The closing edge must be a real segment, or distance-to-outline
      // reports the seam as off the line.
      expect(p.subpaths.first.last, const Vec2(0, 0));
      expect(p.subpaths.first.length, 4);
    });

    test('multiple subpaths — a hole inside a shape', () {
      final p = parseSvgPath(
          'M 0 0 L 10 0 L 10 10 L 0 10 Z M 4 4 L 6 4 L 6 6 L 4 6 Z');
      expect(p.subpaths.length, 2);
      expect(p.subpaths[1].first, const Vec2(4, 4));
    });

    test('a subpath of one point is dropped', () {
      final p = parseSvgPath('M 0 0 M 5 5 L 6 6');
      expect(p.subpaths.length, 1);
    });
  });

  group('curves', () {
    test('a cubic flattens to the requested segment count', () {
      final p = parseSvgPath('M 0 0 C 0 10 10 10 10 0',
          segmentsPerCurve: 8);
      expect(p.subpaths.first.length, 9); // start + 8
      expect(p.subpaths.first.last, const Vec2(10, 0));
    });

    test('a cubic passes through its endpoints and bulges between', () {
      final p = parseSvgPath('M 0 0 C 0 12 10 12 10 0',
          segmentsPerCurve: 16);
      final mid = p.subpaths.first[8];
      // Bezier midpoint of this curve is y = 9, not the control's 12.
      expect(mid.y, closeTo(9, 0.5));
    });

    test('a quadratic flattens too', () {
      final p =
          parseSvgPath('M 0 0 Q 5 10 10 0', segmentsPerCurve: 4);
      expect(p.subpaths.first.length, 5);
      expect(p.subpaths.first.last, const Vec2(10, 0));
    });

    test('S reflects the previous cubic control point', () {
      final p = parseSvgPath('M 0 0 C 0 5 5 5 5 0 S 10 -5 10 0',
          segmentsPerCurve: 4);
      expect(p.subpaths.first.last, const Vec2(10, 0));
    });

    test('S with no preceding curve uses the cursor as its control', () {
      final p =
          parseSvgPath('M 0 0 S 10 10 10 0', segmentsPerCurve: 4);
      expect(p.subpaths.first.last, const Vec2(10, 0));
    });

    test('T reflects the previous quadratic control point', () {
      final p =
          parseSvgPath('M 0 0 Q 5 10 10 0 T 20 0', segmentsPerCurve: 4);
      expect(p.subpaths.first.last, const Vec2(20, 0));
    });
  });

  group('number syntax', () {
    test('a minus sign separates numbers without a delimiter', () {
      final p = parseSvgPath('M0 0L10-5');
      expect(p.subpaths.first.last, const Vec2(10, -5));
    });

    test('a second decimal point starts a new number', () {
      final p = parseSvgPath('M0 0L.5.5');
      expect(p.subpaths.first.last, const Vec2(0.5, 0.5));
    });

    test('commas and newlines are separators', () {
      final p = parseSvgPath('M0,0\n  L10,10');
      expect(p.subpaths.first.last, const Vec2(10, 10));
    });

    test('exponent notation survives', () {
      final p = parseSvgPath('M0 0 L1e2 1E1');
      expect(p.subpaths.first.last, const Vec2(100, 10));
    });
  });

  group('failure', () {
    test('an unsupported command is refused, not silently mis-drawn', () {
      expect(() => parseSvgPath('M0 0 A 5 5 0 0 1 10 10'),
          throwsA(isA<SvgPathException>()));
    });

    test('data starting with a number is refused', () {
      expect(() => parseSvgPath('10 10 L 20 20'),
          throwsA(isA<SvgPathException>()));
    });

    test('a truncated command is refused', () {
      expect(() => parseSvgPath('M 0 0 L 10'),
          throwsA(isA<SvgPathException>()));
    });
  });

  test('bounds cover the flattened curve, not just the control points', () {
    final p = parseSvgPath('M 0 0 C 0 10 10 10 10 0');
    final b = p.bounds;
    expect(b.left, closeTo(0, 1e-9));
    expect(b.right, closeTo(10, 1e-9));
    expect(b.top, closeTo(0, 1e-9));
    // The curve peaks at 7.5, well below the control points' 10.
    expect(b.bottom, closeTo(7.5, 0.1));
  });
}
