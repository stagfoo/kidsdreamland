/// What a child has made on top of an asset: the strokes drawn and the
/// regions filled, plus undo.
///
/// Pure Dart, so the undo rules — the single most-used control at this age
/// — are tested rather than hoped for.
library;

import 'drawing_asset.dart';
import 'geometry.dart';
import 'stroke.dart';

/// One reversible act. Strokes and fills share a history so that undo
/// means "the last thing I did", which is the only model a five-year-old
/// has. Two separate stacks would make undo unpredictable exactly when it
/// is needed most.
sealed class ArtworkAction {
  const ArtworkAction();
}

class StrokeAction extends ArtworkAction {
  StrokeAction(this.stroke, {this.erased = false});

  final Stroke stroke;

  /// Rubbed out. Marked rather than removed, so undo can put it back
  /// exactly where it was in the order — a stroke pulled out of the
  /// history and pushed back on the end would redraw on top of whatever
  /// was done in between.
  bool erased;
}

/// Rubbing strokes out. Holds the actions it hid rather than copies of
/// them, so undoing is flipping a flag back and cannot resurrect a
/// stale duplicate.
class EraseAction extends ArtworkAction {
  const EraseAction(this.erased);
  final List<StrokeAction> erased;
}

class FillAction extends ArtworkAction {
  const FillAction(this.regionId, this.colorKey, this.previousColorKey);

  final String regionId;
  final String colorKey;

  /// What the region was before, so undo restores it rather than clearing
  /// it — undoing a recolour should reveal the first colour, not white.
  final String? previousColorKey;
}

class Artwork {
  Artwork({required this.assetId});

  final String assetId;

  final List<ArtworkAction> _history = [];

  /// regionId -> colour key. Rebuilt from history on undo rather than kept
  /// as a second source of truth that could drift.
  final Map<String, String> _fills = {};

  List<ArtworkAction> get history => List.unmodifiable(_history);
  Map<String, String> get fills => Map.unmodifiable(_fills);

  Iterable<Stroke> get strokes => _history
      .whereType<StrokeAction>()
      .where((a) => !a.erased)
      .map((a) => a.stroke);

  bool get isEmpty => _history.isEmpty;
  bool get canUndo => _history.isNotEmpty;

  void addStroke(Stroke stroke) {
    if (stroke.isEmpty) return;
    _history.add(StrokeAction(stroke));
  }

  /// Fills [regionId]. Returns false when nothing changed — filling a
  /// region the colour it already is should not consume an undo, or the
  /// button starts undoing invisible steps.
  bool fill(String regionId, String colorKey) {
    final previous = _fills[regionId];
    if (previous == colorKey) return false;
    _fills[regionId] = colorKey;
    _history.add(FillAction(regionId, colorKey, previous));
    return true;
  }

  /// Rubs out every stroke passing within [radius] of [p], in canvas
  /// units. Returns how many went.
  ///
  /// Whole strokes rather than the part under the finger: a child using an
  /// eraser means "take that away", and a stroke cut into two floating
  /// halves is not what anyone was asking for.
  int erase(Vec2 p, double radius) {
    final hit = <StrokeAction>[];
    final rSq = radius * radius;
    for (final action in _history) {
      if (action is! StrokeAction || action.erased) continue;
      final pts = [for (final sp in action.stroke.points) sp.position];
      final near = pts.length == 1
          ? p.distanceSquaredTo(pts.first) <= rSq
          : distanceSquaredToPolyline(p, pts) <= rSq;
      if (near) hit.add(action);
    }
    if (hit.isEmpty) return 0;
    for (final a in hit) {
      a.erased = true;
    }
    _history.add(EraseAction(hit));
    return hit.length;
  }

  /// Undoes the last action. Returns what was undone, or null if there was
  /// nothing — callers use that to stay silent rather than making an undo
  /// sound for a no-op.
  ArtworkAction? undo() {
    if (_history.isEmpty) return null;
    final action = _history.removeLast();
    switch (action) {
      case StrokeAction():
        break;
      case EraseAction(:final erased):
        for (final a in erased) {
          a.erased = false;
        }
      case FillAction(:final regionId, :final previousColorKey):
        if (previousColorKey == null) {
          _fills.remove(regionId);
        } else {
          _fills[regionId] = previousColorKey;
        }
    }
    return action;
  }

  void clear() {
    _history.clear();
    _fills.clear();
  }

  /// The region under [p], in canvas units, or null.
  ///
  /// Searched last-first so that a small region authored on top of a big
  /// one — an eye on a head — wins the tap. Painting order is the only
  /// statement of intent the asset makes about overlap, and it is the one
  /// a child sees.
  static ArtRegion? regionAt(DrawingAsset asset, Vec2 p) {
    for (var i = asset.regions.length - 1; i >= 0; i--) {
      if (asset.regions[i].contains(p)) return asset.regions[i];
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'assetId': assetId,
        'version': 1,
        'actions': [
          for (final a in _history)
            switch (a) {
              StrokeAction(:final stroke, :final erased) => {
                  'type': 'stroke',
                  'stroke': stroke.toJson(),
                  if (erased) 'erased': true,
                },
              EraseAction(:final erased) => {
                  'type': 'erase',
                  // Positions in the history, which is what makes this
                  // reloadable without giving every stroke an id.
                  'indices': [
                    for (final a in erased) _history.indexOf(a),
                  ],
                },
              FillAction(
                :final regionId,
                :final colorKey,
                :final previousColorKey
              ) =>
                {
                  'type': 'fill',
                  'region': regionId,
                  'color': colorKey,
                  'was': ?previousColorKey,
                },
            },
        ],
      };

  static Artwork fromJson(Map<String, dynamic> json) {
    final art = Artwork(assetId: json['assetId'] as String);
    for (final raw in (json['actions'] as List? ?? const [])) {
      final a = raw as Map;
      switch (a['type']) {
        case 'stroke':
          art._history.add(StrokeAction(
            Stroke.fromJson((a['stroke'] as Map).cast<String, dynamic>()),
            erased: a['erased'] == true,
          ));
        case 'erase':
          final targets = <StrokeAction>[];
          for (final i in (a['indices'] as List? ?? const [])) {
            final idx = (i as num).toInt();
            if (idx >= 0 && idx < art._history.length) {
              final target = art._history[idx];
              if (target is StrokeAction) targets.add(target);
            }
          }
          art._history.add(EraseAction(targets));
        case 'fill':
          final region = a['region'] as String;
          final color = a['color'] as String;
          art._history.add(
            FillAction(region, color, a['was'] as String?),
          );
          art._fills[region] = color;
        default:
          // An action kind written by a future build. Skipping it keeps
          // the rest of the drawing openable, which matters more than
          // being exact about a feature this build cannot draw anyway.
          break;
      }
    }
    return art;
  }
}
