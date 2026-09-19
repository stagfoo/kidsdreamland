import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kidsdreamland/artwork.dart';
import 'package:kidsdreamland/drawing_asset.dart';
import 'package:kidsdreamland/geometry.dart';
import 'package:kidsdreamland/palette.dart';
import 'package:kidsdreamland/stroke.dart';

Stroke strokeOf(int n) => Stroke(
      colorKey: 'red',
      brushKey: 'pencil',
      points: [
        for (var i = 0; i < n; i++) StrokePoint(Vec2(i.toDouble(), 0), 8),
      ],
    );

void main() {
  eraserTests();

  group('undo', () {
    test('undoes strokes and fills in one shared order', () {
      final a = Artwork(assetId: 'x');
      a.addStroke(strokeOf(3));
      a.fill('body', 'red');
      a.addStroke(strokeOf(2));

      expect(a.history.length, 3);
      expect(a.undo(), isA<StrokeAction>());
      expect(a.undo(), isA<FillAction>());
      expect(a.fills, isEmpty);
      expect(a.undo(), isA<StrokeAction>());
      expect(a.canUndo, isFalse);
    });

    test('undoing a recolour reveals the previous colour, not white', () {
      final a = Artwork(assetId: 'x');
      a.fill('body', 'red');
      a.fill('body', 'blue');
      a.undo();
      expect(a.fills['body'], 'red');
    });

    test('undo on an empty artwork is a silent no-op', () {
      final a = Artwork(assetId: 'x');
      expect(a.undo(), isNull);
      expect(a.canUndo, isFalse);
    });

    test('an empty stroke is not recorded', () {
      final a = Artwork(assetId: 'x');
      a.addStroke(strokeOf(0));
      expect(a.isEmpty, isTrue);
    });

    test('refilling the same colour does not consume an undo step', () {
      final a = Artwork(assetId: 'x');
      expect(a.fill('body', 'red'), isTrue);
      expect(a.fill('body', 'red'), isFalse);
      expect(a.history.length, 1);
    });
  });

  group('round trip', () {
    test('survives JSON with fills and strokes intact', () {
      final a = Artwork(assetId: 'dino_trex');
      a.addStroke(strokeOf(4));
      a.fill('body', 'green');
      a.fill('belly', 'yellow');
      a.fill('body', 'blue');

      final back = Artwork.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>,
      );

      expect(back.assetId, 'dino_trex');
      expect(back.fills['body'], 'blue');
      expect(back.fills['belly'], 'yellow');
      expect(back.strokes.length, 1);
      expect(back.strokes.first.points.length, 4);

      // Undo must still walk back through the reloaded history.
      back.undo();
      expect(back.fills['body'], 'green');
    });

    test('an unknown action kind is skipped, not fatal', () {
      // A drawing written by a future build with a feature this one has
      // no idea about should still open.
      final json = {
        'assetId': 'x',
        'version': 99,
        'actions': [
          {'type': 'sticker', 'which': 'star'},
          {'type': 'fill', 'region': 'body', 'color': 'red'},
        ],
      };
      final a = Artwork.fromJson(json);
      expect(a.fills['body'], 'red');
    });

    test('stroke points round trip through the flat triple encoding', () {
      final s = Stroke(
        colorKey: 'purple',
        brushKey: 'crayon',
        points: const [
          StrokePoint(Vec2(1.25, 2.5), 26),
          StrokePoint(Vec2(3, 4), 30),
        ],
      );
      final back = Stroke.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      expect(back.points.length, 2);
      // Saved at one decimal, so 1.25 comes back as 1.3 — a tenth of a
      // canvas unit, finer than a pixel at any real display size.
      expect(back.points.first.position.x, closeTo(1.25, 0.06));
      expect(back.points.last.width, closeTo(30, 0.06));
      expect(back.color, PaintColor.purple);
      expect(back.brush, BrushKind.crayon);
    });

    test('an unknown colour or brush key falls back rather than throwing', () {
      final s = Stroke(colorKey: 'chartreuse', brushKey: 'airbrush');
      expect(s.color, PaintColor.blue);
      expect(s.brush, BrushKind.marker);
    });
  });

  group('regionAt', () {
    final asset = DrawingAsset.fromJson({
      'id': 'test',
      'category': 'test',
      'canvas': {'width': 100, 'height': 100},
      'outline': 'M 0 0 L 100 0 L 100 100 L 0 100 Z',
      'regions': [
        {
          'id': 'big',
          'path': 'M 0 0 L 100 0 L 100 100 L 0 100 Z',
          'suggestedColor': '#FF0000',
        },
        {
          'id': 'small',
          'path': 'M 40 40 L 60 40 L 60 60 L 40 60 Z',
          'suggestedColor': '#00FF00',
        },
      ],
    });

    test('a small region on top of a big one wins the tap', () {
      expect(Artwork.regionAt(asset, const Vec2(50, 50))?.id, 'small');
    });

    test('outside the small one falls through to the big one', () {
      expect(Artwork.regionAt(asset, const Vec2(10, 10))?.id, 'big');
    });

    test('outside everything is null', () {
      expect(Artwork.regionAt(asset, const Vec2(200, 200)), isNull);
    });
  });

  group('StrokeBuilder', () {
    test('drops points closer together than the spacing floor', () {
      final b = StrokeBuilder(brush: BrushKind.pencil, colorKey: 'red');
      b.add(const Vec2(0, 0));
      for (var i = 0; i < 50; i++) {
        b.add(const Vec2(0.1, 0)); // a finger resting still
      }
      expect(b.stroke.points.length, 1);
    });

    test('keeps points that actually moved', () {
      final b = StrokeBuilder(brush: BrushKind.pencil, colorKey: 'red');
      for (var i = 0; i < 10; i++) {
        b.add(Vec2(i * 10.0, 0));
      }
      expect(b.stroke.points.length, 10);
    });

    test('a single tap is a dot, and still draws', () {
      final b = StrokeBuilder(brush: BrushKind.marker, colorKey: 'blue');
      b.add(const Vec2(5, 5));
      expect(b.stroke.isDot, isTrue);
      expect(b.stroke.isEmpty, isFalse);
    });

    test('a grainless brush has a constant width', () {
      final b = StrokeBuilder(brush: BrushKind.marker, colorKey: 'blue');
      for (var i = 0; i < 20; i++) {
        b.add(Vec2(i * 10.0, 0));
      }
      final widths = b.stroke.points.map((p) => p.width).toSet();
      expect(widths.length, 1);
      expect(widths.first, BrushKind.marker.width);
    });

    test('the crayon wobbles, and stays positive', () {
      final b = StrokeBuilder(brush: BrushKind.crayon, colorKey: 'blue');
      for (var i = 0; i < 60; i++) {
        b.add(Vec2(i * 5.0, 0));
      }
      final widths = b.stroke.points.map((p) => p.width).toList();
      expect(widths.toSet().length, greaterThan(10));
      // A width that goes negative inverts the stroke outline and paints
      // a visible spike.
      expect(widths.every((w) => w > 0), isTrue);
    });
  });
}

// Appended: the eraser. Kept with the rest of the undo tests because the
// interesting property is that rubbing out is as undoable as drawing.
void eraserTests() {
  group('erase', () {
    Artwork withTwoStrokes() {
      final a = Artwork(assetId: 'x');
      a.addStroke(Stroke(colorKey: 'red', brushKey: 'pencil', points: const [
        StrokePoint(Vec2(0, 0), 8),
        StrokePoint(Vec2(100, 0), 8),
      ]));
      a.addStroke(Stroke(colorKey: 'blue', brushKey: 'pencil', points: const [
        StrokePoint(Vec2(0, 500), 8),
        StrokePoint(Vec2(100, 500), 8),
      ]));
      return a;
    }

    test('removes only the stroke under the finger', () {
      final a = withTwoStrokes();
      expect(a.erase(const Vec2(50, 0), 20), 1);
      expect(a.strokes.length, 1);
      expect(a.strokes.single.colorKey, 'blue');
    });

    test('rubbing out nothing records nothing', () {
      final a = withTwoStrokes();
      expect(a.erase(const Vec2(50, 250), 20), 0);
      // An eraser waved over blank canvas must not consume an undo step.
      expect(a.history.length, 2);
    });

    test('undo brings the stroke back in its original order', () {
      final a = withTwoStrokes();
      a.erase(const Vec2(50, 0), 20);
      a.undo();
      final colours = a.strokes.map((s) => s.colorKey).toList();
      // Back in front of the blue one, where it was — not appended.
      expect(colours, ['red', 'blue']);
    });

    test('one sweep can take several strokes, and undo returns them all', () {
      final a = withTwoStrokes();
      expect(a.erase(const Vec2(50, 250), 300), 2);
      expect(a.strokes, isEmpty);
      a.undo();
      expect(a.strokes.length, 2);
    });

    test('an already-erased stroke is not erased twice', () {
      final a = withTwoStrokes();
      a.erase(const Vec2(50, 0), 20);
      expect(a.erase(const Vec2(50, 0), 20), 0);
    });

    test('a dot stroke can be rubbed out', () {
      final a = Artwork(assetId: 'x');
      a.addStroke(Stroke(colorKey: 'red', brushKey: 'marker', points: const [
        StrokePoint(Vec2(40, 40), 20),
      ]));
      expect(a.erase(const Vec2(45, 45), 20), 1);
    });

    test('erasure survives a save and reload, undo included', () {
      final a = withTwoStrokes();
      a.erase(const Vec2(50, 0), 20);
      final back = Artwork.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>,
      );
      expect(back.strokes.length, 1);
      back.undo();
      expect(back.strokes.map((s) => s.colorKey).toList(), ['red', 'blue']);
    });
  });
}
