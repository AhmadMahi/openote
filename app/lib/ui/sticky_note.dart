import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'break_timer.dart';

/// The floating teaching agenda — a translucent sticky note that sits over the
/// page, fixed to the window (it does not scroll with the page) and never part
/// of it (so it is never exported).
///
/// It doubles as a session planner: turn on timer mode and each item carries a
/// duration you can start and run down. Starting an item folds the note away to
/// a single running line with the minutes left; a break slot opens the
/// full-screen break countdown and completes itself when it ends.
///
/// It is a `Positioned.fill` overlay whose only opaque region is the note
/// itself, so the rest of the canvas stays clickable. In any tool other than
/// Select its BODY ignores the pointer, so you can draw straight over it; the
/// header stays live in every tool, so the note is always draggable.
class StickyNote extends StatelessWidget {
  const StickyNote({super.key, required this.app, this.topInset = 0});
  final AppState app;

  /// How much of the window's top edge is reserved by the floating toolbar.
  /// The note is clamped below it, so however you drag it, it can never sit
  /// over the chrome. Zero in focus mode, where there is no chrome.
  final double topInset;

  static const double _width = 320;

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
                final top = topInset + 12;
                final maxX = math.max(8.0, cons.maxWidth - _width - 8);
                final maxY = math.max(top, cons.maxHeight - 60);
                // Default spot: tucked to the right but BELOW the zoom/fit
                // controls (which live top-right), so it never opens hidden
                // behind them. Once dragged, it stays where it was put.
                final x = (app.stickyX ?? (cons.maxWidth - _width - 20))
                    .clamp(8.0, maxX)
                    .toDouble();
                final y =
                    (app.stickyY ?? (top + 220)).clamp(top, maxY).toDouble();
                final interactive = app.tool == Tool.select;
                // Solidity from the setting; dimmed further in a drawing tool
                // so the note is less in the way while you draw near it.
                final opacity = (interactive
                        ? app.stickyOpacity
                        : app.stickyOpacity * AppState.stickyDrawDim)
                    .clamp(0.0, 1.0)
                    .toDouble();
                return Stack(
                  children: [
                    Positioned(
                      left: x,
                      top: y,
                      width: _width,
                      child: Opacity(
                        opacity: opacity,
                        child: _NoteCard(
                          app: app,
                          x: x,
                          y: y,
                          top: top,
                          bounds: cons.biggest,
                          interactive: interactive,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// A finished session's overtime colour, and the "on time" green.
const Color _green = Color(0xFF2E9E5B);

String _fmtDuration(int minutes) {
  if (minutes <= 0) return '0m';
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// A running item's remaining time as m:ss, negative when in overtime.
String _fmtClock(int seconds) {
  final neg = seconds < 0;
  final a = seconds.abs();
  return '${neg ? '-' : ''}${a ~/ 60}:${(a % 60).toString().padLeft(2, '0')}';
}

class _NoteCard extends StatefulWidget {
  const _NoteCard(
      {required this.app,
      required this.x,
      required this.y,
      required this.top,
      required this.bounds,
      required this.interactive});
  final AppState app;
  final double x, y;

  /// The lowest the note may be dragged (kept below the toolbar).
  final double top;
  final Size bounds;

  /// Whether the body accepts the pointer. False in a drawing tool.
  final bool interactive;

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  final _input = TextEditingController();
  final _minutes = TextEditingController();
  bool _generating = false;

  /// Ticks once a second while an item is running, to refresh the countdown.
  Timer? _ticker;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    // Rebuild as the input changes so the add row can swap between "add" and
    // "copy sample prompt" when it is empty.
    _input.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final running = app.runningStickyIndex >= 0;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  /// Remaining seconds for a running item (negative = overtime).
  int _remaining(StickyItem it) {
    if (it.startedAtMs == null) return it.minutes * 60;
    final elapsed =
        (DateTime.now().millisecondsSinceEpoch - it.startedAtMs!) ~/ 1000;
    return it.minutes * 60 - elapsed;
  }

  void _drag(DragUpdateDetails d) {
    final nx = (widget.x + d.delta.dx)
        .clamp(8.0, math.max(8.0, widget.bounds.width - StickyNote._width - 8))
        .toDouble();
    final ny = (widget.y + d.delta.dy)
        .clamp(widget.top, math.max(widget.top, widget.bounds.height - 60))
        .toDouble();
    app.setStickyPos(nx, ny);
  }

  void _add() {
    final raw = _input.text;
    if (raw.trim().isEmpty) return;
    final lines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (app.stickyTimerMode) {
      // A pasted CSV block (topic, minutes per line) becomes the whole agenda;
      // a single line becomes one timed item, with the minutes field winning
      // if it was filled.
      if (lines.length > 1) {
        app.addStickyAgendaParsed(lines);
      } else {
        final p = AppState.parseAgendaLine(lines.first);
        final field = int.tryParse(_minutes.text.trim());
        app.addStickyItem(p.text,
            minutes: (field != null && field > 0) ? field : p.minutes,
            isBreak: p.isBreak);
      }
    } else {
      // Plain checklist: keep text verbatim (no time parsing), one item a line.
      for (final l in lines) {
        app.addStickyItem(l.trim());
      }
    }
    _input.clear();
    _minutes.clear();
  }

  void _copySamplePrompt() {
    Clipboard.setData(
        const ClipboardData(text: AppState.stickyAgendaSamplePrompt));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
      content: Text('Sample prompt copied — paste it into any LLM, then paste '
          'the CSV it gives back here.'),
    ));
  }

  Future<void> _startItem(int i) async {
    final it = app.stickyItems[i];
    app.startStickyItem(i);
    if (it.isBreak) {
      await showBreakCountdown(context, app,
          minutes: it.minutes > 0 ? it.minutes : 5);
      if (!mounted) return;
      final idx = app.stickyItems.indexOf(it);
      if (idx >= 0) app.completeStickyItem(idx);
    }
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
    // Timer mode returns CSV lines with times/breaks — parse them into timed
    // items; otherwise a plain list.
    if (app.stickyTimerMode) {
      app.setStickyAgendaParsed(items);
    } else {
      app.setStickyItems(items);
    }
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    _syncTicker();
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final minimized = app.stickyMinimized;

    final Widget body = minimized
        ? _minimizedBody(context, s, scheme)
        : Flexible(
            child: IgnorePointer(
                ignoring: !widget.interactive,
                child: _expandedBody(context, s, scheme)));

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: s.raised.withValues(alpha: dark ? 0.62 : 0.74),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.44 : 0.18),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, s, scheme),
              body,
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, OnoteSurfaces s, ColorScheme scheme) {
    final total = app.stickySessionMinutes;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: _drag,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withValues(alpha: 0.16),
              scheme.primary.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(
              bottom: BorderSide(color: s.border.withValues(alpha: 0.6))),
        ),
        child: Row(
          children: [
            Icon(Icons.drag_indicator, size: 16, color: s.textSecondary),
            const SizedBox(width: 2),
            Icon(Icons.sticky_note_2_outlined, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text('Agenda',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OnoteType.uiStrong.copyWith(color: s.textPrimary)),
            ),
            if (app.stickyTimerMode && total > 0) ...[
              const SizedBox(width: 6),
              Text('· ${_fmtDuration(total)}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary)),
            ],
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.timer_outlined, size: 17),
              isSelected: app.stickyTimerMode,
              selectedIcon: Icon(Icons.timer, size: 17, color: scheme.primary),
              tooltip:
                  app.stickyTimerMode ? 'Timer mode: on' : 'Timer mode: off',
              visualDensity: VisualDensity.compact,
              onPressed: app.toggleStickyTimerMode,
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

  /// Minimized: the running item with its countdown and a progress line, or —
  /// when nothing is running — the next thing to teach with a check circle.
  Widget _minimizedBody(
      BuildContext context, OnoteSurfaces s, ColorScheme scheme) {
    final ri = app.runningStickyIndex;
    if (ri >= 0) {
      final it = app.stickyItems[ri];
      final rem = _remaining(it);
      final total = math.max(1, it.minutes * 60);
      final progress = ((total - rem) / total).clamp(0.0, 1.0);
      final over = rem < 0;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 6),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                      it.isBreak ? Icons.free_breakfast : Icons.stop_circle,
                      size: 19,
                      color: scheme.primary),
                  tooltip: 'Complete',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  onPressed: () => app.completeStickyItem(ri),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(it.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OnoteType.ui.copyWith(color: s.textPrimary)),
                ),
                const SizedBox(width: 6),
                if (it.minutes > 0)
                  Text(_fmtClock(rem),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: over ? scheme.error : _green)),
              ],
            ),
          ),
          if (it.minutes > 0)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: s.border.withValues(alpha: 0.4),
                valueColor:
                    AlwaysStoppedAnimation(over ? scheme.error : _green),
              ),
            ),
        ],
      );
    }

    final next = app.nextStickyItem;
    final idx = app.nextStickyIndex;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 12, 10),
      child: Row(
        children: [
          if (next != null)
            IconButton(
              icon: Icon(
                  app.stickyTimerMode
                      ? Icons.play_circle_outline
                      : Icons.radio_button_unchecked,
                  size: 18),
              color: s.textSecondary,
              tooltip: app.stickyTimerMode ? 'Start' : 'Mark done',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              onPressed: () => app.stickyTimerMode
                  ? _startItem(idx)
                  : app.toggleStickyItem(idx),
            )
          else
            const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.check_circle, size: 18, color: _green),
            ),
          const SizedBox(width: 6),
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

  Widget _expandedBody(
      BuildContext context, OnoteSurfaces s, ColorScheme scheme) {
    final items = app.stickyItems;
    final timer = app.stickyTimerMode;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
                timer
                    ? 'Plan your session. Add items with a time each, or type '
                        'rough notes and let AI shape them into a timed agenda.'
                    : 'Your agenda for this session. Add items, or type a few '
                        'rough words and let AI shape them into a to-do list.',
                style: OnoteType.ui
                    .copyWith(color: s.textSecondary, height: 1.35)),
          )
        else
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: items.length,
              onReorder: app.reorderStickyItem,
              itemBuilder: (context, i) => _itemRow(context, s, scheme, i),
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
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    hintText: timer
                        ? 'Add an item (or "break")…'
                        : 'Add an item… or rough notes for AI',
                    hintStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              if (timer) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 44,
                  child: TextField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5),
                    onSubmitted: (_) => _add(),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      hintText: 'min',
                      hintStyle: TextStyle(fontSize: 11),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              // Empty input → offer a sample prompt to build the agenda in any
              // LLM; once you have typed (or pasted a CSV), it becomes Add.
              _input.text.trim().isEmpty
                  ? IconButton(
                      icon: const Icon(Icons.content_copy_outlined, size: 16),
                      tooltip: 'Copy a sample prompt for any LLM',
                      visualDensity: VisualDensity.compact,
                      onPressed: _copySamplePrompt,
                    )
                  : IconButton(
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

  Widget _itemRow(
      BuildContext context, OnoteSurfaces s, ColorScheme scheme, int i) {
    final it = app.stickyItems[i];
    return Padding(
      key: ObjectKey(it),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Drag handle — reorder up/down (Select tool only, since the body
          // ignores the pointer while a pen is up).
          ReorderableDragStartListener(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(Icons.drag_indicator,
                  size: 15, color: s.textSecondary.withValues(alpha: 0.7)),
            ),
          ),
          _leading(s, scheme, it, i),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              it.text,
              style: OnoteType.ui.copyWith(
                color: it.done ? s.textSecondary : s.textPrimary,
                decoration: it.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (app.stickyTimerMode) _minutesChip(scheme, s, it, i),
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

  /// The leading control: a simple check off timer mode; in timer mode a
  /// play → running-countdown → done progression.
  Widget _leading(OnoteSurfaces s, ColorScheme scheme, StickyItem it, int i) {
    if (!app.stickyTimerMode) {
      return IconButton(
        icon: Icon(it.done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18, color: it.done ? _green : s.textSecondary),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(),
        onPressed: () => app.toggleStickyItem(i),
      );
    }
    if (it.done) {
      return IconButton(
        icon: const Icon(Icons.check_circle, size: 18, color: _green),
        tooltip: 'Undo',
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(),
        onPressed: () => app.toggleStickyItem(i),
      );
    }
    if (it.running) {
      final rem = _remaining(it);
      final over = rem < 0;
      return Tooltip(
        message: 'Complete',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => app.completeStickyItem(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: (over ? scheme.error : _green).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              it.minutes > 0 ? _fmtClock(rem) : 'stop',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: over ? scheme.error : _green),
            ),
          ),
        ),
      );
    }
    // Not started: play.
    return IconButton(
      icon: Icon(
          it.isBreak
              ? Icons.free_breakfast_outlined
              : Icons.play_circle_outline,
          size: 19,
          color: scheme.primary),
      tooltip: it.isBreak ? 'Start break' : 'Start',
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      onPressed: () => _startItem(i),
    );
  }

  /// A small pill showing the item's minutes; tap to change from a preset list.
  Widget _minutesChip(
      ColorScheme scheme, OnoteSurfaces s, StickyItem it, int i) {
    return PopupMenuButton<int>(
      tooltip: 'Set time',
      padding: EdgeInsets.zero,
      onSelected: (m) => app.setStickyItemMinutes(i, m),
      itemBuilder: (_) => [
        for (final m in const [5, 10, 15, 20, 25, 30, 45, 60, 90])
          PopupMenuItem(value: m, height: 34, child: Text(_fmtDuration(m))),
      ],
      child: Container(
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: s.well.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(it.minutes > 0 ? _fmtDuration(it.minutes) : 'set',
            style: TextStyle(fontSize: 11, color: s.textSecondary)),
      ),
    );
  }
}
