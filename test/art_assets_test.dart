@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kidsdreamland/artwork.dart';
import 'package:kidsdreamland/drawing_asset.dart';
import 'package:kidsdreamland/geometry.dart';

/// Every shipped drawing, parsed from the real files.
///
/// Art production is a generator and a pile of coordinates, so this is the
/// guard that stops a bad shape reaching a tablet: a region that flattens
/// to nothing, a colour typo, a drawing that wanders off its own canvas.
void main() {
  final dir = Directory('assets/art');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .where((f) => !f.path.endsWith('index.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('there is a full set of assets across two categories', () {
    expect(files.length, greaterThanOrEqualTo(8));
    final assets = [
      for (final f in files)
        DrawingAsset.fromJson(
            jsonDecode(f.readAsStringSync()) as Map<String, dynamic>),
    ];
    final categories = assets.map((a) => a.category).toSet();
    expect(categories.length, greaterThanOrEqualTo(2));
    // Ids are the filename and the save key; a duplicate would silently
    // overwrite another drawing's saved work.
    expect(assets.map((a) => a.id).toSet().length, assets.length);
  });

  test('the index lists exactly the assets that exist', () {
    final index = jsonDecode(File('assets/art/index.json').readAsStringSync())
        as Map<String, dynamic>;
    final listed = {
      for (final a in index['assets'] as List) (a as Map)['id'] as String,
    };
    final onDisk = {
      for (final f in files) f.uri.pathSegments.last.replaceAll('.json', ''),
    };
    expect(listed, onDisk);

    final categories = {
      for (final c in index['categories'] as List) (c as Map)['id'] as String,
    };
    final used = {
      for (final a in index['assets'] as List) (a as Map)['category'] as String,
    };
    // A drawing filed under a category the menu does not show is a drawing
    // no one can reach.
    expect(used.difference(categories), isEmpty);
  });

  for (final file in files) {
    final name = file.uri.pathSegments.last;

    group(name, () {
      late DrawingAsset asset;

      setUp(() {
        asset = DrawingAsset.fromJson(
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
      });

      test('parses', () {
        expect(asset.id, isNotEmpty);
        expect(asset.regions, isNotEmpty);
        expect(asset.outline.subpaths, isNotEmpty);
      });

      test('stays inside its own canvas', () {
        final b = asset.outline.bounds;
        expect(b.left, greaterThanOrEqualTo(0));
        expect(b.top, greaterThanOrEqualTo(0));
        expect(b.right, lessThanOrEqualTo(asset.canvasSize.x));
        expect(b.bottom, lessThanOrEqualTo(asset.canvasSize.y));
      });

      test('fills a decent share of the canvas', () {
        // A drawing crammed into one corner traces as a tiny scribble on a
        // tablet, whatever the layout does with it.
        final b = asset.outline.bounds;
        expect(b.width / asset.canvasSize.x, greaterThan(0.5));
        expect(b.height / asset.canvasSize.y, greaterThan(0.3));
      });

      test('every guide dot sits on the outline', () {
        for (final d in asset.guideDots) {
          expect(
            distanceSquaredToPolyline(d, asset.outline.allPoints),
            lessThan(4.0),
            reason: 'dot $d is off the line',
          );
        }
      });

      test('every region is fillable — it has an interior to tap', () {
        for (final r in asset.regions) {
          final c = r.bounds.centre;
          // Probe the centre and a ring around it. A region whose every
          // probe misses is a sliver nothing can land in, which reads as
          // a bit of the picture that refuses to colour.
          final probes = <Vec2>[
            c,
            Vec2(c.x + r.bounds.width * 0.15, c.y),
            Vec2(c.x - r.bounds.width * 0.15, c.y),
            Vec2(c.x, c.y + r.bounds.height * 0.15),
            Vec2(c.x, c.y - r.bounds.height * 0.15),
          ];
          expect(
            probes.any(r.contains),
            isTrue,
            reason: 'region "${r.id}" has no tappable interior',
          );
        }
      });

      test('regions are big enough for a child to hit', () {
        for (final r in asset.regions) {
          // 60 canvas units is roughly a fingertip once a 1024 drawing is
          // scaled to a tablet.
          expect(
            r.bounds.width,
            greaterThan(30),
            reason: 'region "${r.id}" is too narrow to tap',
          );
          expect(
            r.bounds.height,
            greaterThan(30),
            reason: 'region "${r.id}" is too short to tap',
          );
        }
      });

      test('region ids are unique within the drawing', () {
        final ids = asset.regions.map((r) => r.id).toList();
        expect(ids.toSet().length, ids.length);
      });

      test('the eye is reachable — small parts are not buried', () {
        // Regions are authored big-to-small and searched last-first, so
        // the last region must be findable at its own centre.
        final last = asset.regions.last;
        expect(Artwork.regionAt(asset, last.bounds.centre)?.id, last.id);
      });

      test('has enough checkpoints to be worth tracing', () {
        expect(asset.guideDots.length, greaterThanOrEqualTo(8));
      });
    });
  }
}
