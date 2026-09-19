import 'package:flutter/material.dart';

import 'palette.dart';
import 'sound_manager.dart';
import 'sound_policy.dart';
import 'squishy_button.dart';
import 'theme.dart';

/// The colours, along the bottom of the drawing screen.
///
/// Scrollable, but sized so all six fit without scrolling on any tablet —
/// a control a child has to scroll to reach is a control they will not
/// find. The scroll exists so a seventh colour later does not break the
/// layout, not because anyone is expected to use it.
class PaletteStrip extends StatelessWidget {
  const PaletteStrip({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final PaintColor selected;
  final ValueChanged<PaintColor> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kMinTouchTarget + 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: PaintColor.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: kControlGap),
        itemBuilder: (context, i) {
          final colour = PaintColor.values[i];
          final isSelected = colour == selected;
          return SquishyButton(
            sfx: Sfx.colorSelect,
            // Each colour rings a step higher, so the palette is worth
            // touching for its own sake at this age.
            rate: SoundManager.instance
                .colorRate(i, PaintColor.values.length),
            semanticLabel: colour.key,
            onPressed: () => onSelected(colour),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: isSelected ? kMinTouchTarget + 10 : kMinTouchTarget,
              height: isSelected ? kMinTouchTarget + 10 : kMinTouchTarget,
              decoration: BoxDecoration(
                color: Color(colour.argb),
                shape: BoxShape.circle,
                border: Border.all(
                  // The selected swatch grows and gains a white collar.
                  // Size and a ring, not a tick: a tick is a symbol that
                  // has to be learned, and bigger is not.
                  color: isSelected ? Colors.white : Colors.white54,
                  width: isSelected ? 6 : 3,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
