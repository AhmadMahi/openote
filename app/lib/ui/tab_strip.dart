import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';

/// The editor's tab strip: the small set of pages the user opened with
/// "Open in new tab", shown across the top of the editor. Empty (and takes no
/// room) until the first tab is opened. The active tab — the page on screen —
/// is highlighted; each tab closes with its ×.
class TabStrip extends StatelessWidget {
  const TabStrip({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    if (app.openTabs.isEmpty) return const SizedBox.shrink();
    final s = context.surfaces;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: s.well,
        border: Border(bottom: BorderSide(color: s.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
    final scheme = Theme.of(context).colorScheme;
    final active = widget.app.isActiveTab(widget.tab);
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

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: active ? null : () => widget.app.activateTab(widget.tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(maxWidth: 190),
          padding: const EdgeInsets.only(left: 12, right: 6),
          decoration: BoxDecoration(
            color: active
                ? s.raised
                : _hover
                    ? s.raised.withValues(alpha: 0.5)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color:
                    active ? scheme.primary.withValues(alpha: 0.55) : s.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined,
                  size: 15, color: active ? scheme.primary : s.textSecondary),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OnoteType.ui.copyWith(
                    color: active ? s.textPrimary : s.textSecondary,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: () => widget.app.closeTab(widget.tab),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(Icons.close,
                      size: 14,
                      color: (active || _hover)
                          ? s.textSecondary
                          : s.textSecondary.withValues(alpha: 0.45)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
