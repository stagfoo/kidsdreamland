import 'package:flutter_test/flutter_test.dart';
import 'package:kidsdreamland/drawing_asset.dart';
import 'package:kidsdreamland/geometry.dart';

Map<String, dynamic> baseAsset({
  List<Map<String, dynamic>>? regions,
  List<Map<String, dynamic>>? guideDots,
  Map<String, dynamic>? symmetryAxis,
}) =>
    {
      'id': 'dino_trex',
      'category': 'dinosaurs',
      'title': 'T-Rex',
      'canvas': {'width': 1024, 'height': 1024},
      'outline': 'M 100 100 L 900 100 L 900 900 L 100 900 Z',
      'guideDots': ?guideDots,
      'regions': ?regions,
      'symmetryAxis': ?symmetryAxis,
    };

void main() {
  group('parsing', () {
    test('reads the core fields', () {
      final a = DrawingAsset.fromJson(baseAsset());
      expect(a.id, 'dino_trex');
      expect(a.category, 'dinosaurs');
      expect(a.title, 'T-Rex');
      expect(a.canvasSize, const Vec2(1024, 1024));
      expect(a.outline.subpaths, isNotEmpty);
    });

    test('title defaults to the id when unauthored', () {
      final json = baseAsset()..remove('title');
      expect(DrawingAsset.fromJson(json).title, 'dino_trex');
    });

    test('authored guide dots are used as given', () {
      final a = DrawingAsset.fromJson(baseAsset(guideDots: [
        {'x': 1, 'y': 2},
        {'x': 3, 'y': 4},
      ]));
      expect(a.guideDots, [const Vec2(1, 2), const Vec2(3, 4)]);
    });

    test('unauthored guide dots are spaced along the outline', () {
      final a = DrawingAsset.fromJson(baseAsset());
      expect(a.guideDots.length, greaterThanOrEqualTo(8));
      expect(a.guideDots.length, lessThanOrEqualTo(60));
      // Every generated dot must actually sit on the outline, or the
      // checkpoints ask for a line that is not drawn.
      for (final d in a.guideDots) {
        final dist = distanceSquaredToPolyline(d, a.outline.allPoints);
        expect(dist, lessThan(1.0));
      }
    });

    test('a tiny outline still gets the floor of eight dots', () {
      final json = baseAsset()..['outline'] = 'M 0 0 L 5 0 L 5 5 Z';
      expect(DrawingAsset.fromJson(json).guideDots.length, 8);
    });

    test('regions carry their colour and optional number', () {
      final a = DrawingAsset.fromJson(baseAsset(regions: [
        {
          'id': 'body',
          'path': 'M 0 0 L 10 0 L 10 10 Z',
          'suggestedColor': '#8BC34A',
          'number': 3,
        },
      ]));
      expect(a.regions.single.id, 'body');
      expect(a.regions.single.suggestedColor, 0xFF8BC34A);
      expect(a.regions.single.number, 3);
    });
  });

  group('optional phase fields', () {
    test('an asset with no numbers is honestly trace-only', () {
      final a = DrawingAsset.fromJson(baseAsset(regions: [
        {
          'id': 'body',
          'path': 'M 0 0 L 10 0 L 10 10 Z',
          'suggestedColor': '#8BC34A',
        },
      ]));
      expect(a.regions.single.number, isNull);
      expect(a.supportsNumbers, isFalse);
    });

    test('a half-numbered asset does not claim number support', () {
      final a = DrawingAsset.fromJson(baseAsset(regions: [
        {
          'id': 'a',
          'path': 'M 0 0 L 10 0 L 10 10 Z',
          'suggestedColor': '#8BC34A',
          'number': 1,
        },
        {
          'id': 'b',
          'path': 'M 0 0 L 10 0 L 10 10 Z',
          'suggestedColor': '#FFE0B2',
        },
      ]));
      expect(a.supportsNumbers, isFalse);
    });

    test('an asset with no axis still mirrors, down the middle', () {
      final a = DrawingAsset.fromJson(baseAsset());
      expect(a.symmetryAxis, isNull);
      expect(a.effectiveSymmetryAxis.type, SymmetryType.vertical);
      expect(a.effectiveSymmetryAxis.position, 512);
    });

    test('an authored axis wins', () {
      final a = DrawingAsset.fromJson(
          baseAsset(symmetryAxis: {'type': 'vertical', 'x': 400}));
      expect(a.effectiveSymmetryAxis.position, 400);
    });

    test('a horizontal axis reads y', () {
      final a = DrawingAsset.fromJson(
          baseAsset(symmetryAxis: {'type': 'horizontal', 'y': 300}));
      expect(a.effectiveSymmetryAxis.type, SymmetryType.horizontal);
      expect(a.effectiveSymmetryAxis.position, 300);
    });
  });

  group('region hit testing', () {
    test('a hole behaves like a hole', () {
      final a = DrawingAsset.fromJson(baseAsset(regions: [
        {
          'id': 'head',
          // A square with a square eye cut out of it.
          'path': 'M 0 0 L 100 0 L 100 100 L 0 100 Z '
              'M 40 40 L 60 40 L 60 60 L 40 60 Z',
          'suggestedColor': '#FFFFFF',
        },
      ]));
      final head = a.regions.single;
      expect(head.contains(const Vec2(10, 10)), isTrue);
      // Inside the eye is outside the head, so filling the head does not
      // colour the eye in.
      expect(head.contains(const Vec2(50, 50)), isFalse);
      expect(head.contains(const Vec2(200, 200)), isFalse);
    });
  });

  group('difficulty', () {
    test('rises with the amount of work in the drawing', () {
      Map<String, dynamic> withRegions(int n) => baseAsset(regions: [
            for (var i = 0; i < n; i++)
              {
                'id': 'r$i',
                'path': 'M 0 0 L 10 0 L 10 10 Z',
                'suggestedColor': '#FFFFFF',
              },
          ]);
      final easy = DrawingAsset.fromJson(withRegions(1)).difficulty;
      final medium = DrawingAsset.fromJson(withRegions(5)).difficulty;
      final hard = DrawingAsset.fromJson(withRegions(12)).difficulty;
      expect(easy, 1);
      expect(medium, greaterThan(easy));
      expect(hard, 3);
    });

    test('always lands in 1..3', () {
      for (final n in [0, 1, 3, 8, 40]) {
        final a = DrawingAsset.fromJson(baseAsset(regions: [
          for (var i = 0; i < n; i++)
            {
              'id': 'r$i',
              'path': 'M 0 0 L 10 0 L 10 10 Z',
              'suggestedColor': '#FFFFFF',
            },
        ]));
        expect(a.difficulty, inInclusiveRange(1, 3));
      }
    });
  });

  group('colours', () {
    test('accepts both hex lengths', () {
      expect(parseHexColor('#FF0000'), 0xFFFF0000);
      expect(parseHexColor('80FF0000'), 0x80FF0000);
      expect(parseHexColor('  #00ff00  '), 0xFF00FF00);
    });

    test('a typo fails loudly rather than painting a mystery colour', () {
      expect(() => parseHexColor('#GG0000'),
          throwsA(isA<AssetFormatException>()));
      expect(() => parseHexColor('#F00'),
          throwsA(isA<AssetFormatException>()));
    });
  });

  group('malformed assets', () {
    test('a missing id is refused', () {
      final json = baseAsset()..remove('id');
      expect(() => DrawingAsset.fromJson(json),
          throwsA(isA<AssetFormatException>()));
    });

    test('a zero-size canvas is refused', () {
      final json = baseAsset()..['canvas'] = {'width': 0, 'height': 10};
      expect(() => DrawingAsset.fromJson(json),
          throwsA(isA<AssetFormatException>()));
    });

    test('an outline that draws nothing is refused', () {
      final json = baseAsset()..['outline'] = 'M 10 10';
      expect(() => DrawingAsset.fromJson(json),
          throwsA(isA<AssetFormatException>()));
    });
  });
}
