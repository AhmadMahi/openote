import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';

/// The editor's tab strip: the small set of pages the user opened with
/// "Open in new tab", shown across the top of the editor as browser-style tabs.
/// Empty (and takes no room) until the first tab is opened. The active tab —
/// the page on screen — is raised and accented; each tab closes with its ×.
class TabStrip extends StatelessWidget {
  const TabStrip({super.key, required this.app});
  final AppState app;

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
      height: 44,
      decoration: BoxDecoration(
        color: s.well,
        border: Border(bottom: BorderSide(color: s.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
        itemCount: app.openTabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) => _Tab(app: app, tab: app.openTabs[i]),
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({required this.app, required this.tab});
  final AppState app;
  final PageTab tab;

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

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: active ? null : () => widget.app.activateTab(widget.tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(maxWidth: 200, minWidth: 96),
          padding: const EdgeInsets.only(left: 11, right: 6),
          decoration: BoxDecoration(
            color: active
                ? s.raised
                : _hover
                    ? s.raised.withValues(alpha: dark ? 0.45 : 0.6)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  active ? accent.withValues(alpha: 0.55) : Colors.transparent,
              width: active ? 1.4 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.3 : 0.10),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_rounded,
                  size: 16,
                  color: active ? accent : accent.withValues(alpha: 0.55)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OnoteType.ui.copyWith(
                    color: active ? s.textPrimary : s.textSecondary,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // A steady slot so the label does not shift when × appears; the ×
              // only shows for the active or hovered tab.
              SizedBox(
                width: 20,
                height: 20,
                child: showClose
                    ? _CloseButton(
                        color: s.textSecondary,
                        onTap: () => widget.app.closeTab(widget.tab),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.color, required this.onTap});
  final Color color;
  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _hover ? s.border : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(Icons.close,
              size: 14,
              color:
                  _hover ? s.textPrimary : widget.color.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}
