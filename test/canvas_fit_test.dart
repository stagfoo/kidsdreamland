import 'package:flutter_test/flutter_test.dart';
import 'package:kidsdreamland/canvas_fit.dart';
import 'package:kidsdreamland/geometry.dart';

void main() {
  test('a square canvas in a wide box is centred horizontally', () {
    final f = CanvasFit.contain(const Vec2(1024, 1024), const Vec2(2000, 1000));
    expect(f.scale, closeTo(1000 / 1024, 1e-9));
    expect(f.offset.y, closeTo(0, 1e-9));
    expect(f.offset.x, greaterThan(0));
    // Centred: equal bars either side.
    expect(f.offset.x * 2 + 1024 * f.scale, closeTo(2000, 1e-6));
  });

  test('a square canvas in a tall box is centred vertically', () {
    final f = CanvasFit.contain(const Vec2(1024, 1024), const Vec2(800, 1600));
    expect(f.scale, closeTo(800 / 1024, 1e-9));
    expect(f.offset.x, closeTo(0, 1e-9));
    expect(f.offset.y, greaterThan(0));
  });

  test('padding shrinks the drawing, not the centring', () {
    final f = CanvasFit.contain(const Vec2(1000, 1000), const Vec2(1000, 1000),
        padding: 50);
    expect(f.scale, closeTo(0.9, 1e-9));
    expect(f.offset.x, closeTo(50, 1e-6));
    expect(f.offset.y, closeTo(50, 1e-6));
  });

  test('toScreen and toCanvas are exact inverses', () {
    final f = CanvasFit.contain(const Vec2(1024, 1024), const Vec2(1440, 900),
        padding: 24);
    for (final p in const [
      Vec2(0, 0),
      Vec2(1024, 1024),
      Vec2(512, 512),
      Vec2(137.5, 900.25),
    ]) {
      final back = f.toCanvas(f.toScreen(p));
      // If these drift, a drawing fits but touches land somewhere else.
      expect(back.x, closeTo(p.x, 1e-9));
      expect(back.y, closeTo(p.y, 1e-9));
    }
  });

  test('the whole canvas lands inside the box', () {
    final f = CanvasFit.contain(const Vec2(1024, 1024), const Vec2(1440, 900));
    final tl = f.toScreen(const Vec2(0, 0));
    final br = f.toScreen(const Vec2(1024, 1024));
    expect(tl.x, greaterThanOrEqualTo(-1e-9));
    expect(tl.y, greaterThanOrEqualTo(-1e-9));
    expect(br.x, lessThanOrEqualTo(1440 + 1e-9));
    expect(br.y, lessThanOrEqualTo(900 + 1e-9));
  });

  test('degenerate boxes do not divide by zero', () {
    final f = CanvasFit.contain(const Vec2(1024, 1024), const Vec2(0, 0));
    expect(f.scale, 1);
    final g = CanvasFit.contain(const Vec2(0, 0), const Vec2(100, 100));
    expect(g.scale, 1);
    // Padding larger than the box is a layout accident, not a crash.
    final h = CanvasFit.contain(const Vec2(100, 100), const Vec2(10, 10),
        padding: 50);
    expect(h.scale, 1);
  });

  test('lengths scale with the drawing', () {
    final f = CanvasFit.contain(const Vec2(1000, 1000), const Vec2(500, 500));
    expect(f.lengthToScreen(46), closeTo(23, 1e-9));
  });
}
