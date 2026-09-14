import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../mindmap/mindmap.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

/// A mind map on the page: a left-to-right tree you build by typing.
///
/// content: `{ root: <MindNode json> }`
///
/// Enter adds a sibling branch and Ctrl/Cmd+C a child (Tab also makes a child);
/// Ctrl/Cmd+Shift+C outdents. A branch with children folds and unfolds; nodes
/// take a colour (solid or translucent), and one button tints each branch a
/// different hue automatically. The tree is laid out automatically — you don't
/// place nodes by hand — and the whole block drags and resizes on the page,
/// both wider and taller. Scrolling or two-finger panning over the map moves
/// the map, not the page beneath it. A toolbar mirrors the keys so it is usable
/// without knowing them, and a Markdown outline can be imported into it.
class MindmapBlockView extends StatefulWidget {
  const MindmapBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  State<MindmapBlockView> createState() => _MindmapBlockViewState();
}

class _MindmapBlockViewState extends State<MindmapBlockView> {
  late MindNode _root;
  String? _selectedId;
  String? _editingId;
  final _editController = TextEditingController();
  final _editFocus = FocusNode();

  // Pan/zoom of the map inside its own window, so a wheel or two-finger scroll
  // moves the map rather than the page. The trackpad drives this controller
  // natively; the mouse wheel is fed into it by [_wheelPan].
  final _tc = TransformationController();
  Size _viewport = Size.zero; // the map window's size, for clamping the pan
  Size _contentSize = Size.zero; // the laid-out tree's size

  // Layout constants (logical px, before the canvas zoom).
  static const double _nodeW = 156;
  static const double _hGap = 44;
  static const double _vGap = 12;
  static const double _padH = 10;
  static const double _padV = 8;
  static const double _minH = 34;

  @override
  void initState() {
    super.initState();
    final raw = widget.block.content['root'];
    _root = raw is Map
        ? MindNode.fromJson(raw.cast<String, dynamic>())
        : MindNode.starter();
    _selectedId = _root.id;
    _editFocus.addListener(() {
      if (!_editFocus.hasFocus && _editingId != null) _commitEdit(save: true);
    });
    // A brand-new starter map opens ready to rename its centre.
    if (raw is! Map) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _beginEdit(_root.id));
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocus.dispose();
    _tc.dispose();
    super.dispose();
  }

  /// Pan the map by a mouse-wheel notch, and claim the notch so the page it
  /// sits on does not scroll out from under it. A wheel notch is delivered to
  /// every listener under the pointer; registering with the shared resolver
  /// means this map is the one that moves. The trackpad's two-finger pan is a
  /// different event family that the InteractiveViewer already handles, and is
  /// kept off the page by the pointer claim on the enclosing Listener.
  void _wheelPan(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      final scale = _tc.value.getMaxScaleOnAxis();
      final shift = HardwareKeyboard.instance.isShiftPressed;
      // A mouse's vertical wheel scrolls the map sideways when Shift is held,
      // matching the page's own wheel behaviour.
      final d = shift
          ? Offset(e.scrollDelta.dy + e.scrollDelta.dx, 0)
          : e.scrollDelta;
      const b = 400.0; // must match the InteractiveViewer's boundaryMargin
      final m = _tc.value.clone();
      var tx = m[12] - d.dx;
      var ty = m[13] - d.dy;
      // Keep the pan within the same bounds a drag would: the window may see
      // from `-b` past the content's far edge to `+b` before it, in map units.
      final loX = _viewport.width - (_contentSize.width + b) * scale;
      final loY = _viewport.height - (_contentSize.height + b) * scale;
      tx = tx.clamp(math.min(loX, b * scale), b * scale);
      ty = ty.clamp(math.min(loY, b * scale), b * scale);
      m[12] = tx;
      m[13] = ty;
      _tc.value = m;
    });
  }

  void _save() {
    widget.block.content['root'] = _root.toJson();
    widget.block.updatedAt = nowMs();
    widget.app.updateBlock(widget.block);
  }

  // ── Tree helpers ────────────────────────────────────────────────────────

  MindNode? _find(String id, [MindNode? from]) {
    final n = from ?? _root;
    if (n.id == id) return n;
    for (final c in n.children) {
      final hit = _find(id, c);
      if (hit != null) return hit;
    }
    return null;
  }

  MindNode? _parentOf(String id, [MindNode? from]) {
    final n = from ?? _root;
    for (final c in n.children) {
      if (c.id == id) return n;
      final hit = _parentOf(id, c);
      if (hit != null) return hit;
    }
    return null;
  }

  void _commitEdit({bool save = false}) {
    final id = _editingId;
    if (id == null) return;
    final node = _find(id);
    if (node != null) node.text = _editController.text.trim();
    _editingId = null;
    if (save) _save();
    if (mounted) setState(() {});
  }

  void _beginEdit(String id) {
    final node = _find(id);
    if (node == null) return;
    setState(() {
      _selectedId = id;
      _editingId = id;
      _editController.text = node.text;
      _editController.selection =
          TextSelection(baseOffset: 0, extentOffset: node.text.length);
    });
    _editFocus.requestFocus();
  }

  void _addChild(String id) {
    _commitEdit();
    final node = _find(id);
    if (node == null) return;
    node.collapsed = false;
    final child = MindNode();
    node.children.add(child);
    _save();
    _beginEdit(child.id);
  }

  void _addSibling(String id) {
    _commitEdit();
    final parent = _parentOf(id);
    if (parent == null) {
      // The root has no sibling; make a child instead.
      _addChild(id);
      return;
    }
    final i = parent.children.indexWhere((c) => c.id == id);
    final sib = MindNode();
    parent.children.insert(i + 1, sib);
    _save();
    _beginEdit(sib.id);
  }

  void _outdent(String id) {
    _commitEdit();
    final parent = _parentOf(id);
    if (parent == null) return; // root
    final grand = _parentOf(parent.id);
    if (grand == null) return; // already a first-level branch
    final node = _find(id)!;
    parent.children.removeWhere((c) => c.id == id);
    final pi = grand.children.indexWhere((c) => c.id == parent.id);
    grand.children.insert(pi + 1, node);
    _save();
    _beginEdit(id);
  }

  void _deleteSelected() {
    final id = _selectedId;
    if (id == null || id == _root.id) return; // never delete the centre
    _commitEdit();
    final parent = _parentOf(id);
    if (parent == null) return;
    parent.children.removeWhere((c) => c.id == id);
    setState(() => _selectedId = parent.id);
    _save();
  }

  void _toggleCollapse(String id) {
    final node = _find(id);
    if (node == null || node.children.isEmpty) return;
    setState(() => node.collapsed = !node.collapsed);
    _save();
  }

  void _setColor(String color) {
    final id = _selectedId;
    if (id == null) return;
    final node = _find(id);
    if (node == null) return;
    setState(() => node.color = color);
    _save();
  }

  /// Give every top-level branch its own hue, shared down its whole subtree, so
  /// the map reads by colour at a glance. Manual per-node colours still win the
  /// moment you set one afterwards — this only fills them in in one go.
  void _autoColorBranches() {
    final keys = _hues.keys.toList();
    void paint(MindNode n, String key) {
      n.color = key;
      for (final c in n.children) {
        paint(c, key);
      }
    }

    final kids = _root.children;
    if (kids.isEmpty) {
      // Nothing has branched yet: tint the centre so the button still responds.
      setState(() => _root.color = keys.first);
      _save();
      return;
    }
    for (var i = 0; i < kids.length; i++) {
      paint(kids[i], keys[i % keys.length]);
    }
    setState(() {});
    _save();
  }

  Future<void> _importMarkdown() async {
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [
        XTypeGroup(label: 'Markdown', extensions: ['md', 'markdown', 'txt'])
      ]);
    } catch (_) {
      return;
    }
    if (file == null) return;
    final text = await file.readAsString();
    setState(() {
      _root = parseMarkdownOutline(text);
      _selectedId = _root.id;
      _editingId = null;
    });
    _save();
  }

  // ── Layout (left to right) ──────────────────────────────────────────────

  double _measure(String text) {
    final tp = TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: _textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 3,
    )..layout(maxWidth: _nodeW - 2 * _padH);
    return math.max(_minH, tp.height + 2 * _padV);
  }

  static const _textStyle = TextStyle(fontSize: 13, height: 1.25);

  ({Map<String, Rect> rects, Size size}) _layout() {
    final rects = <String, Rect>{};
    var maxX = 0.0, maxY = 0.0, cursorY = 0.0;

    double place(MindNode n, int depth) {
      final x = depth * (_nodeW + _hGap);
      final h = _measure(n.text);
      if (n.collapsed || n.children.isEmpty) {
        final y = cursorY;
        rects[n.id] = Rect.fromLTWH(x, y, _nodeW, h);
        cursorY += h + _vGap;
        maxX = math.max(maxX, x + _nodeW);
        maxY = math.max(maxY, y + h);
        return y + h / 2;
      }
      final centers = [for (final c in n.children) place(c, depth + 1)];
      final mid = (centers.first + centers.last) / 2;
      final y = mid - h / 2;
      rects[n.id] = Rect.fromLTWH(x, y, _nodeW, h);
      maxX = math.max(maxX, x + _nodeW);
      maxY = math.max(maxY, y + h);
      return mid;
    }

    place(_root, 0);
    return (rects: rects, size: Size(maxX + 4, maxY + 4));
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final laid = _layout();
    _contentSize = laid.size;

    final canvas = Shortcuts(
      // Ctrl/Cmd+C makes a child (a modifier chord, so plain "c" still types
      // while you name a node); Tab does too. Enter makes a sibling and lives on
      // the field itself (onSubmitted). Our mapping sits nearer the focused field
      // than the app's default copy shortcut, so Ctrl/Cmd+C means "child" inside
      // the map without triggering copy.
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyC, control: true): _ChildIntent(),
        SingleActivator(LogicalKeyboardKey.keyC, meta: true): _ChildIntent(),
        SingleActivator(LogicalKeyboardKey.tab): _ChildIntent(),
        SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
            _OutdentIntent(),
        SingleActivator(LogicalKeyboardKey.keyC, meta: true, shift: true):
            _OutdentIntent(),
        SingleActivator(LogicalKeyboardKey.tab, shift: true): _OutdentIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ChildIntent: CallbackAction<_ChildIntent>(onInvoke: (_) {
            final id = _editingId ?? _selectedId;
            if (id != null) _addChild(id);
            return null;
          }),
          _OutdentIntent: CallbackAction<_OutdentIntent>(onInvoke: (_) {
            final id = _editingId ?? _selectedId;
            if (id != null) _outdent(id);
            return null;
          }),
        },
        // Keep scroll and two-finger panning inside the map, not the page:
        // claim the pointer so PageCanvas declines to move the page under a
        // trackpad pan/pinch (the graph block's pattern), and route the mouse
        // wheel through _wheelPan so a notch pans the map instead of the page.
        child: Listener(
          onPointerDown: (e) => widget.app.claimedPointers.add(e.pointer),
          onPointerUp: (e) => widget.app.claimedPointers.remove(e.pointer),
          onPointerCancel: (e) => widget.app.claimedPointers.remove(e.pointer),
          onPointerPanZoomStart: (e) =>
              widget.app.claimedPointers.add(e.pointer),
          onPointerPanZoomEnd: (e) =>
              widget.app.claimedPointers.remove(e.pointer),
          onPointerSignal: _wheelPan,
          child: ClipRect(
            child: LayoutBuilder(builder: (context, vp) {
              _viewport = Size(vp.maxWidth, vp.maxHeight);
              return InteractiveViewer(
                transformationController: _tc,
                constrained: false,
                minScale: 0.4,
                maxScale: 2.5,
                boundaryMargin: const EdgeInsets.all(400),
                child: SizedBox(
                  width: math.max(laid.size.width, 40),
                  height: math.max(laid.size.height, 40),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ConnectorPainter(
                            root: _root,
                            rects: laid.rects,
                            color: s.border,
                          ),
                        ),
                      ),
                      for (final entry in laid.rects.entries)
                        _positionedNode(
                            context, s, dark, entry.key, entry.value),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: s.raised,
        borderRadius: OnoteRadius.lgAll,
        border: Border.all(color: s.border),
      ),
      clipBehavior: Clip.antiAlias,
      // A definite height for the map area, because a free block hands us an
      // UNBOUNDED height and a Flexible/Expanded cannot live in that. When the
      // block has been resized we fill the height it was given; otherwise the
      // map is as tall as its tree, capped so a big map still fits on the page
      // and pans/zooms inside.
      child: LayoutBuilder(builder: (context, cons) {
        const toolbarH = 44.0;
        final mapH = cons.maxHeight.isFinite
            ? math.max(80.0, cons.maxHeight - toolbarH)
            : math.min(laid.size.height + 12, 360.0);
        return Column(
          mainAxisSize:
              cons.maxHeight.isFinite ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: toolbarH, child: _toolbar(context, s)),
            SizedBox(height: mapH, child: canvas),
          ],
        );
      }),
    );
  }

  Widget _toolbar(BuildContext context, OnoteSurfaces s) {
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          icon: Icon(icon, size: 18),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
        );
    final sel = _selectedId;
    final selNode = sel == null ? null : _find(sel);
    return Container(
      color: s.well,
      padding: const EdgeInsets.symmetric(horizontal: OnoteSpace.x2),
      child: Row(
        children: [
          Icon(Icons.account_tree_outlined, size: 16, color: s.textSecondary),
          const Spacer(),
          btn(Icons.subdirectory_arrow_right, 'Add child  (Ctrl/Cmd+C)',
              sel == null ? null : () => _addChild(sel)),
          btn(Icons.add, 'Add sibling  (Enter)',
              sel == null ? null : () => _addSibling(sel)),
          if (selNode != null && selNode.children.isNotEmpty)
            btn(
                selNode.collapsed ? Icons.unfold_more : Icons.unfold_less,
                selNode.collapsed ? 'Expand' : 'Collapse',
                () => _toggleCollapse(sel!)),
          _colorButton(context, s),
          btn(Icons.auto_awesome_outlined, 'Auto-colour each branch',
              _autoColorBranches),
          btn(Icons.delete_outline, 'Delete branch',
              (sel == null || sel == _root.id) ? null : _deleteSelected),
          btn(Icons.upload_file_outlined, 'Import a Markdown outline',
              _importMarkdown),
        ],
      ),
    );
  }

  Widget _colorButton(BuildContext context, OnoteSurfaces s) {
    return PopupMenuButton<String>(
      tooltip: 'Colour',
      icon: const Icon(Icons.palette_outlined, size: 18),
      onSelected: _setColor,
      itemBuilder: (_) => [
        for (final row in _swatchRows)
          PopupMenuItem<String>(
            enabled: false,
            height: 34,
            child: Row(
              children: [
                for (final key in row)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      onTap: () {
                        _setColor(key);
                        Navigator.of(context).pop();
                      },
                      child: _swatch(key, s),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _swatch(String key, OnoteSurfaces s) {
    final st =
        _nodeStyle(key, Theme.of(context).brightness == Brightness.dark, s);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: st.fill,
        border: Border.all(color: st.border, width: 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: key == 'none'
          ? Icon(Icons.not_interested, size: 12, color: s.textSecondary)
          : null,
    );
  }

  Widget _positionedNode(
      BuildContext context, OnoteSurfaces s, bool dark, String id, Rect r) {
    final node = _find(id)!;
    final selected = _selectedId == id;
    final editing = _editingId == id;
    final st = _nodeStyle(node.color, dark, s);
    final hasChildren = node.children.isNotEmpty;

    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: () {
              if (selected && !editing) {
                _beginEdit(id);
              } else {
                _commitEdit(save: true);
                setState(() => _selectedId = id);
              }
            },
            onDoubleTap: () => _beginEdit(id),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: _padH, vertical: _padV),
              decoration: BoxDecoration(
                color: st.fill,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : st.border,
                  width: selected ? 2 : 1.2,
                ),
              ),
              alignment: Alignment.centerLeft,
              child: editing
                  ? TextField(
                      controller: _editController,
                      focusNode: _editFocus,
                      maxLines: 1,
                      style: _textStyle.copyWith(color: st.text),
                      cursorColor: st.text,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                      ),
                      onChanged: (t) {
                        node.text = t;
                      },
                      onSubmitted: (_) => _addSibling(id),
                    )
                  : Text(
                      node.text.isEmpty ? ' ' : node.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: _textStyle.copyWith(color: st.text),
                    ),
            ),
          ),
          // Collapse / expand knob on the right edge, where the children hang.
          if (hasChildren)
            Positioned(
              right: -9,
              top: r.height / 2 - 9,
              child: GestureDetector(
                onTap: () => _toggleCollapse(id),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: s.raised,
                    shape: BoxShape.circle,
                    border: Border.all(color: s.border),
                  ),
                  child: Icon(
                    node.collapsed ? Icons.add : Icons.remove,
                    size: 12,
                    color: s.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Colour palette ────────────────────────────────────────────────────────

  static const _hues = <String, int>{
    'slate': 0xFF64748B,
    'blue': 0xFF3B82F6,
    'teal': 0xFF14B8A6,
    'green': 0xFF22C55E,
    'amber': 0xFFF59E0B,
    'red': 0xFFEF4444,
    'violet': 0xFF8B5CF6,
    'pink': 0xFFEC4899,
  };

  // Two rows in the picker: translucent tints, then solids; 'none' leads.
  static final List<List<String>> _swatchRows = [
    ['none', ..._hues.keys],
    [for (final k in _hues.keys) '$k-solid'],
  ];

  ({Color fill, Color border, Color text}) _nodeStyle(
      String key, bool dark, OnoteSurfaces s) {
    if (key == 'none' || key.isEmpty) {
      return (fill: s.well, border: s.border, text: s.textPrimary);
    }
    final solid = key.endsWith('-solid');
    final hue = solid ? key.substring(0, key.length - 6) : key;
    final base = Color(_hues[hue] ?? 0xFF64748B);
    if (solid) {
      return (fill: base, border: base, text: Colors.white);
    }
    // Translucent: a soft tint that reads as glass, coloured border, page text.
    return (
      fill: base.withValues(alpha: dark ? 0.22 : 0.15),
      border: base.withValues(alpha: 0.6),
      text: s.textPrimary,
    );
  }
}

class _ChildIntent extends Intent {
  const _ChildIntent();
}

class _OutdentIntent extends Intent {
  const _OutdentIntent();
}

/// The branch lines: a smooth curve from each parent's right edge to each
/// visible child's left edge.
class _ConnectorPainter extends CustomPainter {
  _ConnectorPainter(
      {required this.root, required this.rects, required this.color});

  final MindNode root;
  final Map<String, Rect> rects;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    void walk(MindNode n) {
      final pr = rects[n.id];
      if (pr == null) return;
      if (n.collapsed) return;
      for (final c in n.children) {
        final cr = rects[c.id];
        if (cr == null) continue;
        final p1 = Offset(pr.right, pr.center.dy);
        final p2 = Offset(cr.left, cr.center.dy);
        final dx = (p2.dx - p1.dx) / 2;
        final path = Path()
          ..moveTo(p1.dx, p1.dy)
          ..cubicTo(p1.dx + dx, p1.dy, p2.dx - dx, p2.dy, p2.dx, p2.dy);
        canvas.drawPath(path, paint);
        walk(c);
      }
    }

    walk(root);
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter old) =>
      old.rects != rects || old.color != color;
}
