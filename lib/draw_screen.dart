import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'artwork.dart';
import 'artwork_painter.dart';
import 'canvas_fit.dart';
import 'celebration.dart';
import 'drawing_asset.dart';
import 'gallery_store.dart';
import 'geometry.dart';
import 'palette.dart';
import 'palette_strip.dart';
import 'sound_manager.dart';
import 'sound_policy.dart';
import 'squishy_button.dart';
import 'stroke.dart';
import 'theme.dart';
import 'tool_picker.dart';
import 'trace_guide.dart';

/// The canvas: trace the dashed line, or fill the regions, or both.
class DrawScreen extends StatefulWidget {
  const DrawScreen({super.key, required this.asset, this.reopening});

  final DrawingAsset asset;

  /// A piece being carried on from the gallery.
  final Artwork? reopening;

  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends State<DrawScreen> {
  late final Artwork _artwork =
      widget.reopening ?? Artwork(assetId: widget.asset.id);
  late final TraceProgress _progress =
      TraceProgress(widget.asset.guideDots);

  PaintColor _colour = PaintColor.red;
  DrawTool _tool = DrawTool.crayon;

  StrokeBuilder? _builder;
  Stroke? _liveStroke;
  Vec2? _lastCanvasPoint;

  /// Bumped whenever the finished artwork changed, so the static layer
  /// knows to repaint and the live layer does not have to care.
  int _revision = 0;

  bool _celebrated = false;
  bool _saving = false;

  Size _canvasBox = Size.zero;

  CanvasFit get _fit => CanvasFit.contain(
        widget.asset.canvasSize,
        Vec2(_canvasBox.width, _canvasBox.height),
        padding: 12,
      );

  Vec2 _toCanvas(Offset local) => _fit.toCanvas(Vec2(local.dx, local.dy));

  // ------------------------------------------------------------- drawing

  void _onPointerDown(PointerDownEvent e) {
    if (_canvasBox == Size.zero) return;
    final p = _toCanvas(e.localPosition);

    switch (_tool) {
      case DrawTool.bucket:
        _fillAt(p);
      case DrawTool.eraser:
        _lastCanvasPoint = p;
        _eraseAt(p);
      case DrawTool.pencil:
      case DrawTool.crayon:
      case DrawTool.marker:
        _beginStroke(p);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_canvasBox == Size.zero) return;
    final p = _toCanvas(e.localPosition);

    switch (_tool) {
      case DrawTool.bucket:
        // Dragging the bucket fills everything it crosses, which is how a
        // child actually uses it — and the fill sound is throttled, so it
        // does not machine-gun.
        _fillAt(p);
      case DrawTool.eraser:
        _eraseAt(p);
      case DrawTool.pencil:
      case DrawTool.crayon:
      case DrawTool.marker:
        _extendStroke(p);
    }
    _lastCanvasPoint = p;
  }

  void _onPointerUp(PointerUpEvent e) {
    _endStroke();
    _lastCanvasPoint = null;
  }

  void _beginStroke(Vec2 p) {
    final brush = _tool.brush!;
    _builder = StrokeBuilder(brush: brush, colorKey: _colour.key);
    final snapped = _snap(p);
    _builder!.add(snapped);
    _progress.registerPoint(snapped);
    _lastCanvasPoint = p;
    setState(() => _liveStroke = _builder!.stroke);
    SoundManager.instance.play(Sfx.draw);
  }

  void _extendStroke(Vec2 p) {
    final b = _builder;
    if (b == null) return;
    final snapped = _snap(p);

    // Checkpoints are tested along the whole travelled segment, not just
    // at the sampled points: a fast drag delivers events a long way apart
    // and would otherwise skip every dot it flew over.
    final from = _lastCanvasPoint;
    final newly = from == null
        ? _progress.registerPoint(snapped)
        : _progress.registerSegment(from, snapped);

    b.add(snapped);
    SoundManager.instance.play(Sfx.draw);
    if (newly.isNotEmpty) {
      setState(() {}); // repaint the lit checkpoints
      _checkComplete();
    } else {
      // The live layer repaints from the builder's own point list, so a
      // plain setState is enough and costs one small painter.
      setState(() {});
    }
  }

  void _endStroke() {
    final b = _builder;
    if (b == null) return;
    _builder = null;
    if (!b.stroke.isEmpty) {
      _artwork.addStroke(b.stroke);
      _revision++;
    }
    setState(() => _liveStroke = null);
    _checkComplete();
  }

  /// Pulls a point onto the line art, easing off with distance.
  Vec2 _snap(Vec2 p) {
    final r = snapToOutline(p, widget.asset.outline.subpaths);
    return r.position;
  }

  void _fillAt(Vec2 p) {
    final region = Artwork.regionAt(widget.asset, p);
    if (region == null) return;
    if (_artwork.fill(region.id, _colour.key)) {
      SoundManager.instance.play(Sfx.fill);
      setState(() => _revision++);
    }
  }

  void _eraseAt(Vec2 p) {
    // In canvas units, so the eraser is the same size relative to the
    // drawing on every tablet.
    final removed = _artwork.erase(p, 34);
    if (removed > 0) {
      SoundManager.instance.play(Sfx.draw);
      setState(() => _revision++);
    }
  }

  void _undo() {
    final undone = _artwork.undo();
    if (undone == null) return; // nothing to undo: stay silent
    setState(() => _revision++);
  }

  void _checkComplete() {
    if (_celebrated || !_progress.isComplete) return;
    _celebrated = true;
    SoundManager.instance.play(Sfx.complete);
    setState(() {});
  }

  // -------------------------------------------------------------- saving

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final store = await GalleryStore.open();
      final piece = await store.save(
        asset: widget.asset,
        artwork: _artwork,
        savedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (!mounted) return;
      SoundManager.instance.play(Sfx.complete);
      await showCelebration(context, piece: piece);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final done = _progress.isComplete;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _SideRail(
              onBack: () => Navigator.of(context).pop(false),
              onUndo: _artwork.canUndo ? _undo : null,
              progress: _progress.fraction,
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final box = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        // Assigned during layout, read by the gesture
                        // handlers on the next touch — never during this
                        // build, so it cannot drive a rebuild loop.
                        _canvasBox = box;
                        return Listener(
                          onPointerDown: _onPointerDown,
                          onPointerMove: _onPointerMove,
                          onPointerUp: _onPointerUp,
                          behavior: HitTestBehavior.opaque,
                          child: Stack(
                            children: [
                              // The finished work sits behind its own
                              // repaint boundary, so a moving finger
                              // repaints one stroke rather than an
                              // afternoon of them.
                              Positioned.fill(
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    painter: ArtworkPainter(
                                      asset: widget.asset,
                                      artwork: _artwork,
                                      progress: _progress,
                                      showGuide: !done,
                                      revision: _revision,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: LiveStrokePainter(
                                    asset: widget.asset,
                                    stroke: _liveStroke,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  PaletteStrip(
                    selected: _colour,
                    onSelected: (c) => setState(() => _colour = c),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ToolPicker(
                    selected: _tool,
                    tint: Color(_colour.argb),
                    onSelected: (t) => setState(() => _tool = t),
                  ),
                  const SizedBox(height: kControlGap * 1.5),
                  // The finish button is always here, not only once the
                  // trace is complete: a child who has decided they are
                  // done is done, and hiding the way out until a target
                  // is met is a fail state wearing a different hat.
                  SquishyButton(
                    semanticLabel: 'finished',
                    enabled: !_saving,
                    onPressed: _saving ? null : _finish,
                    child: Container(
                      width: kMinTouchTarget + 8,
                      height: kMinTouchTarget + 8,
                      decoration: BoxDecoration(
                        color: done ? Sky.dotHit : Sky.accent,
                        shape: BoxShape.circle,
                      ),
                      child: _saving
                          ? const Padding(
                              padding: EdgeInsets.all(22),
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded,
                              size: 42, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Back and undo, down the left edge.
///
/// Undo is the biggest control on the screen after the canvas itself —
/// it is the most-used button at this age by a wide margin, and a child
/// who cannot find it will stop drawing rather than ask.
class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.onBack,
    required this.onUndo,
    required this.progress,
  });

  final VoidCallback onBack;
  final VoidCallback? onUndo;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        children: [
          SquishyButton(
            semanticLabel: 'back',
            sfx: Sfx.transition,
            onPressed: onBack,
            child: Container(
              width: kMinTouchTarget,
              height: kMinTouchTarget,
              decoration: const BoxDecoration(
                color: Sky.card,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  size: 34, color: Sky.ink),
            ),
          ),
          const Spacer(),
          SquishyButton(
            semanticLabel: 'undo',
            enabled: onUndo != null,
            onPressed: onUndo,
            child: Container(
              width: kMinTouchTarget + 22,
              height: kMinTouchTarget + 22,
              decoration: BoxDecoration(
                color: Sky.accentSoft,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 5),
              ),
              child: const Icon(Icons.undo_rounded, size: 46, color: Sky.ink),
            ),
          ),
          const Spacer(),
          // How much of the line has been traced, as a ring rather than a
          // number — it says "keep going" without asking anyone to read.
          SizedBox(
            width: 46,
            height: 46,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 300),
              builder: (context, value, _) => CircularProgressIndicator(
                value: value,
                strokeWidth: 8,
                backgroundColor: Sky.accentSoft,
                valueColor: const AlwaysStoppedAnimation(Sky.dotHit),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps the status bar out of the way while drawing.
class ImmersiveScope extends StatefulWidget {
  const ImmersiveScope({super.key, required this.child});

  final Widget child;

  @override
  State<ImmersiveScope> createState() => _ImmersiveScopeState();
}

class _ImmersiveScopeState extends State<ImmersiveScope> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
