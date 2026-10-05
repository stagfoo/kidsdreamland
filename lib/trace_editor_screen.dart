/// Turning a PNG into a drawing, with a person in the loop.
///
/// This screen is the one place in the app that breaks the no-text rule,
/// and it does so deliberately: it is behind [GrownupGate], the child
/// never sees it, and the work here — naming a region, picking which
/// category a fish belongs in — is reading-and-typing work that cannot
/// honestly be done in pictures.
///
/// The controls are sliders rather than presets because there is no right
/// threshold for a PNG in the abstract. You drag until the overlay sits
/// on the line, and a stepped control always stops just past the value
/// you were heading for.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'art_draft.dart';
import 'asset_library.dart';
import 'crash_log.dart';
import 'drawing_asset.dart';
import 'geometry.dart';
import 'imported_art_store.dart';
import 'palette.dart';
import 'png_decode.dart';
import 'png_trace.dart';
import 'theme.dart';

/// One trace's worth of work, for the worker isolate.
///
/// Its own class rather than a record so the byte list travels by reference
/// where the platform allows it: a Uint8List is transferable, and a megapixel
/// image copied on every slider nudge would hand back the cost this moved off
/// the UI thread to avoid.
class _TraceRequest {
  const _TraceRequest({
    required this.rgba,
    required this.width,
    required this.height,
    required this.options,
  });

  final Uint8List rgba;
  final int width, height;
  final TraceOptions options;
}

/// Runs on the worker isolate. Top-level, because [compute] cannot carry a
/// closure over this screen's state.
TracedArt _traceInBackground(_TraceRequest request) => traceLineArt(
      request.rgba,
      request.width,
      request.height,
      options: request.options,
    );

class TraceEditorScreen extends StatefulWidget {
  const TraceEditorScreen({
    super.key,
    required this.image,
    required this.suggestedName,
    required this.knownCategories,
  });

  final DecodedImage image;

  /// Seeded from the filename, which is nearly always what the drawing is
  /// called anyway.
  final String suggestedName;

  /// Existing categories, offered so a new fish lands beside the other
  /// fish rather than in a category of one.
  final List<ArtCategory> knownCategories;

  @override
  State<TraceEditorScreen> createState() => _TraceEditorScreenState();
}

class _TraceEditorScreenState extends State<TraceEditorScreen> {
  TraceOptions _options = const TraceOptions();
  TracedArt? _trace;
  ArtDraft? _draft;
  int? _selected;
  bool _saving = false;

  late final TextEditingController _title =
      TextEditingController(text: widget.suggestedName);
  late final TextEditingController _category = TextEditingController(
    text: widget.knownCategories.isEmpty
        ? 'my drawings'
        : widget.knownCategories.first.id,
  );

  /// A slider dragged continuously would retrace on every frame. The wait
  /// is short enough to feel live and long enough that a drag costs one
  /// trace rather than sixty.
  Timer? _debounce;

  /// A trace is running. The first one starts before anything is on screen,
  /// so without this the editor opens to a blank panel and looks hung.
  bool _tracing = false;

  /// Which trace is the current one.
  ///
  /// Traces run off the UI thread now, so two can be in flight when a slider
  /// is nudged twice: without this the slower first one can land after the
  /// faster second and quietly undo it.
  int _traceGeneration = 0;

  /// Why the last trace produced nothing, or null when it worked.
  ///
  /// Shown on the panel rather than thrown. This runs on a tablet with no
  /// console attached, and an image the tracer cannot make sense of used to
  /// take the whole screen down with it.
  String? _traceError;

  @override
  void initState() {
    super.initState();
    unawaited(_retrace());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _category.dispose();
    super.dispose();
  }

  void _scheduleRetrace() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 140),
      () => unawaited(_retrace()),
    );
  }

  /// Traces the image and rebuilds the draft from it.
  ///
  /// On a worker isolate, not here. The trace floods and walks every pixel of
  /// a megapixel image, which on the UI thread meant the editor could not
  /// paint its first frame until it finished — the screen opened frozen, and
  /// a big enough image sat there long enough for Android to offer to close
  /// the app. The tracer is plain Dart over a byte list, so it moves across
  /// with nothing to unpick.
  Future<void> _retrace() async {
    final generation = ++_traceGeneration;
    setState(() {
      _tracing = true;
      _traceError = null;
    });

    final TracedArt trace;
    try {
      trace = await compute(
        _traceInBackground,
        _TraceRequest(
          rgba: widget.image.rgba,
          width: widget.image.width,
          height: widget.image.height,
          options: _options,
        ),
      );
    } catch (e, stack) {
      // Caught rather than allowed to escape: this used to run unguarded from
      // initState, so anything the tracer could not handle arrived as a crash
      // on a screen that had never painted.
      CrashLog.instance.record('tracing an image', e, stack);
      if (!mounted || generation != _traceGeneration) return;
      setState(() {
        _tracing = false;
        _traceError = '$e';
      });
      return;
    }

    // A newer trace has already started, so this one is stale.
    if (!mounted || generation != _traceGeneration) return;

    final draft = ArtDraft.fromTrace(
      trace,
      id: sanitiseId(_title.text) ?? 'drawing',
      category: sanitiseId(_category.text) ?? 'my_drawings',
      title: _title.text.trim().isEmpty ? 'Drawing' : _title.text.trim(),
    );

    // Carry over colours and names when the retrace found the same number
    // of regions. Nudging a slider and losing twenty minutes of naming is
    // the kind of thing that makes a tool not get used.
    final old = _draft;
    if (old != null && old.regions.length == draft.regions.length) {
      for (var i = 0; i < draft.regions.length; i++) {
        draft.regions[i].id = old.regions[i].id;
        draft.regions[i].suggestedColor = old.regions[i].suggestedColor;
        draft.regions[i].number = old.regions[i].number;
      }
    }
    draft.symmetryAxisX = old?.symmetryAxisX;

    setState(() {
      _tracing = false;
      _trace = trace;
      _draft = draft;
      if (_selected != null && _selected! >= draft.regions.length) {
        _selected = null;
      }
    });
  }

  /// What the screen shows before the first trace has landed.
  ///
  /// Three different things, because they ask for three different reactions: a
  /// trace still running, a trace that failed, and a trace that worked but
  /// found nothing to draw. A bare spinner for all three is what made a failed
  /// trace look like a hang.
  Widget _firstTrace() {
    final error = _traceError;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined, size: 40),
              const SizedBox(height: 12),
              const Text(
                'That image could not be traced',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              const Text(
                'The tracer wants line art on a transparent background — a '
                'photograph or a drawing on solid white has no empty space for '
                'it to flood.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }

  @override
  Widget build(BuildContext context) {
    final trace = _trace;
    final draft = _draft;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trace a drawing'),
        backgroundColor: Sky.card,
        // A retrace no longer blocks the screen, so without this a slider nudge
        // on a big image looks like nothing happened until the overlay jumps.
        bottom: _tracing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
        actions: [
          TextButton.icon(
            onPressed: _saving || _tracing || draft == null ||
                    draft.regions.isEmpty
                ? null
                : _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Save'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: trace == null || draft == null
          ? _firstTrace()
          : Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _Preview(
                    image: widget.image,
                    trace: trace,
                    draft: draft,
                    selected: _selected,
                    onTapCanvas: _selectAt,
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: Container(
                    color: Sky.card,
                    child: _Controls(
                      options: _options,
                      trace: trace,
                      draft: draft,
                      title: _title,
                      category: _category,
                      knownCategories: widget.knownCategories,
                      selected: _selected,
                      onOptions: (o) {
                        setState(() => _options = o);
                        _scheduleRetrace();
                      },
                      onNames: _retrace,
                      onSelect: (i) => setState(() => _selected = i),
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Picks the region under a tap, smallest first — the same last-first
  /// search the app itself uses, so what you select here is exactly what
  /// a child's finger will find.
  void _selectAt(Vec2 canvasPoint) {
    final draft = _draft;
    if (draft == null) return;
    for (var i = draft.regions.length - 1; i >= 0; i--) {
      if (_containsPoint(draft.regions[i], canvasPoint)) {
        setState(() => _selected = i);
        return;
      }
    }
    setState(() => _selected = null);
  }

  static bool _containsPoint(DraftRegion r, Vec2 p) {
    var inside = false;
    for (final loop in r.loops) {
      if (pointInPolygon(p, loop)) inside = !inside;
    }
    return inside;
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    final id = sanitiseId(_title.text);
    final categoryId = sanitiseId(_category.text);
    if (id == null || categoryId == null) {
      _say('Give the drawing a name and a category first.');
      return;
    }

    setState(() => _saving = true);
    try {
      draft.id = id;
      draft.category = categoryId;
      draft.title = _title.text.trim();

      final json = draft.toAssetJson();

      // Parsed back before it is written, not after. A drawing that only
      // fails at load time fails on a tablet in front of a child, with
      // nobody around who knows what a subpath is.
      DrawingAsset.fromJson(json);

      final store = await ImportedArtStore.open();
      await store.saveAsset(
        json,
        category: ArtCategory(
          categoryId,
          _category.text.trim().isEmpty ? categoryId : _category.text.trim(),
          'star',
        ),
      );
      await AssetLibrary.reload();
      if (mounted) Navigator.of(context).pop(true);
    } on AssetFormatException catch (e, stack) {
      CrashLog.instance.record('saving a trace', e, stack);
      _say('That trace will not load: ${e.message}');
    } catch (e, stack) {
      CrashLog.instance.record('saving a trace', e, stack);
      _say('Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

// ---------------------------------------------------------------- preview

class _Preview extends StatelessWidget {
  const _Preview({
    required this.image,
    required this.trace,
    required this.draft,
    required this.selected,
    required this.onTapCanvas,
  });

  final DecodedImage image;
  final TracedArt trace;
  final ArtDraft draft;
  final int? selected;
  final ValueChanged<Vec2> onTapCanvas;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final scale = side / draft.canvasSize;
        final offset = Offset(
          (constraints.maxWidth - side) / 2,
          (constraints.maxHeight - side) / 2,
        );

        return GestureDetector(
          onTapUp: (d) {
            final local = d.localPosition - offset;
            onTapCanvas(Vec2(local.dx / scale, local.dy / scale));
          },
          child: Container(
            color: Sky.background,
            child: CustomPaint(
              size: Size.infinite,
              painter: _TracePainter(
                image: image,
                trace: trace,
                draft: draft,
                selected: selected,
                scale: scale,
                offset: offset,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter({
    required this.image,
    required this.trace,
    required this.draft,
    required this.selected,
    required this.scale,
    required this.offset,
  });

  final DecodedImage image;
  final TracedArt trace;
  final ArtDraft draft;
  final int? selected;
  final double scale;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    final canvasSide = draft.canvasSize;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasSide, canvasSide),
      Paint()..color = Colors.white,
    );

    // The original, ghosted underneath. Faint enough that the traced line
    // on top is what you read, present enough that a trace wandering off
    // the ink is obvious at a glance.
    final b = trace.imageBounds;
    if (b.width > 0) {
      canvas.drawImageRect(
        image.image,
        Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        ),
        Rect.fromLTRB(b.left, b.top, b.right, b.bottom),
        Paint()..color = Colors.black.withValues(alpha: 0.22),
      );
    }

    for (var i = 0; i < draft.regions.length; i++) {
      final r = draft.regions[i];
      final path = _pathFor(r.loops);
      canvas.drawPath(
        path,
        Paint()
          ..color = Color(r.suggestedColor)
              .withValues(alpha: i == selected ? 0.85 : 0.45),
      );
      if (i == selected) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..color = Sky.accent,
        );
      }
    }

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = Sky.outline;
    for (final loop in draft.outlineLoops) {
      canvas.drawPath(_pathFor([loop]), linePaint);
    }

    // The checkpoints exactly as the app will place them. Seeing them here
    // is the point: a dot sitting off the line is a trace problem, and
    // this is the only screen where it is still cheap to fix.
    final dotPaint = Paint()..color = Sky.dotPending;
    for (final d in draft.guideDots) {
      canvas.drawCircle(Offset(d.x, d.y), 10, dotPaint);
    }

    canvas.restore();
  }

  Path _pathFor(List<List<Vec2>> loops) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final loop in loops) {
      if (loop.isEmpty) continue;
      path.moveTo(loop.first.x, loop.first.y);
      for (final p in loop.skip(1)) {
        path.lineTo(p.x, p.y);
      }
      path.close();
    }
    return path;
  }

  @override
  bool shouldRepaint(_TracePainter old) =>
      old.draft != draft ||
      old.trace != trace ||
      old.selected != selected ||
      old.scale != scale;
}

// --------------------------------------------------------------- controls

class _Controls extends StatelessWidget {
  const _Controls({
    required this.options,
    required this.trace,
    required this.draft,
    required this.title,
    required this.category,
    required this.knownCategories,
    required this.selected,
    required this.onOptions,
    required this.onNames,
    required this.onSelect,
    required this.onChanged,
  });

  final TraceOptions options;
  final TracedArt trace;
  final ArtDraft draft;
  final TextEditingController title;
  final TextEditingController category;
  final List<ArtCategory> knownCategories;
  final int? selected;
  final ValueChanged<TraceOptions> onOptions;
  final VoidCallback onNames;
  final ValueChanged<int?> onSelect;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final w in trace.warnings) _WarningTile(w),

        TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (_) => onNames(),
          onEditingComplete: onNames,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: category,
          decoration: const InputDecoration(labelText: 'Category'),
          onSubmitted: (_) => onNames(),
          onEditingComplete: onNames,
        ),
        if (knownCategories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final c in knownCategories)
                  ActionChip(
                    label: Text(c.title),
                    onPressed: () {
                      category.text = c.id;
                      onNames();
                    },
                  ),
              ],
            ),
          ),

        const Divider(height: 32),
        Text(
          '${draft.regions.length} regions · ${draft.guideDots.length} dots',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),

        _Slider(
          label: 'Ink threshold',
          value: options.alphaThreshold,
          min: 0.05,
          max: 0.95,
          help: 'How solid a pixel must be to count as line.',
          onChanged: (v) => onOptions(options.copyWith(alphaThreshold: v)),
        ),
        _Slider(
          label: 'Detail',
          value: options.simplify,
          min: 0.2,
          max: 6,
          help: 'Lower keeps every wobble; higher straightens the line.',
          invert: true,
          onChanged: (v) => onOptions(options.copyWith(simplify: v)),
        ),
        _Slider(
          label: 'Smoothing',
          value: options.smoothing.toDouble(),
          min: 0,
          max: 3,
          help: 'Rounds the corners. Zero keeps horns and teeth sharp.',
          onChanged: (v) => onOptions(options.copyWith(smoothing: v.round())),
        ),
        _Slider(
          label: 'Smallest region',
          value: options.minRegionFraction,
          min: 0.0005,
          max: 0.05,
          help: 'Anything smaller is treated as a speck, not an area.',
          onChanged: (v) =>
              onOptions(options.copyWith(minRegionFraction: v)),
        ),

        const Divider(height: 32),
        const Text('Regions', style: TextStyle(fontWeight: FontWeight.w600)),
        const Text(
          'Biggest first. The app searches this list backwards, so small '
          'parts must stay at the bottom to be tappable.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 8),

        for (var i = 0; i < draft.regions.length; i++)
          _RegionRow(
            region: draft.regions[i],
            index: i,
            isSelected: i == selected,
            canMoveUp: i > 0,
            canMoveDown: i < draft.regions.length - 1,
            onSelect: () => onSelect(i == selected ? null : i),
            onMove: (delta) {
              final r = draft.regions.removeAt(i);
              draft.regions.insert(i + delta, r);
              onSelect(i + delta);
              onChanged();
            },
            onColour: (argb) {
              draft.regions[i].suggestedColor = argb;
              onChanged();
            },
            onRename: (name) {
              draft.regions[i].id = name;
              onChanged();
            },
            onNumber: (n) {
              draft.regions[i].number = n;
              onChanged();
            },
          ),
      ],
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.help,
    required this.onChanged,
    this.invert = false,
  });

  final String label;
  final double value, min, max;
  final String help;
  final ValueChanged<double> onChanged;

  /// Some knobs read backwards — a bigger simplification tolerance is
  /// *less* detail — so the readout is flipped rather than the slider,
  /// which would make the drag direction fight the label.
  final bool invert;

  @override
  Widget build(BuildContext context) {
    final shown = invert ? (max + min - value) : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(
                shown.toStringAsFixed(shown < 1 ? 3 : 1),
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: Colors.black54,
                ),
              ),
            ],
          ),
          // No divisions: these are values you find by feel, and a stepped
          // slider always lands beside the one you wanted.
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
          Text(
            help,
            style: const TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

class _RegionRow extends StatelessWidget {
  const _RegionRow({
    required this.region,
    required this.index,
    required this.isSelected,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onSelect,
    required this.onMove,
    required this.onColour,
    required this.onRename,
    required this.onNumber,
  });

  final DraftRegion region;
  final int index;
  final bool isSelected, canMoveUp, canMoveDown;
  final VoidCallback onSelect;
  final ValueChanged<int> onMove;
  final ValueChanged<int> onColour;
  final ValueChanged<String> onRename;
  final ValueChanged<int?> onNumber;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: isSelected ? Sky.accentSoft : Colors.transparent,
      child: Column(
        children: [
          ListTile(
            dense: true,
            onTap: onSelect,
            leading: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color(region.suggestedColor),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            title: Text(region.id),
            subtitle: Text(
              '${region.bounds.width.round()} × '
              '${region.bounds.height.round()}'
              '${region.number == null ? '' : '  ·  no. ${region.number}'}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  onPressed: canMoveUp ? () => onMove(-1) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                  onPressed: canMoveDown ? () => onMove(1) : null,
                ),
              ],
            ),
          ),
          if (isSelected)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final c in PaintColor.values)
                        GestureDetector(
                          onTap: () => onColour(c.argb),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Color(c.argb),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: region.suggestedColor == c.argb
                                    ? Sky.ink
                                    : Colors.white,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: region.id,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            isDense: true,
                          ),
                          onChanged: onRename,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 90,
                        child: TextFormField(
                          initialValue: region.number?.toString() ?? '',
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Number',
                            isDense: true,
                          ),
                          onChanged: (v) => onNumber(int.tryParse(v)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WarningTile extends StatelessWidget {
  const _WarningTile(this.warning);

  final TraceWarning warning;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (warning) {
      TraceWarning.noInk => (
          Icons.error_outline_rounded,
          'No ink found. Drag the ink threshold down, or check the PNG '
              'actually has transparency.',
        ),
      TraceWarning.noRegions => (
          Icons.warning_amber_rounded,
          'The line never closes, so there is nothing to fill. Traceable, '
              'but not colourable.',
        ),
      TraceWarning.allRegionsTooSmall => (
          Icons.warning_amber_rounded,
          'Every enclosed area was too small to tap. Try lowering the '
              'smallest-region slider.',
        ),
      TraceWarning.touchesImageEdge => (
          Icons.info_outline_rounded,
          'The drawing touches the edge of the image, so part of its '
              'outline is the image border.',
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Sky.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
