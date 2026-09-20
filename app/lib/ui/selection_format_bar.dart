import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

/// A small floating format bar that appears over the page when you select text
/// in a text block, so bold / italic / underline / highlight / heading are one
/// tap away instead of a trip to the Format menu.
///
/// Like the sticky note it is ALWAYS a `Positioned.fill` child of the editor
/// Stack (a non-positioned child would collapse the Stack); it renders nothing
/// until there is a live selection. It reads the active editor's controller
/// directly, because the caret-watch in [AppState] only notifies when the set
/// of marks changes, not on every selection move.
class SelectionFormatBar extends StatelessWidget {
  const SelectionFormatBar({super.key, required this.app});
  final AppState app;

  static const double _barHeight = 38;
  static const double _estWidth = 224;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final ed = app.activeEditor;
          if (ed == null || ed.block.type != BlockType.text) {
            return const SizedBox.shrink();
          }
          // The controller carries the selection; watch it so the bar tracks
          // the drag, not just marks-at-caret changes.
          return AnimatedBuilder(
            animation: ed.controller,
            builder: (context, _) {
              final sel = ed.controller.selection;
              if (!sel.isValid || sel.isCollapsed) {
                return const SizedBox.shrink();
              }
              return LayoutBuilder(
                builder: (context, cons) {
                  final b = ed.block;
                  final tl = app.canvas.pageToScreen(Offset(b.x, b.y));
                  final left = tl.dx
                      .clamp(8.0, math.max(8.0, cons.maxWidth - _estWidth - 8))
                      .toDouble();
                  // Above the block; if there is no room above, tuck it just
                  // below the block's top instead of off the top edge.
                  final wantTop = tl.dy - _barHeight - 10;
                  final top = (wantTop < 8 ? tl.dy + 8 : wantTop)
                      .clamp(
                          8.0, math.max(8.0, cons.maxHeight - _barHeight - 8))
                      .toDouble();
                  return Stack(children: [
                    Positioned(
                      left: left,
                      top: top,
                      child: _Bar(app: app),
                    ),
                  ]);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: SelectionFormatBar._barHeight,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: s.raised.withValues(alpha: dark ? 0.86 : 0.94),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: s.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.4 : 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _btn(Icons.format_bold, 'Bold  (Ctrl+B)',
                    () => app.wrapSelection('**')),
                _btn(Icons.format_italic, 'Italic  (Ctrl+I)',
                    () => app.wrapSelection('*')),
                _btn(Icons.format_underlined, 'Underline  (Ctrl+U)',
                    () => app.wrapSelection('++')),
                _btn(Icons.border_color, 'Highlight',
                    () => app.wrapSelection('==')),
                _sep(s),
                _btn(Icons.title, 'Heading', () => app.toggleLinePrefix('# ')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sep(OnoteSurfaces s) => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        color: s.border,
      );

  Widget _btn(IconData icon, String tip, VoidCallback onTap) => IconButton(
        icon: Icon(icon, size: 17),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        padding: EdgeInsets.zero,
        onPressed: onTap,
      );
}
