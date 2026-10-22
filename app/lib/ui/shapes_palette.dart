import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';

/// The floating shapes palette: a small draggable bar of shapes and teaching
/// marks, like the Sticky-notes panel. Pick a shape and it arms the Shapes
/// tool; a click on the page then stamps it at the chosen size, keeping its
/// proper proportions. One size applies to every shape; colour is changed with
/// the K key (the same key the pen uses), and the check and cross come pre-set
/// to green and red.
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
    (
      kind: 'diamond',
      icon: Icons.diamond_outlined,
      tip: 'Diamond',
      color: null
    ),
    (
      kind: 'pentagon',
      icon: Icons.pentagon_outlined,
      tip: 'Pentagon',
      color: null
    ),
    (
      kind: 'hexagon',
      icon: Icons.hexagon_outlined,
      tip: 'Hexagon',
      color: null
    ),
    (kind: 'star', icon: Icons.star_outline, tip: 'Star', color: null),
    (kind: 'line', icon: Icons.horizontal_rule, tip: 'Line', color: null),
    (kind: 'arrow', icon: Icons.north_east, tip: 'Arrow', color: null),
    (
      kind: 'double_arrow',
      icon: Icons.sync_alt,
      tip: 'Double arrow',
      color: null
    ),
    (kind: 'plus', icon: Icons.add, tip: 'Plus', color: null),
    (kind: 'minus', icon: Icons.remove, tip: 'Minus', color: null),
    (
      kind: 'cloud',
      icon: Icons.cloud_outlined,
      tip: 'Thought cloud',
      color: null
    ),
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
              const Divider(height: 1),
              // One universal size for every shape, and a reminder that K sets
              // the colour (the same key the pen uses).
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 8, 8),
                child: Row(
                  children: [
                    Text('Size',
                        style:
                            TextStyle(fontSize: 11.5, color: s.textSecondary)),
                    const Spacer(),
                    _SizeButton(
                      icon: Icons.remove,
                      onTap: () => app.setShapeSize(app.shapeSize - 8),
                      surfaces: s,
                    ),
                    SizedBox(
                      width: 34,
                      child: Text('${app.shapeSize.round()}',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 11.5, color: s.textPrimary)),
                    ),
                    _SizeButton(
                      icon: Icons.add,
                      onTap: () => app.setShapeSize(app.shapeSize + 8),
                      surfaces: s,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Color(app.shapeColorHex),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('Press K to change colour',
                        style:
                            TextStyle(fontSize: 10.5, color: s.textSecondary)),
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

class _SizeButton extends StatelessWidget {
  const _SizeButton(
      {required this.icon, required this.onTap, required this.surfaces});
  final IconData icon;
  final VoidCallback onTap;
  final OnoteSurfaces surfaces;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: OnoteRadius.smAll,
      child: Container(
        width: 26,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: OnoteRadius.smAll,
          border: Border.all(color: surfaces.border.withValues(alpha: 0.6)),
        ),
        child: Icon(icon, size: 15, color: surfaces.textSecondary),
      ),
    );
  }
}
