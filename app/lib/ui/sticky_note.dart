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

  /// The note's size before it has ever been resized.
  static const double _defaultWidth = 360;
  static const double _defaultHeight = 360;

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
                // Width and expanded height come from the saved size (dragged
                // from the corner), clamped to the note's limits and to what
                // the editor area can actually hold.
                final maxW = math.max(AppState.minStickyW, cons.maxWidth - 16);
                final w = (app.stickyW ?? _defaultWidth)
                    .clamp(AppState.minStickyW, maxW)
                    .toDouble();
                final maxH =
                    math.max(AppState.minStickyH, cons.maxHeight - top - 16);
                final h = (app.stickyH ?? _defaultHeight)
                    .clamp(AppState.minStickyH, maxH)
                    .toDouble();
                final maxX = math.max(8.0, cons.maxWidth - w - 8);
                final maxY = math.max(top, cons.maxHeight - 60);
                // Default spot: tucked to the right but BELOW the zoom/fit
                // controls (which live top-right), so it never opens hidden
                // behind them. Once dragged, it stays where it was put.
                final x = (app.stickyX ?? (cons.maxWidth - w - 20))
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
                      width: w,
                      child: Opacity(
                        opacity: opacity,
                        child: _NoteCard(
                          app: app,
                          x: x,
                          y: y,
                          top: top,
                          width: w,
                          height: h,
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
      required this.width,
      required this.height,
      required this.bounds,
      required this.interactive});
  final AppState app;
  final double x, y;

  /// The current note size (width always; height applies when expanded).
  final double width, height;

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

  /// Whether the pointer is over the bottom-right corner (shows the resize
  /// arrow, which is otherwise hidden).
  bool _hoverResize = false;

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
        .clamp(8.0, math.max(8.0, widget.bounds.width - widget.width - 8))
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
        : Expanded(
            child: IgnorePointer(
                ignoring: !widget.interactive,
                child: _expandedBody(context, s, scheme)));

    final Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          // Expanded: a fixed height (dragged from the corner) so the list
          // scrolls inside it. Minimized: hug the single line.
          height: minimized ? null : widget.height,
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
            mainAxisSize: minimized ? MainAxisSize.min : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, s, scheme),
              body,
            ],
          ),
        ),
      ),
    );

    // The bottom-right resize grip: pull it diagonally to set width/height.
    // Only when expanded and the Select tool is armed (the body is live).
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        if (!minimized && widget.interactive)
          Positioned(
            right: 0,
            bottom: 0,
            child: _resizeHandle(s, scheme),
          ),
      ],
    );
  }

  Widget _resizeHandle(OnoteSurfaces s, ColorScheme scheme) {
    // No permanent grip; a small arrow fades in only while you hover the very
    // corner, hinting you can pull to resize. Kept small so it never steals the
    // AI button's clicks.
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpLeftDownRight,
      onEnter: (_) => setState(() => _hoverResize = true),
      onExit: (_) => setState(() => _hoverResize = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => app.setStickySize(
            widget.width + d.delta.dx, widget.height + d.delta.dy),
        child: SizedBox(
          width: 18,
          height: 18,
          child: AnimatedOpacity(
            opacity: _hoverResize ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: Padding(
              padding: const EdgeInsets.only(right: 3, bottom: 3),
              child: Icon(Icons.south_east_rounded,
                  size: 13, color: s.textSecondary.withValues(alpha: 0.9)),
            ),
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
              tooltip: app.stickyTimerMode
                  ? 'Session timer: on'
                  : 'Session timer: off',
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

  /// Every control in the add bar shares this height, so the input, the minutes
  /// field and the icon buttons line up on one baseline.
  static const double _ctlH = 38;

  Widget _expandedBody(
      BuildContext context, OnoteSurfaces s, ColorScheme scheme) {
    final items = app.stickyItems;
    final timer = app.stickyTimerMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: items.isEmpty
              ? SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Text(
                        timer
                            ? 'Plan your session. Add items with a time each, or '
                                'type rough notes and let AI shape them into a '
                                'timed agenda.'
                            : 'Your agenda for this session. Add items, or type a '
                                'few rough words and let AI shape them into a '
                                'to-do list.',
                        style: OnoteType.ui
                            .copyWith(color: s.textSecondary, height: 1.4)),
                  ),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  // Delete-all is a real last row (past five items), so it is
                  // out of sight until you scroll down to the end of the list.
                  // It carries no drag handle, so it cannot be picked up; and
                  // reorderStickyItem clamps any drop, so nothing lands "after"
                  // it.
                  itemCount: items.length + (items.length > 5 ? 1 : 0),
                  onReorder: app.reorderStickyItem,
                  itemBuilder: (context, i) => i < items.length
                      ? _itemRow(context, s, scheme, i)
                      : _deleteAllItem(s, scheme),
                ),
        ),
        Divider(height: 1, color: s.border.withValues(alpha: 0.6)),
        _addBar(context, s, scheme, timer),
      ],
    );
  }

  /// The bottom add bar: input, optional minutes, copy/add, and the AI button —
  /// all the same height. The controls top-align so the input can grow for a
  /// pasted block without shifting the buttons.
  Widget _addBar(
      BuildContext context, OnoteSurfaces s, ColorScheme scheme, bool timer) {
    final empty = _input.text.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _inputField(s, scheme, timer)),
          if (timer) ...[
            const SizedBox(width: 8),
            _minutesField(s, scheme),
          ],
          const SizedBox(width: 8),
          // Empty input → offer a sample prompt to build the agenda in any LLM;
          // once you have typed (or pasted a CSV), it becomes Add.
          empty
              ? _squareButton(s, scheme,
                  icon: Icons.content_copy_outlined,
                  tooltip: 'Copy a sample prompt for any LLM',
                  onTap: _copySamplePrompt)
              : _squareButton(s, scheme,
                  icon: Icons.add,
                  tooltip: 'Add item',
                  onTap: _add,
                  accent: true),
          const SizedBox(width: 6),
          _generating
              ? const SizedBox(
                  width: _ctlH,
                  height: _ctlH,
                  child: Center(
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              : _squareButton(s, scheme,
                  icon: Icons.auto_awesome,
                  tooltip: 'Shape into an agenda with AI',
                  onTap: _generate,
                  accent: true),
        ],
      ),
    );
  }

  Widget _inputField(OnoteSurfaces s, ColorScheme scheme, bool timer) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _ctlH),
      child: TextField(
        controller: _input,
        minLines: 1,
        maxLines: 4,
        style: const TextStyle(fontSize: 13),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _add(),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: s.well.withValues(alpha: 0.6),
          prefixIcon: Icon(Icons.add, size: 17, color: s.textSecondary),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 30, minHeight: _ctlH),
          contentPadding: const EdgeInsets.fromLTRB(0, 9, 10, 9),
          border: OutlineInputBorder(
            borderRadius: OnoteRadius.mdAll,
            borderSide: BorderSide(color: s.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: OnoteRadius.mdAll,
            borderSide: BorderSide(color: s.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: OnoteRadius.mdAll,
            borderSide: BorderSide(color: scheme.primary),
          ),
          hintText: timer
              ? 'Add an item (or "break")…'
              : 'Add an item… or rough notes for AI',
          // Keep the placeholder on one line so the bar stays a single row at
          // rest; typed or pasted text still grows the field up to maxLines.
          hintMaxLines: 1,
          hintStyle: TextStyle(fontSize: 12.5, color: s.textSecondary),
        ),
      ),
    );
  }

  Widget _minutesField(OnoteSurfaces s, ColorScheme scheme) {
    return SizedBox(
      width: 66,
      height: _ctlH,
      child: TextField(
        controller: _minutes,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 13),
        onSubmitted: (_) => _add(),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: s.well.withValues(alpha: 0.6),
          prefixIcon:
              Icon(Icons.timer_outlined, size: 15, color: s.textSecondary),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 26, minHeight: _ctlH),
          contentPadding: const EdgeInsets.fromLTRB(0, 9, 6, 9),
          border: OutlineInputBorder(
            borderRadius: OnoteRadius.mdAll,
            borderSide: BorderSide(color: s.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: OnoteRadius.mdAll,
            borderSide: BorderSide(color: s.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: OnoteRadius.mdAll,
            borderSide: BorderSide(color: scheme.primary),
          ),
          hintText: 'min',
          hintStyle: TextStyle(fontSize: 12, color: s.textSecondary),
        ),
      ),
    );
  }

  /// A square, bordered icon button that matches the input height.
  Widget _squareButton(OnoteSurfaces s, ColorScheme scheme,
      {required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
      bool accent = false}) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: _ctlH,
        height: _ctlH,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: s.well.withValues(alpha: 0.6),
              borderRadius: OnoteRadius.mdAll,
              border: Border.all(color: s.border),
            ),
            child: InkWell(
              borderRadius: OnoteRadius.mdAll,
              onTap: onTap,
              child: Center(
                child: Icon(icon,
                    size: 18, color: accent ? scheme.primary : s.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The delete-all control: a clearly-destructive red bar at the end of the
  /// agenda, shown only once the list is long enough to need it (past five
  /// items), so it never crowds a short list.
  Widget _deleteAllItem(OnoteSurfaces s, ColorScheme scheme) {
    return Padding(
      // Required: every ReorderableListView child is keyed.
      key: const ValueKey('sticky-delete-all'),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Material(
        color: scheme.error.withValues(alpha: 0.10),
        borderRadius: OnoteRadius.mdAll,
        child: InkWell(
          borderRadius: OnoteRadius.mdAll,
          onTap: app.clearStickyItems,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_sweep_outlined,
                    size: 16, color: scheme.error),
                const SizedBox(width: 8),
                Text('Delete all',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.error)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemRow(
      BuildContext context, OnoteSurfaces s, ColorScheme scheme, int i) {
    final it = app.stickyItems[i];
    return Padding(
      key: ObjectKey(it),
      padding: const EdgeInsets.fromLTRB(6, 5, 4, 5),
      child: Row(
        // Top-align so a long item that wraps to several lines keeps its
        // controls beside the first line rather than floating at the middle.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle — reorder up/down (Select tool only, since the body
          // ignores the pointer while a pen is up).
          ReorderableDragStartListener(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(right: 2, top: 6),
              child: Icon(Icons.drag_indicator,
                  size: 15, color: s.textSecondary.withValues(alpha: 0.7)),
            ),
          ),
          _leading(s, scheme, it, i),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                it.text,
                style: OnoteType.ui.copyWith(
                  height: 1.3,
                  color: it.done ? s.textSecondary : s.textPrimary,
                  decoration: it.done ? TextDecoration.lineThrough : null,
                ),
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
        margin: const EdgeInsets.only(right: 2, top: 4),
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
