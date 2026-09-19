import 'dart:io';

import 'package:flutter/material.dart';

import 'asset_library.dart';
import 'draw_screen.dart';
import 'gallery_store.dart';
import 'mascot.dart';
import 'sound_policy.dart';
import 'squishy_button.dart';
import 'theme.dart';

/// Everything that has been finished, newest first.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.library});

  final AssetLibrary library;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<SavedPiece>? _pieces;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = await GalleryStore.open();
    final pieces = await store.list();
    if (!mounted) return;
    setState(() => _pieces = pieces);
  }

  @override
  Widget build(BuildContext context) {
    final pieces = _pieces;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: SquishyButton(
                semanticLabel: 'back',
                sfx: Sfx.transition,
                onPressed: () => Navigator.of(context).pop(),
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
            ),
            Expanded(
              child: pieces == null
                  ? const Center(child: CircularProgressIndicator())
                  : pieces.isEmpty
                      // An empty gallery shows the mascot rather than a
                      // sentence explaining that it is empty.
                      ? const Center(
                          child: Mascot(size: 180, mood: MascotMood.watching),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(20),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 260,
                            mainAxisSpacing: kControlGap,
                            crossAxisSpacing: kControlGap,
                            childAspectRatio: 1,
                          ),
                          itemCount: pieces.length,
                          itemBuilder: (context, i) => _PieceCard(
                            piece: pieces[i],
                            onPressed: () => _reopen(pieces[i]),
                            onDelete: () => _delete(pieces[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens a saved piece back on its own line art, to be added to.
  Future<void> _reopen(SavedPiece piece) async {
    final asset = widget.library.byId(piece.assetId);
    if (asset == null) return;
    final store = await GalleryStore.open();
    final artwork = await store.reopen(piece.id);
    if (!mounted || artwork == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DrawScreen(asset: asset, reopening: artwork),
      ),
    );
    await _load();
  }

  Future<void> _delete(SavedPiece piece) async {
    // Deleting is the one destructive thing in the app, so it asks — with
    // pictures, since the audience cannot read the question.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Sky.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  File(piece.pngPath),
                  width: 140,
                  height: 140,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 24),
              SquishyButton(
                semanticLabel: 'keep it',
                onPressed: () => Navigator.of(context).pop(false),
                child: Container(
                  width: kMinTouchTarget,
                  height: kMinTouchTarget,
                  decoration: const BoxDecoration(
                    color: Sky.dotHit,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.favorite_rounded,
                      size: 34, color: Colors.white),
                ),
              ),
              const SizedBox(width: kControlGap),
              SquishyButton(
                semanticLabel: 'throw it away',
                onPressed: () => Navigator.of(context).pop(true),
                child: Container(
                  width: kMinTouchTarget,
                  height: kMinTouchTarget,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE57373),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_rounded,
                      size: 34, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;
    final store = await GalleryStore.open();
    await store.delete(piece.id);
    await _load();
  }
}

class _PieceCard extends StatelessWidget {
  const _PieceCard({
    required this.piece,
    required this.onPressed,
    required this.onDelete,
  });

  final SavedPiece piece;
  final VoidCallback onPressed;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: SquishyButton(
            semanticLabel: 'drawing',
            sfx: Sfx.transition,
            onPressed: onPressed,
            child: Container(
              decoration: BoxDecoration(
                color: Sky.card,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.file(File(piece.pngPath), fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: SquishyButton(
            semanticLabel: 'remove this drawing',
            onPressed: onDelete,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Sky.card,
                shape: BoxShape.circle,
                border: Border.all(color: Sky.accentSoft, width: 3),
              ),
              child: const Icon(Icons.close_rounded, size: 26, color: Sky.ink),
            ),
          ),
        ),
      ],
    );
  }
}
