import 'package:flutter/material.dart';

import 'artwork_painter.dart';
import 'asset_library.dart';
import 'draw_screen.dart';
import 'drawing_asset.dart';
import 'sound_policy.dart';
import 'squishy_button.dart';
import 'theme.dart';

/// The thumbnail grid for one category.
class CategoryScreen extends StatelessWidget {
  const CategoryScreen({
    super.key,
    required this.library,
    required this.category,
  });

  final AssetLibrary library;
  final ArtCategory category;

  @override
  Widget build(BuildContext context) {
    final assets = library.inCategory(category.id);

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
              child: GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  // Max extent rather than a fixed column count, so the
                  // cards stay a sensible size on a 7" tablet and on a
                  // 13" one instead of stretching to fill.
                  maxCrossAxisExtent: 260,
                  mainAxisSpacing: kControlGap,
                  crossAxisSpacing: kControlGap,
                  childAspectRatio: 1,
                ),
                itemCount: assets.length,
                itemBuilder: (context, i) => _ArtCard(
                  asset: assets[i],
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DrawScreen(asset: assets[i]),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtCard extends StatelessWidget {
  const _ArtCard({required this.asset, required this.onPressed});

  final DrawingAsset asset;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SquishyButton(
      semanticLabel: asset.title,
      sfx: Sfx.transition,
      onPressed: onPressed,
      child: Container(
        decoration: BoxDecoration(
          color: Sky.card,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: CustomPaint(painter: ThumbnailPainter(asset)),
              ),
            ),
            // The difficulty mark: one, two or three dots. Dots rather
            // than a number, because a number is a thing to read and a
            // thing to be graded by.
            Positioned(
              right: 12,
              bottom: 12,
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < asset.difficulty
                              ? Sky.accent
                              : Sky.accentSoft,
                        ),
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
