import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';

/// The floating shapes palette: a small draggable bar of shapes and teaching
/// marks, like the Sticky-notes panel. Pick a shape (check, cross, circle,
/// rectangle, triangle, line, arrow, star) and it arms the Shapes tool; a drag
/// on the page then places it. A colour row sets the next shape's colour; the
/// check and cross come pre-set to green and red.
class ShapesPalette extends StatefulWidget {
  const ShapesPalette({super.key, required this.app, required this.topInset});
  final AppState app;
  final double topInset;

  @override
  State<ShapesPalette> createState() => _ShapesPaletteState();
}

class _ShapesPaletteState extends State<ShapesPalette> {
  Offset? _pos; // null until first build, then anchored under the chrome

  static const _shapes =
      <({String kind, IconData icon, String tip, int? color})>[
    (kind: 'check', icon: Icons.check, tip: 'Check / right', color: 0xFF2E9E5B),
    (kind: 'cross', icon: Icons.close, tip: 'Cross / wrong', color: 0xFFE5484D),
    (kind: 'circle', icon: Icons.circle_outlined, tip: 'Circle', color: null),
    (kind: 'rectangle', icon: Icons.crop_square, tip: 'Rectangle', color: null),
    (
      kind: 'triangle',
      icon: Icons.change_history,
      tip: 'Triangle',
      color: null
    ),
    (kind: 'line', icon: Icons.horizontal_rule, tip: 'Line', color: null),
    (kind: 'arrow', icon: Icons.north_east, tip: 'Arrow', color: null),
    (kind: 'star', icon: Icons.star_outline, tip: 'Star', color: null),
  ];

  static const _colors = <int>[
    0xFF2E9E5B, // green
    0xFFE5484D, // red
    0xFF2563EB, // blue
    0xFFF59E0B, // amber
    0xFF18181B, // near-black
  ];

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    final pos = _pos ?? Offset(16, widget.topInset + 12);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 196,
          decoration: BoxDecoration(
            color: s.raised,
            borderRadius: OnoteRadius.lgAll,
            border: Border.all(color: s.border),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Draggable header.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => setState(() {
                  final size = MediaQuery.of(context).size;
                  final next = pos + d.delta;
                  _pos = Offset(
                    next.dx.clamp(0.0, size.width - 196),
                    next.dy.clamp(widget.topInset, size.height - 80),
                  );
                }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
                  child: Row(
                    children: [
                      Icon(Icons.drag_indicator,
                          size: 16, color: s.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('Shapes',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: s.textPrimary)),
                      ),
                      InkWell(
                        onTap: app.toggleShapesOpen,
                        borderRadius: OnoteRadius.smAll,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(Icons.close,
                              size: 15, color: s.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final sh in _shapes)
                      _ShapeCell(
                        icon: sh.icon,
                        tip: sh.tip,
                        selected:
                            app.tool == Tool.shape && app.shapeKind == sh.kind,
                        accent: scheme.primary,
                        surfaces: s,
                        onTap: () => app.armShape(sh.kind, colorHex: sh.color),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
                child: Row(
                  children: [
                    for (final hex in _colors)
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: InkWell(
                          onTap: () => app.setShapeColorHex(hex),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Color(hex),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: app.shapeColorHex == hex
                                      ? scheme.primary
                                      : Colors.transparent,
                                  width: 2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShapeCell extends StatelessWidget {
  const _ShapeCell({
    required this.icon,
    required this.tip,
    required this.selected,
    required this.accent,
    required this.surfaces,
    required this.onTap,
  });
  final IconData icon;
  final String tip;
  final bool selected;
  final Color accent;
  final OnoteSurfaces surfaces;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onTap,
        borderRadius: OnoteRadius.mdAll,
        child: Container(
          width: 38,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.14) : null,
            borderRadius: OnoteRadius.mdAll,
            border: Border.all(
                color:
                    selected ? accent : surfaces.border.withValues(alpha: 0.6)),
          ),
          child: Icon(icon,
              size: 18, color: selected ? accent : surfaces.textPrimary),
        ),
      ),
    );
  }
}
