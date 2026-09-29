/// A drawing part-way through being authored.
///
/// The tracer produces geometry and nothing else — it has no opinion about
/// which blob is the head or what colour a pig should suggest. This is
/// where that gets decided, and it is deliberately mutable: the editor is
/// a person poking at a picture until it looks right, not a pipeline.
///
/// Emitting the asset JSON is the one thing here that has to be exactly
/// right, because everything downstream — the app, the bundle, the asset
/// tests — reads that shape.
library;

import 'geometry.dart';
import 'palette.dart';
import 'png_trace.dart';

/// One fillable area, with the parts a person chooses attached.
class DraftRegion {
  DraftRegion({
    required this.id,
    required this.loops,
    required this.suggestedColor,
    required this.interiorPoint,
    this.number,
  });

  String id;
  final List<List<Vec2>> loops;

  /// A point known to be inside — see [TracedRegion.interiorPoint]. The
  /// editor uses it to put a label on the right blob; the bounding-box
  /// centre would sit in the hole of a ring-shaped area.
  final Vec2 interiorPoint;

  /// Phase 1's fill hint and Phase 3's answer key. Seeded from the
  /// palette at trace time so a freshly imported drawing is already
  /// colourable, rather than making the import a colouring chore before
  /// it is a drawing.
  int suggestedColor;

  /// Left null until someone is actually authoring for paint-by-numbers.
  /// `supportsNumbers` only reports true once every region has one, so a
  /// half-numbered drawing costs nothing and blocks nothing.
  int? number;

  Bounds get bounds => Bounds.around(loops.first);

  String get pathData => loops.map(polygonToPath).join(' ');
}

/// The whole drawing under the editor's hands.
class ArtDraft {
  ArtDraft({
    required this.id,
    required this.category,
    required this.title,
    required this.canvasSize,
    required this.silhouette,
    required this.regions,
    this.symmetryAxisX,
  });

  /// Filenames and the gallery key are built from this, so it is held to
  /// the same shape as the shipped ids: lowercase, no spaces.
  String id;
  String category;

  /// Shown nowhere a child can see. It exists so the JSON stays legible
  /// to whoever opens it in a year, and for accessibility labels.
  String title;

  final double canvasSize;

  /// The outer edge of the drawing. Not editable — it is whatever the ink
  /// enclosed, and a person redrawing it by hand on a tablet would be
  /// doing the paint app's job worse.
  final List<List<Vec2>> silhouette;

  /// Big-to-small. The editor preserves that on every reorder, because
  /// `Artwork.regionAt` searches last-first and the ordering is the only
  /// thing making a tap on an eye hit the eye.
  final List<DraftRegion> regions;

  /// Phase 2's mirror line, in canvas units. Null means "down the middle",
  /// which `effectiveSymmetryAxis` supplies anyway — so this is only ever
  /// set for a drawing whose symmetry is genuinely off-centre.
  double? symmetryAxisX;

  static ArtDraft fromTrace(
    TracedArt trace, {
    required String id,
    required String category,
    required String title,
  }) {
    final colours = PaintColor.values;
    return ArtDraft(
      id: id,
      category: category,
      title: title,
      canvasSize: trace.canvasSize,
      silhouette: trace.silhouette,
      regions: [
        for (var i = 0; i < trace.regions.length; i++)
          DraftRegion(
            id: trace.regions[i].id,
            loops: trace.regions[i].loops,
            interiorPoint: trace.regions[i].interiorPoint,
            // Cycled rather than all one colour: a drawing that opens with
            // every region suggesting the same swatch looks like the
            // import failed.
            suggestedColor: colours[i % colours.length].argb,
          ),
      ],
    );
  }

  /// Every drawn line: the silhouette plus each region boundary.
  List<List<Vec2>> get outlineLoops => [
        ...silhouette,
        for (final r in regions) ...r.loops,
      ];

  /// Checkpoints, authored explicitly rather than left to the loader.
  ///
  /// A traced drawing is made of a dozen separate loops, and the loader's
  /// fallback walks them as one joined polyline — which drops dots onto
  /// the invented jump between the end of one loop and the start of the
  /// next, hovering in empty space. Distributing per subpath puts every
  /// checkpoint on a line somebody actually drew.
  List<Vec2> get guideDots {
    final loops = outlineLoops;
    final total = loops.fold<double>(0, (s, l) => s + polylineLength(l));
    // The loader's own rule: about one dot per 90 canvas units, never so
    // few there is nothing to follow, never so many they crowd into a
    // dotted line and stop reading as checkpoints.
    final count = (total / 90).round().clamp(8, 60);
    final sampled = sampleAlongSubpaths(loops, count);

    // A drawn line the artist made once is described twice here — as part
    // of the silhouette and as the edge of the region beside it — and both
    // copies now sit on the same curve. Sampling them independently puts
    // two checkpoints a few units apart, so the body outline ends up with
    // twice the dot density of the tail, and a pair of overlapping dots
    // reads as one dot that will not light.
    const minGap = 34.0;
    final kept = <Vec2>[];
    for (final d in sampled) {
      final crowded = kept.any(
        (k) => k.distanceSquaredTo(d) < minGap * minGap,
      );
      if (!crowded) kept.add(d);
    }

    // Never thin a drawing below something worth tracing. A shape small
    // enough for the gap to eat its checkpoints keeps all of them.
    return kept.length >= 8 ? kept : sampled;
  }

  /// The asset file, in the shape `DrawingAsset.fromJson` expects.
  Map<String, dynamic> toAssetJson() {
    return {
      'id': id,
      'category': category,
      'title': title,
      'canvas': {'width': canvasSize, 'height': canvasSize},
      'outline': outlineLoops.map(polygonToPath).join(' '),
      'guideDots': [
        for (final d in guideDots)
          {
            'x': double.parse(d.x.toStringAsFixed(1)),
            'y': double.parse(d.y.toStringAsFixed(1)),
          },
      ],
      'regions': [
        for (final r in regions)
          {
            'id': r.id,
            'path': r.pathData,
            'suggestedColor': _hex(r.suggestedColor),
            if (r.number != null) 'number': r.number,
          },
      ],
      if (symmetryAxisX != null)
        'symmetryAxis': {'type': 'vertical', 'x': symmetryAxisX},
    };
  }
}

String _hex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Trims a typed name down to something safe to put in a filename and an
/// asset id. Returns null when nothing usable is left, so the caller can
/// keep the person on the naming step rather than writing `_.json`.
String? sanitiseId(String raw) {
  final s = raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return s.isEmpty ? null : s;
}
