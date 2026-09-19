import 'package:flutter/material.dart';

import 'palette.dart';
import 'squishy_button.dart';
import 'theme.dart';

/// What a touch on the canvas does.
enum DrawTool {
  pencil,
  crayon,
  marker,

  /// Tap a region, it fills. What a younger child reaches for first.
  bucket,

  /// Rubs out whole strokes. Never removes a fill's region boundary or
  /// the line art — there is nothing a child can do here that damages the
  /// drawing they were given.
  eraser,
}

extension DrawToolBrush on DrawTool {
  /// The brush this tool draws with, or null if it is not a drawing tool.
  BrushKind? get brush => switch (this) {
        DrawTool.pencil => BrushKind.pencil,
        DrawTool.crayon => BrushKind.crayon,
        DrawTool.marker => BrushKind.marker,
        DrawTool.bucket || DrawTool.eraser => null,
      };

  IconData get icon => switch (this) {
        DrawTool.pencil => Icons.create,
        DrawTool.crayon => Icons.brush,
        DrawTool.marker => Icons.edit,
        DrawTool.bucket => Icons.format_color_fill,
        DrawTool.eraser => Icons.cleaning_services,
      };

  String get label => switch (this) {
        DrawTool.pencil => 'pencil',
        DrawTool.crayon => 'crayon',
        DrawTool.marker => 'marker',
        DrawTool.bucket => 'fill',
        DrawTool.eraser => 'eraser',
      };
}

/// The tool column down the side of the drawing screen.
///
/// A column rather than a second bottom row: landscape is where the width
/// is, and stacking two horizontal bars would eat the canvas from the one
/// direction it cannot spare.
class ToolPicker extends StatelessWidget {
  const ToolPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.tint,
  });

  final DrawTool selected;
  final ValueChanged<DrawTool> onSelected;

  /// The current paint colour, shown on the tools that use it — so the
  /// answer to "what will this do" is on the button itself.
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final tool in DrawTool.values) ...[
          _ToolButton(
            tool: tool,
            selected: tool == selected,
            tint: tool == DrawTool.eraser ? Sky.ink : tint,
            onPressed: () => onSelected(tool),
          ),
          if (tool != DrawTool.values.last)
            const SizedBox(height: kControlGap),
        ],
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tool,
    required this.selected,
    required this.tint,
    required this.onPressed,
  });

  final DrawTool tool;
  final bool selected;
  final Color tint;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SquishyButton(
      semanticLabel: tool.label,
      onPressed: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: kMinTouchTarget,
        height: kMinTouchTarget,
        decoration: BoxDecoration(
          color: selected ? tint : Sky.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? Colors.white : Sky.accentSoft,
            width: selected ? 5 : 3,
          ),
        ),
        child: Icon(
          tool.icon,
          size: 34,
          // On a selected tool the icon sits on the paint colour, so it
          // has to survive both a yellow and a purple behind it.
          color: selected
              ? (tint.computeLuminance() > 0.55 ? Sky.ink : Colors.white)
              : Sky.ink,
        ),
      ),
    );
  }
}
