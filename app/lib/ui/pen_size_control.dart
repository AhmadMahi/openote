import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';

/// The stroke-thickness control: a small slider, the value, and an up/down
/// stepper. The slider is for a rough sweep; the stepper is for landing on an
/// exact width without fighting the slider. Pen and highlighter each have their
/// own width (see [AppState.penSize]), so this control shows whichever tool is
/// active. Used both in the Draw ribbon and the focus-mode palette.
class PenSizeControl extends StatelessWidget {
  const PenSizeControl({super.key, required this.app, this.sliderWidth = 78});
  final AppState app;
  final double sliderWidth;

  static String _fmt(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final size = app.penSize.clamp(AppState.minPenSize, AppState.maxPenSize);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: sliderWidth,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: size.toDouble(),
              min: AppState.minPenSize,
              max: AppState.maxPenSize,
              // Half-point steps, so the slider lands on the same values the
              // stepper does — no more stray 8.25 to nudge off.
              divisions: ((AppState.maxPenSize - AppState.minPenSize) /
                      AppState.penSizeStep)
                  .round(),
              onChanged: app.setPenSize,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 22,
          child: Text(
            _fmt(size.toDouble()),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: s.textSecondary),
          ),
        ),
        const SizedBox(width: 2),
        // The up/down stepper: exact width without the slider's precision.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Step(
              icon: Icons.keyboard_arrow_up,
              tooltip: 'Thicker',
              onTap: size >= AppState.maxPenSize
                  ? null
                  : () => app.setPenSize(size + AppState.penSizeStep),
            ),
            _Step(
              icon: Icons.keyboard_arrow_down,
              tooltip: 'Thinner',
              onTap: size <= AppState.minPenSize
                  ? null
                  : () => app.setPenSize(size - AppState.penSizeStep),
            ),
          ],
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 18,
          height: 13,
          child: Icon(icon,
              size: 15,
              color: onTap == null
                  ? s.textSecondary.withValues(alpha: 0.35)
                  : s.textSecondary),
        ),
      ),
    );
  }
}
