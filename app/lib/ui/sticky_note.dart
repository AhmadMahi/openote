import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';

/// The floating teaching agenda — a translucent sticky note that sits over the
/// page, fixed to the window (it does not scroll with the page) and never part
/// of it (so it is never exported). One per notebook.
///
/// It is a `Positioned.fill` overlay whose only opaque region is the note
/// itself, so the rest of the canvas stays clickable. In any tool other than
/// Select it ignores the pointer, so you can draw straight over it and it stays
/// put. Minimise shows only the next unchecked item; close hides it but keeps
/// the list until you delete it.
class StickyNote extends StatelessWidget {
  const StickyNote({super.key, required this.app});
  final AppState app;

  static const double _width = 300;

  @override
  Widget build(BuildContext context) {
    // ALWAYS a Positioned child of the editor Stack — a non-positioned child
    // (even a zero-size one) would make the Stack size to it and collapse the
    // layout. When closed it simply renders nothing.
    return Positioned.fill(
      child: !app.stickyOpen
          ? const SizedBox.shrink()
          : LayoutBuilder(
              builder: (context, cons) {
                final x = (app.stickyX ?? (cons.maxWidth - _width - 24))
                    .clamp(8.0, math.max(8.0, cons.maxWidth - _width - 8))
                    .toDouble();
                final y = (app.stickyY ?? 84.0)
                    .clamp(8.0, math.max(8.0, cons.maxHeight - 60))
                    .toDouble();
                // Interactive only in Select; in a drawing tool the note ignores the
                // pointer so a stroke lands on the canvas beneath it.
                final interactive = app.tool == Tool.select;
                return Stack(
                  children: [
                    Positioned(
                      left: x,
                      top: y,
                      width: _width,
                      child: IgnorePointer(
                        ignoring: !interactive,
                        child: _NoteCard(
                            app: app, x: x, y: y, bounds: cons.biggest),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _NoteCard extends StatefulWidget {
  const _NoteCard(
      {required this.app,
      required this.x,
      required this.y,
      required this.bounds});
  final AppState app;
  final double x, y;
  final Size bounds;

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  final _input = TextEditingController();
  bool _generating = false;

  AppState get app => widget.app;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _drag(DragUpdateDetails d) {
    final nx = (widget.x + d.delta.dx)
        .clamp(8.0, math.max(8.0, widget.bounds.width - StickyNote._width - 8))
        .toDouble();
    final ny = (widget.y + d.delta.dy)
        .clamp(8.0, math.max(8.0, widget.bounds.height - 60))
        .toDouble();
    app.setStickyPos(nx, ny);
  }

  void _add() {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    app.addStickyItem(t);
    _input.clear();
  }

  Future<void> _generate() async {
    final rough = _input.text.trim();
    if (rough.isEmpty || _generating) return;
    setState(() => _generating = true);
    final items = await app.generateStickyAgenda(rough);
    if (!mounted) return;
    setState(() => _generating = false);
    if (items == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('Connect an AI provider to generate an agenda.')));
      return;
    }
    app.setStickyItems(items);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final minimized = app.stickyMinimized;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: s.raised.withValues(alpha: dark ? 0.72 : 0.82),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: s.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.4 : 0.16),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, s),
              if (minimized)
                _minimizedBody(context, s)
              else
                Flexible(child: _expandedBody(context, s)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, OnoteSurfaces s) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: _drag,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: s.well.withValues(alpha: 0.6),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Row(
          children: [
            Icon(Icons.drag_indicator, size: 16, color: s.textSecondary),
            const SizedBox(width: 4),
            Icon(Icons.sticky_note_2_outlined,
                size: 15, color: s.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Agenda',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OnoteType.uiStrong.copyWith(color: s.textPrimary)),
            ),
            IconButton(
              icon: Icon(
                  app.stickyMinimized ? Icons.unfold_more : Icons.unfold_less,
                  size: 17),
              tooltip: app.stickyMinimized ? 'Expand' : 'Minimize',
              visualDensity: VisualDensity.compact,
              onPressed: () => app.setStickyMinimized(!app.stickyMinimized),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 17),
              tooltip: 'Hide (your list is kept)',
              visualDensity: VisualDensity.compact,
              onPressed: app.toggleStickyOpen,
            ),
          ],
        ),
      ),
    );
  }

  /// Minimized: only the next thing to teach.
  Widget _minimizedBody(BuildContext context, OnoteSurfaces s) {
    final next = app.nextStickyItem;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Row(
        children: [
          Icon(next == null ? Icons.check_circle : Icons.arrow_forward,
              size: 15,
              color: next == null ? const Color(0xFF2E9E5B) : s.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              next?.text ??
                  (app.stickyItems.isEmpty ? 'No items yet' : 'All done 🎉'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: OnoteType.ui.copyWith(color: s.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _expandedBody(BuildContext context, OnoteSurfaces s) {
    final items = app.stickyItems;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
                'Your agenda for this session. Add items, or type a few rough '
                'words and let AI shape them into a to-do list.',
                style: OnoteType.ui
                    .copyWith(color: s.textSecondary, height: 1.35)),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: items.length,
              itemBuilder: (context, i) => _itemRow(context, s, i),
            ),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 12.5),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'Add an item… or rough notes for AI',
                    hintStyle: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'Add item',
                visualDensity: VisualDensity.compact,
                onPressed: _add,
              ),
              _generating
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(
                      icon: const Icon(Icons.auto_awesome, size: 17),
                      tooltip: 'Shape into an agenda with AI',
                      visualDensity: VisualDensity.compact,
                      onPressed: _generate,
                    ),
            ],
          ),
        ),
        if (items.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 6),
              child: TextButton.icon(
                onPressed: app.clearStickyItems,
                icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                label: const Text('Delete all', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _itemRow(BuildContext context, OnoteSurfaces s, int i) {
    final it = app.stickyItems[i];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: Icon(
                it.done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: it.done ? const Color(0xFF2E9E5B) : s.textSecondary),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            onPressed: () => app.toggleStickyItem(i),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                it.text,
                style: OnoteType.ui.copyWith(
                  color: it.done ? s.textSecondary : s.textPrimary,
                  decoration: it.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            color: s.textSecondary,
            onPressed: () => app.deleteStickyItem(i),
          ),
        ],
      ),
    );
  }
}
