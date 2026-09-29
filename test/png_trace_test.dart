/// The tracer, against pixel grids written by hand.
///
/// Every case here is a drawing small enough to read in the source, which
/// is the point: when a real PNG traces wrong on a tablet, the question is
/// always "which of these rules did it break", and a test you can see the
/// shape of answers that faster than a debugger.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kidsdreamland/art_draft.dart';
import 'package:kidsdreamland/drawing_asset.dart';
import 'package:kidsdreamland/geometry.dart';
import 'package:kidsdreamland/png_trace.dart';

/// Builds RGBA from an ASCII picture: `#` is ink, anything else is clear.
///
/// [zoom] repeats each character into a block, so a readable ten-character
/// drawing becomes a pixel grid with lines thick enough to behave like
/// something a person drew.
(Uint8List, int, int) pixels(List<String> rows, {int zoom = 4}) {
  final w = rows.first.length * zoom;
  final h = rows.length * zoom;
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final ink = rows[y ~/ zoom][x ~/ zoom] == '#';
      final i = (y * w + x) * 4;
      out[i] = 0x4E;
      out[i + 1] = 0x34;
      out[i + 2] = 0x2E;
      out[i + 3] = ink ? 255 : 0;
    }
  }
  return (out, w, h);
}

TracedArt traceRows(List<String> rows, {TraceOptions? options, int zoom = 4}) {
  final (rgba, w, h) = pixels(rows, zoom: zoom);
  return traceLineArt(
    rgba,
    w,
    h,
    options: options ?? const TraceOptions(smoothing: 0),
  );
}

void main() {
  group('finding regions', () {
    test('a closed ring encloses exactly one region', () {
      final art = traceRows([
        '............',
        '.##########.',
        '.#........#.',
        '.#........#.',
        '.#........#.',
        '.#........#.',
        '.##########.',
        '............',
      ]);

      expect(art.warnings, isEmpty);
      expect(art.regions, hasLength(1));
      expect(art.silhouette, hasLength(1));
    });

    test('a divided box is two regions, not one', () {
      final art = traceRows([
        '###########',
        '#....#....#',
        '#....#....#',
        '#....#....#',
        '#....#....#',
        '###########',
      ]);

      expect(art.regions, hasLength(2));
    });

    test('an unclosed line encloses nothing, and says so', () {
      final art = traceRows([
        '..........',
        '.########.',
        '.#......#.',
        '.#........',
        '.########.',
        '..........',
      ]);

      expect(art.regions, isEmpty);
      expect(art.warnings, contains(TraceWarning.noRegions));
    });

    test('a transparent image reports no ink rather than throwing', () {
      final art = traceRows([
        '......',
        '......',
        '......',
      ]);

      expect(art.isEmpty, isTrue);
      expect(art.warnings, contains(TraceWarning.noInk));
    });

    test('a drawing running off the image edge is flagged', () {
      final art = traceRows([
        '##########',
        '#........#',
        '#........#',
        '##########',
      ]);

      expect(art.warnings, contains(TraceWarning.touchesImageEdge));
    });

    test('fill does not escape through a diagonal pinch', () {
      // Two boxes meeting corner to corner. Eight-connected flooding
      // squeezes through that corner and merges them into one region,
      // which on a real drawing is a head bleeding into a body.
      final art = traceRows([
        '#######.......',
        '#.....#.......',
        '#.....#.......',
        '#######.......',
        '.......#######',
        '.......#.....#',
        '.......#.....#',
        '.......#######',
      ]);

      expect(art.regions, hasLength(2));
    });

    test('specks are dropped, real areas are kept', () {
      final art = traceRows([
        '################',
        '#..............#',
        '#..............#',
        '#..............#',
        '#..............#',
        '#..............#',
        '#....######....#',
        '#....#....#....#',
        '#....######....#',
        '#..............#',
        '################',
      ]);

      // The big surround and the small box inside it: two areas, both
      // comfortably bigger than a fingertip once scaled.
      expect(art.regions, hasLength(2));
      for (final r in art.regions) {
        expect(r.bounds.width, greaterThan(32));
        expect(r.bounds.height, greaterThan(32));
      }
    });

    test('regions come back biggest first', () {
      final art = traceRows([
        '####################',
        '#..................#',
        '#..................#',
        '#..................#',
        '#..................#',
        '####################',
        '#.....#............#',
        '#.....#............#',
        '####################',
      ]);

      final areas = [for (final r in art.regions) r.area];
      expect(areas, equals([...areas]..sort((a, b) => b.compareTo(a))));
    });
  });

  group('placing the drawing on the canvas', () {
    test('it is centred and fills a decent share of the canvas', () {
      final art = traceRows([
        '##########',
        '#........#',
        '#........#',
        '#........#',
        '#........#',
        '##########',
      ]);

      final b = Bounds.around(art.silhouette.expand((l) => l));
      // The same floors `art_assets_test` holds the shipped drawings to.
      expect(b.width / art.canvasSize, greaterThan(0.5));
      expect(b.height / art.canvasSize, greaterThan(0.3));
      expect(b.left, greaterThanOrEqualTo(0));
      expect(b.right, lessThanOrEqualTo(art.canvasSize));

      expect(b.centre.x, closeTo(art.canvasSize / 2, 2));
      expect(b.centre.y, closeTo(art.canvasSize / 2, 2));
    });

    test('the image bounds let the original be laid back underneath', () {
      final art = traceRows([
        '..........',
        '.########.',
        '.#......#.',
        '.########.',
        '..........',
      ]);

      // The drawing sits inside the image, so the image must extend past
      // the traced silhouette on every side.
      final b = Bounds.around(art.silhouette.expand((l) => l));
      expect(art.imageBounds.left, lessThan(b.left));
      expect(art.imageBounds.top, lessThan(b.top));
      expect(art.imageBounds.right, greaterThan(b.right));
      expect(art.imageBounds.bottom, greaterThan(b.bottom));
    });
  });

  group('one drawn line comes back as one line', () {
    // A box with a one-character wall, so the ink has a real thickness to
    // get this wrong by.
    final rows = [
      '..............',
      '.############.',
      '.#..........#.',
      '.#..........#.',
      '.#..........#.',
      '.#..........#.',
      '.#..........#.',
      '.############.',
      '..............',
    ];

    test('the silhouette and the region beside it sit on the same curve',
        () {
      // The failure this guards against: the silhouette follows the
      // outside of the ink and the region boundary the inside, so a box
      // the artist outlined once arrives as two rectangles a stroke-width
      // apart and strokes as a tramline. Both are nudged half a stroke
      // towards the middle of the ink, which is one line.
      final art = traceRows(rows, options: const TraceOptions(smoothing: 0));
      expect(art.regions, hasLength(1));

      final region = art.regions.single.loops.first;
      final gaps = [
        for (final p in art.silhouette.first)
          distanceSquaredToPolyline(p, [...region, region.first]),
      ];
      final mean =
          gaps.map((g) => g <= 0 ? 0.0 : math.sqrt(g)).reduce((a, b) => a + b) /
              gaps.length;

      // The wall is about a fourteenth of the drawing, so roughly 64
      // canvas units. Untouched, these two curves would be that far
      // apart everywhere.
      expect(mean, lessThan(20));
    });

    test('a region reaches the line rather than stopping inside it', () {
      // The same nudge outwards is what stops a filled drawing having a
      // pale halo between the colour and the outline.
      final art = traceRows(rows, options: const TraceOptions(smoothing: 0));
      final region = Bounds.around(art.regions.single.loops.first);
      final silhouette = Bounds.around(art.silhouette.first);

      expect(region.width, greaterThan(silhouette.width * 0.85));
      expect(region.height, greaterThan(silhouette.height * 0.85));
    });
  });

  group('the options actually do something', () {
    test('raising the ink threshold past the ink finds nothing', () {
      final rows = ['######', '#....#', '######'];
      final (rgba, w, h) = pixels(rows);
      // Half-opaque ink, so a threshold either side of it decides.
      for (var i = 3; i < rgba.length; i += 4) {
        if (rgba[i] != 0) rgba[i] = 120;
      }

      final found = traceLineArt(rgba, w, h,
          options: const TraceOptions(alphaThreshold: 0.3));
      final lost = traceLineArt(rgba, w, h,
          options: const TraceOptions(alphaThreshold: 0.8));

      expect(found.isEmpty, isFalse);
      expect(lost.warnings, contains(TraceWarning.noInk));
    });

    test('more simplification means fewer points', () {
      final rows = [
        '..######..',
        '.#......#.',
        '#........#',
        '#........#',
        '.#......#.',
        '..######..',
      ];
      final loose = traceRows(rows,
          options: const TraceOptions(simplify: 5, smoothing: 0));
      final tight = traceRows(rows,
          options: const TraceOptions(simplify: 0.2, smoothing: 0));

      expect(
        loose.silhouette.first.length,
        lessThan(tight.silhouette.first.length),
      );
    });

    test('smoothing rounds corners without losing the shape', () {
      final rows = [
        '##########',
        '#........#',
        '#........#',
        '#........#',
        '##########',
      ];
      final sharp =
          traceRows(rows, options: const TraceOptions(smoothing: 0));
      final round =
          traceRows(rows, options: const TraceOptions(smoothing: 1));

      expect(
        round.silhouette.first.length,
        greaterThan(sharp.silhouette.first.length),
      );
      // A rounded rectangle is still a rectangle: the bounds must not
      // wander, or every drawing drifts smaller each time you nudge the
      // slider.
      final a = Bounds.around(sharp.silhouette.first);
      final b = Bounds.around(round.silhouette.first);
      expect(b.width, closeTo(a.width, a.width * 0.12));
      expect(b.height, closeTo(a.height, a.height * 0.12));
    });
  });

  group('what comes out is a drawing the app can open', () {
    final art = traceRows([
      '####################',
      '#..................#',
      '#..................#',
      '#......######......#',
      '#......#....#......#',
      '#......######......#',
      '#..................#',
      '#..................#',
      '####################',
    ]);

    final draft = ArtDraft.fromTrace(
      art,
      id: 'test_shape',
      category: 'test',
      title: 'Test shape',
    );

    test('it parses back through the app own loader', () {
      final asset = DrawingAsset.fromJson(draft.toAssetJson());
      expect(asset.id, 'test_shape');
      expect(asset.regions, hasLength(art.regions.length));
      expect(asset.outline.subpaths, isNotEmpty);
    });

    test('every region really encloses the pixels it came from', () {
      // Via the interior point rather than the bounding-box centre. The
      // surround of this drawing is a ring, and a ring's box centre is in
      // the hole — which is exactly the case that would slip through a
      // centre probe and reach a tablet as an area that will not colour.
      final asset = DrawingAsset.fromJson(draft.toAssetJson());
      for (var i = 0; i < asset.regions.length; i++) {
        expect(
          asset.regions[i].contains(draft.regions[i].interiorPoint),
          isTrue,
          reason: 'region "${asset.regions[i].id}" does not contain its '
              'own interior point',
        );
      }
    });

    test('a ring-shaped region still fills a fingertip', () {
      for (final r in draft.regions) {
        expect(r.bounds.width, greaterThan(32));
        expect(r.bounds.height, greaterThan(32));
      }
    });

    test('region ids are unique', () {
      final ids = [for (final r in draft.regions) r.id];
      expect(ids.toSet().length, ids.length);
    });

    test('the smallest region is the one a tap finds', () {
      final asset = DrawingAsset.fromJson(draft.toAssetJson());
      final last = asset.regions.last;
      expect(regionAtId(asset, last.bounds.centre), last.id);
    });

    test('there are enough checkpoints to be worth tracing', () {
      expect(draft.guideDots.length, greaterThanOrEqualTo(8));
    });

    test('every checkpoint sits on a line that was actually drawn', () {
      // The one that matters most. Checkpoints are authored per subpath
      // precisely so none of them land on the invented jump between the
      // end of one loop and the start of the next — a dot hovering in
      // empty space is a dot a child chases and never lights.
      final asset = DrawingAsset.fromJson(draft.toAssetJson());
      for (final d in asset.guideDots) {
        final nearest = asset.outline.subpaths
            .map((s) => distanceSquaredToPolyline(d, s))
            .reduce((a, b) => a < b ? a : b);
        expect(nearest, lessThan(4.0), reason: 'dot $d is off every line');
      }
    });

    test('every subpath carries at least one checkpoint', () {
      // A part of the drawing with no dot on it is a part that does not
      // count towards finishing, which reads as the app ignoring the bit
      // you just did.
      final asset = DrawingAsset.fromJson(draft.toAssetJson());
      for (final sub in asset.outline.subpaths) {
        final hit = asset.guideDots.any(
          (d) => distanceSquaredToPolyline(d, sub) < 4.0,
        );
        expect(hit, isTrue, reason: 'a subpath has no checkpoint on it');
      }
    });
  });

  group('sampling along subpaths', () {
    test('dots are shared out by length, never across the gap', () {
      // Two separate loops far apart. Joined end-to-end they would be one
      // long line with a huge invented segment in the middle.
      final a = [
        const Vec2(0, 0),
        const Vec2(100, 0),
        const Vec2(100, 100),
        const Vec2(0, 100),
        const Vec2(0, 0),
      ];
      final b = [
        const Vec2(900, 900),
        const Vec2(1000, 900),
        const Vec2(1000, 1000),
        const Vec2(900, 1000),
        const Vec2(900, 900),
      ];

      final dots = sampleAlongSubpaths([a, b], 20);

      expect(dots, hasLength(greaterThan(10)));
      for (final d in dots) {
        final onA = distanceSquaredToPolyline(d, a);
        final onB = distanceSquaredToPolyline(d, b);
        expect(onA < 1 || onB < 1, isTrue, reason: '$d is on neither loop');
      }
    });

    test('a short subpath still gets a checkpoint', () {
      final long = [const Vec2(0, 0), const Vec2(1000, 0)];
      final short = [const Vec2(0, 500), const Vec2(3, 500)];

      final dots = sampleAlongSubpaths([long, short], 30);
      final onShort = dots.where(
        (d) => distanceSquaredToPolyline(d, short) < 1,
      );
      expect(onShort, isNotEmpty);
    });

    test('nothing to walk is an empty list, not a crash', () {
      expect(sampleAlongSubpaths(const [], 10), isEmpty);
      expect(sampleAlongSubpaths([[const Vec2(1, 1)]], 10), isEmpty);
      expect(sampleAlongSubpaths([[const Vec2(0, 0), const Vec2(1, 0)]], 0),
          isEmpty);
    });
  });
}

/// The app's own last-first region search, which is what decides whether a
/// tap on an eye hits the eye.
String? regionAtId(DrawingAsset asset, Vec2 p) {
  for (var i = asset.regions.length - 1; i >= 0; i--) {
    if (asset.regions[i].contains(p)) return asset.regions[i].id;
  }
  return null;
}
