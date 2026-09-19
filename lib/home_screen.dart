import 'package:flutter/material.dart';

import 'artwork_painter.dart';
import 'asset_library.dart';
import 'category_screen.dart';
import 'drawing_asset.dart';
import 'gallery_screen.dart';
import 'mascot.dart';
import 'sound_manager.dart';
import 'sound_policy.dart';
import 'squishy_button.dart';
import 'theme.dart';

/// The menu. Mascot on the left, categories on the right, gallery and
/// mute tucked into the corner.
///
/// There is no title, no instructions and no words anywhere: the audience
/// cannot read, and a screen of text they have to be told about is a
/// screen they need an adult for.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.library});

  final AssetLibrary library;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final categories = widget.library.categories;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Center(
                    child: SquishyButton(
                      semanticLabel: 'Dreamy',
                      sfx: Sfx.mascot,
                      shadow: false,
                      // Tapping the mascot does nothing but make him
                      // squeak. That is the point: the first thing a small
                      // child does on any screen is poke the face, and it
                      // should answer.
                      onPressed: () {},
                      child: const Mascot(size: 220),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Center(
                    child: Wrap(
                      spacing: kControlGap * 1.5,
                      runSpacing: kControlGap * 1.5,
                      alignment: WrapAlignment.center,
                      children: [
                        for (var i = 0; i < categories.length; i++)
                          _CategoryTile(
                            category: categories[i],
                            tint: Sky.categoryTints[
                                i % Sky.categoryTints.length],
                            preview: widget.library
                                .inCategory(categories[i].id)
                                .firstOrNull,
                            onPressed: () => _open(categories[i]),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  _CornerButton(
                    icon: Icons.photo_library_rounded,
                    label: 'gallery',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            GalleryScreen(library: widget.library),
                      ),
                    ),
                  ),
                  const SizedBox(width: kControlGap),
                  ValueListenableBuilder<bool>(
                    valueListenable: SoundManager.instance.mutedNotifier,
                    builder: (context, muted, _) => _CornerButton(
                      icon: muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      label: muted ? 'sound off' : 'sound on',
                      onPressed: SoundManager.instance.toggleMute,
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

  void _open(ArtCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryScreen(
          library: widget.library,
          category: category,
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.tint,
    required this.preview,
    required this.onPressed,
  });

  final ArtCategory category;
  final Color tint;

  /// One drawing from the category, shown on the tile. A picture of a
  /// dinosaur is the only label that works for someone who cannot read
  /// the word "dinosaurs".
  final DrawingAsset? preview;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SquishyButton(
      semanticLabel: category.title,
      sfx: Sfx.transition,
      onPressed: onPressed,
      child: Container(
        width: 240,
        height: 200,
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white, width: 6),
        ),
        child: preview == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.all(14),
                child: CustomPaint(painter: ThumbnailPainter(preview!)),
              ),
      ),
    );
  }
}

class _CornerButton extends StatelessWidget {
  const _CornerButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SquishyButton(
      semanticLabel: label,
      onPressed: onPressed,
      child: Container(
        width: kMinTouchTarget,
        height: kMinTouchTarget,
        decoration: const BoxDecoration(
          color: Sky.card,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 34, color: Sky.ink),
      ),
    );
  }
}
