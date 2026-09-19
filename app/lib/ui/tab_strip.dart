import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';

/// The editor's tab strip: the pages the user opened with "Open in new tab",
/// shown across the top of the editor as Chrome-style tabs. Empty (and takes no
/// room) until the first tab is opened.
///
/// The active tab is raised, keeps its rounded top, and its background matches
/// the content below while it covers the divider under itself — so it reads as
/// connected to the page, the way a browser tab does. Inactive tabs sit a little
/// lower with a muted fill; the whole strip scrolls when the tabs overflow.
class TabStrip extends StatelessWidget {
  const TabStrip({super.key, required this.app});
  final AppState app;

  static const double _barHeight = 42;

  /// A stable, per-page accent so a tab keeps its colour as others come and go.
  static const _palette = <Color>[
    Color(0xFF3B82F6), // blue
    Color(0xFFF97316), // orange
    Color(0xFFF59E0B), // amber
    Color(0xFFEC4899), // pink
    Color(0xFF22C55E), // green
    Color(0xFF8B5CF6), // violet
    Color(0xFF14B8A6), // teal
  ];

  static Color colorFor(String pageId) =>
      _palette[pageId.hashCode.abs() % _palette.length];

  @override
  Widget build(BuildContext context) {
    if (app.openTabs.isEmpty) return const SizedBox.shrink();
    final s = context.surfaces;
    return Container(
      height: _barHeight,
      decoration: BoxDecoration(
        color: s.well,
        // The thin divider beneath the whole bar; the active tab paints over
        // the slice of it under itself, which is what makes it look connected.
        border: Border(bottom: BorderSide(color: s.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 8, right: 8),
        itemCount: app.openTabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 3),
        itemBuilder: (context, i) =>
            _Tab(app: app, tab: app.openTabs[i], barHeight: _barHeight),
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({required this.app, required this.tab, required this.barHeight});
  final AppState app;
  final PageTab tab;
  final double barHeight;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = widget.app.isActiveTab(widget.tab);
    final accent = TabStrip.colorFor(widget.tab.pageId);

    // The live title when the tab is in the open notebook, else the cached one.
    final live = widget.app.notebookId == widget.tab.notebookId
        ? widget.app.nodes
            .where((n) => n.id == widget.tab.pageId)
            .firstOrNull
            ?.title
        : null;
    final title = (live == null || live.isEmpty)
        ? (widget.tab.title.isEmpty ? 'Untitled' : widget.tab.title)
        : live;

    final showClose = active || _hover;
    const radius = BorderRadius.vertical(top: Radius.circular(12));

    // Bottom-align so the active tab reaches the bar's bottom edge (covering
    // the divider) while inactive tabs sit a touch lower and recessed.
    return Align(
      alignment: Alignment.bottomCenter,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Semantics(
          button: true,
          selected: active,
          label: 'Tab: $title',
          child: InkWell(
            onTap: active ? null : () => widget.app.activateTab(widget.tab),
            borderRadius: radius,
            focusColor: accent.withValues(alpha: 0.18),
            hoverColor: Colors.transparent,
            // Clip to the rounded top so the active accent strip below follows
            // the corner radius instead of squaring off at the top edge — the
            // "slightly off" corner the owner pointed out.
            child: ClipRRect(
              borderRadius: radius,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                height: active ? widget.barHeight : widget.barHeight - 7,
                constraints: const BoxConstraints(maxWidth: 220, minWidth: 108),
                decoration: BoxDecoration(
                  // Active matches the content surface; inactive is transparent
                  // (a faint fill on hover) so it reads as recessed.
                  color: active
                      ? s.raised
                      : _hover
                          ? s.raised.withValues(alpha: dark ? 0.4 : 0.55)
                          : Colors.transparent,
                  border: Border(
                    // Hairline sides define the tab shape against the bar; the
                    // coloured top indicator is the clipped strip below, not a
                    // border, so its ends round with the corner.
                    left: BorderSide(
                        color: active ? s.border : Colors.transparent),
                    right: BorderSide(
                        color: active ? s.border : Colors.transparent),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.description_rounded,
                                size: 16,
                                color: active
                                    ? accent
                                    : accent.withValues(alpha: 0.55)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OnoteType.ui.copyWith(
                                  color:
                                      active ? s.textPrimary : s.textSecondary,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // A steady slot so the label does not shift when ×
                            // appears; the × only shows for the active or
                            // hovered tab.
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: showClose
                                  ? _CloseButton(
                                      color: s.textSecondary,
                                      tooltip: 'Close tab',
                                      onTap: () =>
                                          widget.app.closeTab(widget.tab),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (active)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(height: 2.5, color: accent),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton(
      {required this.color, required this.onTap, required this.tooltip});
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            decoration: BoxDecoration(
              color: _hover ? s.border : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(Icons.close,
                size: 14,
                color: _hover
                    ? s.textPrimary
                    : widget.color.withValues(alpha: 0.7)),
          ),
        ),
      ),
    );
  }
}
