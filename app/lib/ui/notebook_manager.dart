import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../export/import_job.dart';
import '../export/md_import.dart';
import '../export/onenote_import.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'join_git_dialog.dart';
import 'onboarding.dart';
import 'restore_dialog.dart';
import 'sync_dot.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';

/// After deleting a notebook, offer to also remove it from the central GitHub
/// backup (only when that backup is on). Deleting the copy on GitHub is the
/// kind of thing to ask about, not do silently.
Future<void> maybeRemoveFromBackup(
    BuildContext context, AppState app, String nbId, String title) async {
  if (!app.central.enabled) return;
  final also = await showOnoteDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Also delete from the backup?'),
      content: Text(
        '"$title" was deleted here. Remove it from the GitHub backup too? '
        'If you keep it, the backup still holds a copy.',
        style: const TextStyle(fontSize: 13, height: 1.4),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep in backup')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete from backup')),
      ],
    ),
  );
  if (also != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final err = await app.central.removeNotebook(nbId, title);
  messenger?.showSnackBar(
      SnackBar(content: Text(err ?? 'Removed "$title" from the backup.')));
}

/// The notebook manager (style guide §7b) — the one place notebooks are managed.
///
/// **Why a panel and not a pointer menu.** Management used to live in the
/// notebook dropdown: right-clicking a row popped a context menu, which closed
/// the dropdown underneath it. The action worked but the surface you were
/// working in vanished, which read as broken, and deleting three notebooks meant
/// reopening the dropdown three times. Here the list is *stable*: rename in
/// place, delete with an inline confirm, restore from the trash — the list never
/// disappears, and you can do several things in a row. The dropdown keeps only
/// what it is genuinely good at: switching fast.
Future<void> showNotebookManager(BuildContext context, AppState app,
    {String? focusId}) async {
  await app.purgeExpiredTrash();
  if (!context.mounted) return;
  await showOnoteDialog<void>(
    context: context,
    builder: (_) => _NotebookManager(app: app, focusId: focusId),
  );
}

class _NotebookManager extends StatefulWidget {
  const _NotebookManager({required this.app, this.focusId});
  final AppState app;
  final String? focusId;

  @override
  State<_NotebookManager> createState() => _NotebookManagerState();
}

class _NotebookManagerState extends State<_NotebookManager> {
  AppState get app => widget.app;

  /// The notebook whose row is expanded for editing, and which action it shows.
  String? _renamingId;
  String? _confirmDeleteId;
  String? _busyId;
  late String? _highlightId = widget.focusId;

  final _renameCtl = TextEditingController();

  /// Search + sort for the active-notebook list.
  final _searchCtl = TextEditingController();
  String _query = '';
  _NbSort _sort = _NbSort.updated;

  @override
  void dispose() {
    _renameCtl.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  /// Active notebooks after the search box and the chosen sort.
  List<NotebookRef> _visibleNotebooks() {
    final q = _query.trim().toLowerCase();
    final list = [
      for (final nb in app.notebooks)
        if (q.isEmpty || nb.title.toLowerCase().contains(q)) nb
    ];
    if (_sort == _NbSort.name) {
      list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else {
      list.sort((a, b) =>
          app.notebookUpdatedAt(b.id).compareTo(app.notebookUpdatedAt(a.id)));
    }
    return list;
  }

  void _startRename(NotebookRef nb) {
    _renameCtl.text = nb.title;
    _renameCtl.selection =
        TextSelection(baseOffset: 0, extentOffset: _renameCtl.text.length);
    setState(() {
      _renamingId = nb.id;
      _confirmDeleteId = null;
    });
  }

  Future<void> _commitRename(NotebookRef nb) async {
    final v = _renameCtl.text.trim();
    setState(() => _renamingId = null);
    if (v.isEmpty || v == nb.title) return;
    await app.renameNotebook(nb.id, v);
    if (mounted) setState(() {});
  }

  Future<void> _delete(NotebookRef nb) async {
    setState(() {
      _confirmDeleteId = null;
      _busyId = nb.id;
    });
    final title = nb.title;
    final ok = await app.deleteNotebook(nb.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (!ok) {
      _toast("That's your only notebook — create another one first.");
      return;
    }
    if (context.mounted) {
      await maybeRemoveFromBackup(context, app, nb.id, title);
    }
  }

  Future<void> _duplicate(NotebookRef nb) async {
    setState(() => _busyId = nb.id);
    try {
      final copy = await app.duplicateNotebook(nb.id);
      if (mounted) {
        setState(() {
          _busyId = null;
          _highlightId = copy.id;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busyId = null);
        _toast("Couldn't duplicate that notebook: $e");
      }
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.surfaces;
    final notebooks = _visibleNotebooks();
    final trashed = app.trashedNotebooks;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
      title: _header(context, scheme, s),
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: ListView(
            children: [
              _sectionHeader('Active notebooks',
                  trailing: '${app.notebooks.length} open'),
              const SizedBox(height: 6),
              if (notebooks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: Text(
                        _query.trim().isEmpty
                            ? 'No notebooks yet.'
                            : 'No notebooks match “${_query.trim()}”.',
                        style: TextStyle(fontSize: 13, color: s.textSecondary)),
                  ),
                ),
              for (final nb in notebooks) _row(nb, scheme),
              if (trashed.isNotEmpty) ...[
                const SizedBox(height: 18),
                _sectionHeader('Recycle bin',
                    icon: Icons.delete_outline,
                    trailing: 'Deleted after ${app.recycleRetentionDays} days'),
                const SizedBox(height: 6),
                for (final nb in trashed) _trashRow(nb),
              ],
              if (_importOpen) ...[
                const SizedBox(height: 12),
                _sectionLabel('Import into a new notebook'),
                _importRow(),
              ],
              // Repeated imports of the same notebook. Shown here rather than
              // behind a button because the whole problem is that nothing ever
              // pointed them out: a real workspace was holding 586 MB, of which
              // ~380 MB was four copies of one OneNote import made while
              // getting the importer working. Each import correctly mints
              // fresh ids, so nothing can merge them automatically — only a
              // person can say they are the same thing, and only if shown.
              ..._duplicateSection(),
            ],
          ),
        ),
      ),
      // The footer owns its own padding and a divider line above it, so
      // AlertDialog's default action padding is cleared.
      actionsPadding: EdgeInsets.zero,
      // ONE Row as the single action, because `AlertDialog.actions` is an
      // OverflowBar — a `Spacer` there throws ("applying parent data"), since
      // Spacer needs a Flex parent.
      actions: [
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: s.border)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 14),
          child: Row(children: [
            // The left group scrolls horizontally rather than overflowing when
            // the dialog is narrow — the footer must never clip a button.
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Notebook'),
                    onPressed: () async {
                      // Through the shared prompt, which owns the field's
                      // controller in the dialog's own State. This used to build
                      // the field and dispose its controller in a `finally` right
                      // after the await — 150 ms before the route's exit
                      // transition had finished unmounting the field. That is what
                      // crashed the app on Enter; see [promptForText].
                      final title = await promptForText(context,
                          title: 'New notebook',
                          okLabel: 'Create',
                          hintText: 'Notebook name');
                      if (title == null || !mounted) return;
                      await app.createNotebook(title);
                      if (mounted) setState(() {});
                    },
                  ),
                  const SizedBox(width: 8),
                  // Import expands INLINE rather than opening a popup menu: a
                  // popup here would be the second kind of menu this panel exists
                  // to remove.
                  _footerButton(
                    _importOpen ? Icons.expand_less : Icons.download_outlined,
                    'Import',
                    () => setState(() => _importOpen = !_importOpen),
                  ),
                  const SizedBox(width: 8),
                  _footerButton(Icons.healing_outlined, 'Repair',
                      () => _repairWithProgress(context, app)),
                  const SizedBox(width: 8),
                  // The welcome flow is where "open the notebook that's already in
                  // my Drive" lives, and it should not be a one-shot you can never
                  // get back to — that path matters most on a machine you set up
                  // months after the first one.
                  _footerButton(Icons.explore_outlined, 'Get started',
                      () async {
                    // Root navigator's context, captured before the pop — the
                    // same trap as the import row below: `showDialog` on a route
                    // that has just been popped has no live Navigator.
                    final root =
                        Navigator.of(context, rootNavigator: true).context;
                    Navigator.pop(context);
                    await showOnboarding(root, app);
                  }),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done')),
          ]),
        ),
      ],
    );
  }

  /// A footer button — outlined and compact, to sit beside the filled
  /// "New Notebook".
  Widget _footerButton(IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
        icon: Icon(icon, size: 18),
        label: Text(label),
        onPressed: onTap,
      );

  /// The dialog's header: a gradient book tile, the title and subtitle, a
  /// search box and a sort control.
  Widget _header(BuildContext context, ColorScheme scheme, OnoteSurfaces s) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary,
                Color.lerp(scheme.primary, scheme.secondary, 0.6) ??
                    scheme.primary,
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.menu_book_rounded,
              color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Notebooks',
                  style: OnoteType.headline.copyWith(
                      color: s.textPrimary, fontWeight: FontWeight.w700)),
              Text('Organize your ideas, all in one place.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OnoteType.ui.copyWith(color: s.textSecondary)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 170,
          height: 38,
          child: TextField(
            controller: _searchCtl,
            style: const TextStyle(fontSize: 12.5),
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 16),
              prefixIconConstraints:
                  BoxConstraints(minWidth: 32, minHeight: 32),
              hintText: 'Search notebooks…',
              hintStyle: TextStyle(fontSize: 12.5),
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<_NbSort>(
          tooltip: 'Sort',
          initialValue: _sort,
          position: PopupMenuPosition.under,
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => const [
            PopupMenuItem(
                value: _NbSort.updated, child: Text('Recently updated')),
            PopupMenuItem(value: _NbSort.name, child: Text('Name (A→Z)')),
          ],
          child: Container(
            width: 40,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: s.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.tune, size: 18, color: s.textSecondary),
          ),
        ),
      ],
    );
  }

  /// A section heading with an optional leading icon and a trailing note
  /// (the count, or the recycle-bin retention).
  Widget _sectionHeader(String label, {IconData? icon, String? trailing}) {
    final s = context.surfaces;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 2),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: s.textSecondary),
            const SizedBox(width: 6),
          ],
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                  color: s.textSecondary)),
          const Spacer(),
          if (trailing != null)
            Text(trailing,
                style: TextStyle(fontSize: 11.5, color: s.textSecondary)),
        ],
      ),
    );
  }

  /// The inline import choices, shown under the list when Import is expanded.
  ///
  /// **Everything an import needs is captured BEFORE this dialog is popped.**
  /// The obvious spelling — pop, then call `importX(context, app)` — hands the
  /// import the context of a route that no longer exists, so every
  /// `context.mounted` guard inside it is false and the import silently does
  /// nothing at all. That is precisely how the `.onepkg` import stopped
  /// working: the file picker opened, the user chose their notebook, and the
  /// very next line returned.
  ///
  /// A `ScaffoldMessengerState` and the ROOT navigator's context both outlive
  /// this route, so neither can go stale under an import that takes a minute.
  Widget _importRow() {
    Widget choice(IconData icon, String label,
            Future<void> Function(ScaffoldMessengerState, BuildContext) run) =>
        Padding(
          padding: const EdgeInsets.only(right: 6, top: 6),
          child: OutlinedButton.icon(
            icon: Icon(icon, size: 16),
            label: Text(label, style: const TextStyle(fontSize: 13)),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final rootContext =
                  Navigator.of(context, rootNavigator: true).context;
              setState(() => _importOpen = false);
              // Close the panel first: the imports that still show a modal put
              // it over the shell, not over a list the user has finished with.
              Navigator.pop(context);
              await run(messenger, rootContext);
            },
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Wrap(children: [
        choice(Icons.library_books_outlined, 'OneNote notebook (.onepkg)',
            (m, _) => importOneNotePackageWithFeedback(m, app)),
        choice(Icons.upload_file_outlined, 'OneNote section (.one)',
            (m, c) => importOneNoteSectionWithFeedback(c, app, messenger: m)),
        choice(Icons.drive_folder_upload_outlined, 'Markdown folder',
            (m, _) => importMarkdownWithFeedback(m, app)),
        // The other end of "put this notebook on GitHub". It sits with the
        // imports because that is where someone looks for "I have a notebook
        // somewhere else and I want it here" — the fact that this one arrives
        // over git rather than as a file is not the user's distinction to
        // make.
        choice(Icons.cloud_download_outlined, 'From a git address',
            (m, c) => showJoinFromGitDialog(c, app, messenger: m)),
        // Restore every notebook from the central "Sync all notebooks" backup.
        choice(Icons.backup_outlined, 'From a GitHub backup',
            (m, c) => showRestoreDialog(c, app)),
      ]),
    );
  }

  bool _importOpen = false;

  /// Groups of notebooks that look like the same import repeated.
  ///
  /// Computed once per open (a container query and a directory walk each), and
  /// silent when there is nothing to say — a panel that shows an empty
  /// "Duplicates" heading to everyone teaches people to ignore the heading.
  ///
  /// Nothing is auto-selected and nothing is deleted here: the row deletes to
  /// the recycle bin through the same `deleteNotebook` path as any other, so
  /// a mistake is recoverable for the retention period.
  late final List<DuplicateGroup> _dupes = app.findDuplicateNotebooks();

  List<Widget> _duplicateSection() {
    if (_dupes.isEmpty) return const [];
    return [
      const SizedBox(height: 6),
      _sectionLabel('Possible duplicates · same title and same page count'),
      for (final g in _dupes)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${g.members.length} copies of "${g.title}" · ${g.pages} pages '
                'each · ${_bytes(g.reclaimable)} would come back',
                style: const TextStyle(fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 2),
              Text(
                // Said explicitly, because "delete the duplicates" is a
                // frightening sentence unless the safest one is named.
                'Keep the largest — an import interrupted part way through is '
                'the smaller one. Deleted copies go to the recycle bin.',
                style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: context.surfaces.textSecondary),
              ),
              const SizedBox(height: 4),
              for (final m in g.members)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Row(children: [
                    Icon(
                        m == g.members.first
                            ? Icons.star_outline
                            : Icons.content_copy_outlined,
                        size: 14,
                        color: context.surfaces.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          '${m.title} · ${_bytes(m.bytes)}'
                          '${m == g.members.first ? '  (largest — keep)' : ''}'
                          '${m.isOpen ? '  (open)' : ''}',
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (m != g.members.first && !m.isOpen)
                      TextButton(
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8)),
                        onPressed: _busyId == m.id
                            ? null
                            : () async {
                                setState(() => _busyId = m.id);
                                final title = m.title;
                                await app.deleteNotebook(m.id);
                                if (!mounted) return;
                                setState(() {
                                  _busyId = null;
                                  _dupes.remove(g);
                                });
                                if (context.mounted) {
                                  await maybeRemoveFromBackup(
                                      context, app, m.id, title);
                                }
                              },
                        child: const Text('Delete',
                            style: TextStyle(fontSize: 11)),
                      ),
                  ]),
                ),
            ],
          ),
        ),
    ];
  }

  static String _bytes(int n) {
    if (n >= 1 << 30) return '${(n / (1 << 30)).toStringAsFixed(1)} GB';
    if (n >= 1 << 20) return '${(n / (1 << 20)).toStringAsFixed(0)} MB';
    if (n >= 1 << 10) return '${(n / (1 << 10)).toStringAsFixed(0)} KB';
    return '$n B';
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: context.surfaces.textSecondary)),
      );

  Widget _row(NotebookRef nb, ColorScheme scheme) {
    final current = nb.id == app.notebookId;
    final renaming = _renamingId == nb.id;
    final confirming = _confirmDeleteId == nb.id;
    final busy = _busyId == nb.id;
    final counts = app.notebookCounts(nb.id);
    final highlight = _highlightId == nb.id;

    final s = context.surfaces;
    final updated = app.notebookUpdatedAt(nb.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        // Clicking the row opens that notebook — the switching the dropdown did.
        borderRadius: BorderRadius.circular(12),
        onTap: current || renaming || confirming
            ? null
            : () async {
                Navigator.pop(context);
                await app.selectNotebook(nb.id);
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: current
                ? scheme.primary.withValues(alpha: .06)
                : highlight
                    ? scheme.secondary.withValues(alpha: .10)
                    : s.raised.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color:
                    current ? scheme.primary.withValues(alpha: .5) : s.border,
                width: current ? 1.4 : 1),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // The book tile — primary-tinted for the open notebook.
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: current
                          ? scheme.primary.withValues(alpha: .14)
                          : s.well,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.menu_book_rounded,
                        size: 20,
                        color: current ? scheme.primary : s.textSecondary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: renaming
                        ? TextField(
                            controller: _renameCtl,
                            autofocus: true,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                                isDense: true, border: OutlineInputBorder()),
                            onSubmitted: (_) => _commitRename(nb),
                            onTapOutside: (_) => _commitRename(nb),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(nb.title,
                                        overflow: TextOverflow.ellipsis,
                                        style: OnoteType.uiStrong.copyWith(
                                            color: current
                                                ? scheme.primary
                                                : s.textPrimary,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  const SizedBox(width: 8),
                                  // Which of these is safe if this laptop dies —
                                  // answerable at a glance rather than by
                                  // opening each one in turn.
                                  SyncDot(app: app, notebookId: nb.id),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                  '${counts.sections} section${counts.sections == 1 ? '' : 's'} · '
                                  '${counts.pages} page${counts.pages == 1 ? '' : 's'}'
                                  '${current ? ' · open' : ''}',
                                  style: TextStyle(
                                      fontSize: 12, color: s.textSecondary)),
                              if (updated > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Text('Updated ${_ago(updated)}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: s.textSecondary
                                              .withValues(alpha: .8))),
                                ),
                            ],
                          ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (!renaming && !confirming) ...[
                    if (!current)
                      _act(Icons.open_in_new, 'Open this notebook', () async {
                        Navigator.pop(context);
                        await app.selectNotebook(nb.id);
                      }),
                    _act(Icons.edit_outlined, 'Rename', () => _startRename(nb)),
                    _act(Icons.copy_all_outlined, 'Duplicate',
                        () => _duplicate(nb)),
                    _act(
                        Icons.delete_outline,
                        'Move to recycle bin',
                        () => setState(() {
                              _confirmDeleteId = nb.id;
                              _renamingId = null;
                            }),
                        danger: true),
                  ],
                ],
              ),
              // Inline confirm — no second dialog, and the list stays put so you can
              // change your mind or delete another one straight after.
              if (confirming)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 28),
                  child: Row(children: [
                    const Expanded(
                      child: Text(
                          'Move to the recycle bin? You can restore it from here.',
                          style: TextStyle(fontSize: 13)),
                    ),
                    TextButton(
                        onPressed: () =>
                            setState(() => _confirmDeleteId = null),
                        child: const Text('Cancel')),
                    const SizedBox(width: 4),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: OnoteColors.danger,
                          visualDensity: VisualDensity.compact),
                      onPressed: () => _delete(nb),
                      child: const Text('Delete'),
                    ),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trashRow(NotebookRef nb) {
    final s = context.surfaces;
    final days = _daysLeft(nb.deletedAt ?? 0, app.recycleRetentionDays);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: s.raised.withValues(alpha: .25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: s.border),
        ),
        child: Row(children: [
          Icon(Icons.description_outlined, size: 20, color: s.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nb.title,
                    overflow: TextOverflow.ellipsis,
                    style: OnoteType.uiStrong.copyWith(color: s.textSecondary)),
                const SizedBox(height: 1),
                Text(days,
                    style: TextStyle(fontSize: 11, color: s.textSecondary)),
              ],
            ),
          ),
          OutlinedButton.icon(
            style:
                OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.restore, size: 16),
            label: const Text('Restore'),
            onPressed: () async {
              await app.restoreNotebook(nb.id);
              if (mounted) setState(() => _highlightId = nb.id);
            },
          ),
          const SizedBox(width: 4),
          _act(Icons.delete_forever, 'Delete permanently', () async {
            final ok = await _confirmPurge(context, nb,
                caveat: app.purgeCaveat(nb.id));
            if (!ok || !mounted) return;
            await app.purgeNotebook(nb.id);
            if (mounted) setState(() {});
          }, danger: true),
        ]),
      ),
    );
  }

  Widget _act(IconData icon, String tip, VoidCallback onTap,
          {bool danger = false}) =>
      IconButton(
        icon: Icon(icon, size: 16),
        color: danger ? OnoteColors.danger : null,
        visualDensity: VisualDensity.compact,
        tooltip: tip,
        onPressed: onTap,
      );
}

String _daysLeft(int deletedAt, int retentionDays) {
  final remaining = deletedAt +
      Duration(days: retentionDays).inMilliseconds -
      DateTime.now().millisecondsSinceEpoch;
  final days = (remaining / const Duration(days: 1).inMilliseconds).ceil();
  return days <= 0
      ? 'Deletes soon'
      : 'Deletes in $days day${days == 1 ? '' : 's'}';
}

/// How the active-notebook list is ordered.
enum _NbSort { updated, name }

/// A short "how long ago" for the "Updated …" line — "just now", "5 minutes
/// ago", "3 days ago". [ms] is epoch milliseconds; 0 means unknown.
String _ago(int ms) {
  if (ms <= 0) return 'a while ago';
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) {
    final m = d.inMinutes;
    return '$m minute${m == 1 ? '' : 's'} ago';
  }
  if (d.inHours < 24) {
    final h = d.inHours;
    return '$h hour${h == 1 ? '' : 's'} ago';
  }
  if (d.inDays < 30) {
    final n = d.inDays;
    return '$n day${n == 1 ? '' : 's'} ago';
  }
  if (d.inDays < 365) {
    final n = (d.inDays / 30).floor();
    return '$n month${n == 1 ? '' : 's'} ago';
  }
  final n = (d.inDays / 365).floor();
  return '$n year${n == 1 ? '' : 's'} ago';
}

Future<bool> _confirmPurge(BuildContext context, NotebookRef nb,
    {String? caveat}) async {
  final ok = await showOnoteDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete permanently?'),
      content: Text('“${nb.title}” and all its pages will be removed for good. '
          "This can't be undone.${caveat == null ? '' : '\n\n$caveat'}"),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: OnoteColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete forever'),
        ),
      ],
    ),
  );
  return ok == true;
}

// ── Import entry points ────────────────────────────────────────────────────
// These live here because the notebook manager is the single surface that owns
// notebook-level actions, importing included.

/// Import a `.onepkg` as a new notebook — as a background job.
///
/// This used to be a modal that owned the app for the whole import; the job
/// (see `import_job.dart`) is the same work, chunked, with a floating card
/// for progress and honesty about partial imports at the end. The completion
/// message lives on the card now, so nothing here waits for anything.
/// **Takes a messenger, not a `BuildContext`, on purpose.** The background job
/// needs no context, so there is nothing here that a dead route can stop —
/// which is the structural half of the fix for the import that silently did
/// nothing. `ScaffoldMessengerState` lives above the navigator, so it is still
/// good long after whichever dialog started the import has gone.
Future<void> importOneNotePackageWithFeedback(
    ScaffoldMessengerState messenger, AppState app,
    {Future<XFile?> Function()? pickFile}) async {
  final file = await (pickFile?.call() ??
      openFile(acceptedTypeGroups: const [
        XTypeGroup(label: 'OneNote notebook package', extensions: ['onepkg'])
      ]));
  if (file == null) return;
  try {
    final job = ImportJob.start(app, p.basename(file.name), file.path);
    _say(
        messenger,
        job == null
            ? 'An import is already running — one at a time.'
            : 'Importing in the background — keep working, the card in the '
                "corner will say when it's done.");
  } on OneNoteUnavailable {
    _say(messenger, _coreMissing, seconds: 8);
  } catch (e) {
    _say(messenger, "Couldn't read that file: $e");
  }
}

/// Import a single `.one` section into the current notebook.
///
/// Still modal: a section is small, and its parse now happens in an isolate
/// with the decode work, so the dialog is short-lived. [context] must be one
/// that outlives the caller — the root navigator's, not a dialog's — or the
/// progress dialog silently does not appear. [messenger] carries the result
/// even if that context has gone by the time the import finishes.
Future<void> importOneNoteSectionWithFeedback(
    BuildContext context, AppState app,
    {ScaffoldMessengerState? messenger}) async {
  final m = messenger ?? ScaffoldMessenger.of(context);
  try {
    final count = await importOneNoteFile(app, progressContext: context);
    if (count == null) return;
    _say(
        m,
        count == 0
            ? "Couldn't read any content from that .one file."
            : 'Imported '
                '${importArrivalNote(count, lastImportedImages, lastImportedStrokes, lastImportedTags)}'
                ' from OneNote.${_strokeNote()}');
  } on OneNoteUnavailable {
    _say(m, _coreMissing, seconds: 8);
  }
}

/// Import a folder of Markdown (Obsidian-style) as a new section.
Future<void> importMarkdownWithFeedback(
    ScaffoldMessengerState messenger, AppState app) async {
  // **It says what it is doing while it does it.** A vault of a few hundred
  // notes is seconds of work, and there was nothing on screen for any of it.
  final progress = ValueNotifier<String>('Reading the folder…');
  int? count;
  try {
    count = await importMarkdownFolder(
      app,
      onProgress: (done) => progress.value = 'Imported $done '
          'page${done == 1 ? '' : 's'}…',
    );
  } catch (e) {
    progress.dispose();
    _say(messenger, "That folder couldn't be imported: $e", seconds: 8);
    return;
  }
  progress.dispose();
  if (count == null) return;
  _say(
      messenger,
      count == 0
          ? 'No Markdown files found in that folder.'
          : 'Imported $count page${count == 1 ? '' : 's'}.');
}

/// Show a snackbar through a messenger that cannot go stale.
void _say(ScaffoldMessengerState m, String msg, {int seconds = 4}) =>
    m.showSnackBar(
        SnackBar(content: Text(msg), duration: Duration(seconds: seconds)));

const _coreMissing =
    'OneNote import needs the Rust core — build onote_core.dll '
    '(see rust/onote_core/INTEGRATION.md).';

/// One sentence when the parser dropped undecodable ink (~0.02 % of strokes on
/// the reference notebook). The notes LOOK complete when a stroke vanishes,
/// which is exactly why it has to be said out loud.
/// What arrived, in the switcher's own terms (P5).
String _strokeNote() => lastDroppedStrokes == 0
    ? ''
    : ' $lastDroppedStrokes ink stroke'
        '${lastDroppedStrokes == 1 ? '' : 's'} could not be decoded and '
        '${lastDroppedStrokes == 1 ? 'was' : 'were'} left out.';

/// "Repair" — heal every page of the open notebook at once.
///
/// The on-open repair is lazy on purpose (a clean page pays nothing), but a
/// notebook imported before the importer was fixed keeps its `﷟HYPERLINK`
/// junk and its needless `$…$` on every page you have not happened to visit.
/// This is the explicit "just fix all of it" pass, with a live count because
/// on a 300-page notebook it is seconds rather than milliseconds.
Future<void> _repairWithProgress(BuildContext context, AppState app) async {
  final progress = ValueNotifier<String>('Checking pages…');
  var open = false;
  if (context.mounted) {
    open = true;
    showOnoteDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.6)),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: progress,
              builder: (_, t, __) => Text(t),
            ),
          ),
        ]),
      ),
    );
  }
  try {
    final r = await app.repairWholeNotebook(
      onProgress: (done, total) =>
          progress.value = 'Checking page $done of $total…',
    );
    if (open && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      open = false;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Text(r.pages == 0
          ? 'Nothing to repair — every page is already up to date.'
          : 'Repaired ${r.blocks} box${r.blocks == 1 ? '' : 'es'} '
              'across ${r.pages} page${r.pages == 1 ? '' : 's'}.'),
    ));
  } catch (e) {
    if (open && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Repair failed: $e')));
    }
  } finally {
    progress.dispose();
  }
}
