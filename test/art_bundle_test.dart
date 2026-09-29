/// The transfer format, and how much abuse it survives.
///
/// The cases that matter are the broken ones. A pack arrives from another
/// tablet, or from a build six months older, or half-written by a file
/// manager that ran out of space — and the rule throughout the app is that
/// one bad drawing costs you that drawing and nothing else.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kidsdreamland/art_bundle.dart';
import 'package:kidsdreamland/asset_library.dart';

Map<String, dynamic> asset({
  String id = 'fish',
  String category = 'sea',
  String outline = 'M 100 100 L 900 100 L 900 900 L 100 900 Z',
}) {
  return {
    'id': id,
    'category': category,
    'title': id,
    'canvas': {'width': 1024, 'height': 1024},
    'outline': outline,
    'regions': [
      {
        'id': 'body',
        'path': 'M 200 200 L 800 200 L 800 800 L 200 800 Z',
        'suggestedColor': '#1E88E5',
      },
    ],
  };
}

void main() {
  group('round trip', () {
    test('what goes in comes out', () {
      final bundle = ArtBundle(
        name: 'sea creatures',
        categories: const [ArtCategory('sea', 'Sea', 'wave')],
        assets: [asset(), asset(id: 'crab')],
      );

      final read = ArtBundle.decode(bundle.encode());

      expect(read.skipped, isEmpty);
      expect(read.drawings.map((d) => d.id), ['fish', 'crab']);
      expect(read.bundle.name, 'sea creatures');
      expect(read.bundle.categories.single.title, 'Sea');
      expect(read.fromNewerBuild, isFalse);
    });

    test('fields this build has never heard of survive the trip', () {
      // The reason assets are carried as raw JSON rather than re-encoded
      // through the parser: a pack going through an older tablet must not
      // come out the other side with its Phase 3 numbers stripped.
      final withExtra = asset()..['somethingFromLater'] = 42;
      final once = ArtBundle.decode(
        ArtBundle(name: 'p', categories: const [], assets: [withExtra])
            .encode(),
      );
      final twice = ArtBundle.decode(once.bundle.encode());

      expect(twice.bundle.assets.single['somethingFromLater'], 42);
    });
  });

  group('refusing what is not a pack', () {
    test('not JSON at all', () {
      expect(
        () => ArtBundle.decode('this is a photo, not a pack'),
        throwsA(isA<BundleFormatException>()),
      );
    });

    test('JSON, but somebody else\'s', () {
      expect(
        () => ArtBundle.decode('{"some":"other file"}'),
        throwsA(isA<BundleFormatException>()),
      );
    });

    test('a bare list', () {
      expect(
        () => ArtBundle.decode('[1,2,3]'),
        throwsA(isA<BundleFormatException>()),
      );
    });
  });

  group('keeping what is usable', () {
    test('one broken drawing does not cost the others', () {
      final source = ArtBundle(
        name: 'mixed',
        categories: const [ArtCategory('sea', 'Sea', 'wave')],
        assets: [
          asset(id: 'good'),
          asset(id: 'broken', outline: 'not a path at all'),
          asset(id: 'alsogood'),
        ],
      ).encode();

      final read = ArtBundle.decode(source);

      expect(read.drawings.map((d) => d.id), ['good', 'alsogood']);
      expect(read.skipped, hasLength(1));
      expect(read.skipped.single, contains('broken'));
    });

    test('a drawing that is not even an object is skipped', () {
      final read = ArtBundle.decode(
        '{"format":"$kBundleFormat","version":1,"assets":["nonsense"]}',
      );
      expect(read.drawings, isEmpty);
      expect(read.skipped, hasLength(1));
    });

    test('a pack with no drawings reads as empty rather than failing', () {
      final read = ArtBundle.decode(
        '{"format":"$kBundleFormat","version":1}',
      );
      expect(read.drawings, isEmpty);
      expect(read.bundle.categories, isEmpty);
    });
  });

  group('forward and backward compatibility', () {
    test('a pack from a newer build is read, and flagged', () {
      final source = ArtBundle(
        name: 'future',
        categories: const [ArtCategory('sea', 'Sea', 'wave')],
        assets: [asset()],
      ).encode().replaceFirst('"version": 1', '"version": 99');

      final read = ArtBundle.decode(source);

      expect(read.fromNewerBuild, isTrue);
      expect(read.drawings, hasLength(1));
    });

    test('a category nobody declared is invented, not dropped', () {
      // Otherwise the drawing imports, belongs to a category with no tile,
      // and appears on no screen — which reads as the import having
      // silently done nothing at all.
      final read = ArtBundle.decode(
        ArtBundle(
          name: 'orphan',
          categories: const [],
          assets: [asset(id: 'whale', category: 'deep')],
        ).encode(),
      );

      expect(read.drawings.single.category, 'deep');
      expect(read.bundle.categories.map((c) => c.id), contains('deep'));
    });

    test('a malformed category entry is stepped over', () {
      final read = ArtBundle.decode(
        '{"format":"$kBundleFormat","version":1,'
        '"categories":[{"title":"no id here"},{"id":"sea","title":"Sea"}],'
        '"assets":[]}',
      );
      expect(read.bundle.categories.map((c) => c.id), ['sea']);
    });
  });
}
