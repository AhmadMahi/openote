import 'package:flutter/material.dart';

import '../canvas/paper.dart';
import '../core/platform_open.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../update/app_update.dart';
import 'mcp_dialog.dart';
import 'color_picker.dart' show ShortcutField;
import 'onote_dialog.dart';
import 'shortcut_overlay.dart';
import 'sync_dialog.dart';
import 'update_dialog.dart';

/// The centralised settings page (PLANNING "Consistency/UX"): one place
/// holding every app-wide preference and door — previously each lived only
/// wherever its feature happened to put a control. The per-feature controls
/// stay where they are (a toggle you use while drawing belongs in Draw);
/// this page is where you LOOK for one you can't find.
Future<void> showSettingsDialog(BuildContext context, AppState app) {
  return showOnoteDialog<void>(
    context: context,
    builder: (_) => _SettingsDialog(app: app),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.app});
  final AppState app;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  AppState get app => widget.app;

  bool _checking = false;
  String? _updateNote;

  Future<void> _checkNow() async {
    setState(() {
      _checking = true;
      _updateNote = null;
    });
    await app.checkForAppUpdate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _updateNote = app.updateAvailable == null
          ? "You're up to date ($kAppVersion is the newest version)."
          : null;
    });
    if (app.updateAvailable != null && mounted) {
      await showUpdateDialog(context, app);
    }
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(title,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary)),
      );

  /// A preference whose control is too wide to sit beside its label.
  ///
  /// The cursor picker has four segments and overflowed the row by 32px — a
  /// real layout assertion, not a cosmetic squeeze. Stacking keeps the
  /// dialog's one visual language (a highlighted segment says what is set)
  /// instead of dropping to a second one for the sake of width.
  Widget _rowStacked(String label, Widget control) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            SizedBox(width: double.infinity, child: control),
          ],
        ),
      );

  /// Label left, control right — and stacked instead when the dialog is
  /// squeezed (a very narrow window), so a wide control never overflows.
  Widget _row(String label, Widget control) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: LayoutBuilder(
          builder: (context, c) => c.maxWidth < 380
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    Align(alignment: Alignment.centerLeft, child: control),
                  ],
                )
              : Row(children: [
                  Expanded(
                      child: Text(label, style: const TextStyle(fontSize: 13))),
                  control,
                ]),
        ),
      );

  /// An on/off preference, shown the same way as the Theme row above it — a
  /// highlighted segment, not a switch. One visual language for "this is
  /// currently set to X" throughout the dialog, not two.
  Widget _toggle(bool value, ValueChanged<bool> onChanged) =>
      SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11))),
        segments: const [
          ButtonSegment(value: false, label: Text('Off')),
          ButtonSegment(value: true, label: Text('On')),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );

  /// A short list of named choices, as a dense dropdown.
  Widget _pick(String value, Map<String, String> options,
          ValueChanged<String> onChanged) =>
      DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.containsKey(value) ? value : options.keys.first,
          isDense: true,
          style: TextStyle(
              fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
          items: [
            for (final e in options.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      );

  Widget _door(IconData icon, String label, String hint, VoidCallback open) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              Text(hint,
                  style: const TextStyle(
                      fontSize: 11, color: OnoteColors.graphite400)),
            ]),
          ),
          TextButton.icon(
            icon: Icon(icon, size: 15),
            label: const Text('Open…', style: TextStyle(fontSize: 12)),
            onPressed: open,
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => AlertDialog(
        title: const Text('Settings'),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: [
              _section('Appearance'),
              _row(
                'Theme',
                SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle:
                          WidgetStatePropertyAll(TextStyle(fontSize: 11))),
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.system, label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {app.themeMode},
                  onSelectionChanged: (s) => app.setThemeMode(s.first),
                ),
              ),
              // Seven accents, as dots of the colour itself — the one thing a
              // label could not say better. The chrome takes a wash of the
              // choice, so this is the app's theme, not only its buttons.
              _rowStacked(
                'Accent',
                Wrap(
                  spacing: 8,
                  children: [
                    for (final a in OnoteAccent.values)
                      Tooltip(
                        message: a.label,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(99),
                          onTap: () => app.setAccent(a),
                          child: Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: a.color(Theme.of(context).brightness ==
                                  Brightness.dark),
                              border: a == app.accent
                                  ? Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                      width: 2)
                                  : null,
                            ),
                            child: a == app.accent
                                ? const Icon(Icons.check,
                                    size: 14, color: Colors.white)
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _section('Writing and drawing'),
              // The drawing cursor. A preference rather than a decision the
              // app makes, because the right answer depends on how somebody
              // works: a nib shows what you are holding, a crosshair is what
              // people arriving from image editors expect, and a dot gets out
              // of the way on a busy diagram.
              _rowStacked(
                'Drawing cursor',
                SegmentedButton<PenCursorStyle>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle:
                          WidgetStatePropertyAll(TextStyle(fontSize: 11))),
                  segments: [
                    for (final v in PenCursorStyle.values)
                      ButtonSegment(
                          value: v, label: Text(v.label), tooltip: v.describe),
                  ],
                  selected: {app.penCursorStyle},
                  onSelectionChanged: (s) => app.setPenCursorStyle(s.first),
                ),
              ),
              // ONE colour shortcut, and it is here rather than hidden on a
              // swatch's context menu — a key you can rebind should be
              // findable in the place people look for keys.
              _rowStacked(
                'Next ink colour',
                Align(
                  alignment: Alignment.centerLeft,
                  child: ShortcutField(
                    value: app.cycleColorKey,
                    onChanged: app.setCycleColorKey,
                  ),
                ),
              ),
              _row('Spell check',
                  _toggle(app.spellCheckEnabled, app.setSpellCheck)),
              _row('Pen near the page switches to inking',
                  _toggle(app.penProximitySwitch, app.setPenProximitySwitch)),
              // What a page is born with. Each is settable per page on the
              // View tab; this is the starting point, and a page never moved
              // from it is exactly what every earlier build made.
              _section('New pages'),
              _rowStacked(
                'Background',
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle:
                          WidgetStatePropertyAll(TextStyle(fontSize: 11))),
                  segments: const [
                    ButtonSegment(value: 'blank', label: Text('Blank')),
                    ButtonSegment(value: 'grid', label: Text('Grid')),
                    ButtonSegment(value: 'dotted', label: Text('Dots')),
                    ButtonSegment(value: 'ruled', label: Text('Ruled')),
                  ],
                  selected: {app.defaultBackground},
                  onSelectionChanged: (s) => app.setDefaultBackground(s.first),
                ),
              ),
              // Stacked, not beside its label: a slider wants the width, and
              // a narrow window (or a folded test at 300px) must not overflow.
              _rowStacked(
                'Pattern spacing',
                SizedBox(
                  width: double.infinity,
                  child: Row(children: [
                    Expanded(
                      child: Slider(
                        value: app.defaultBgSpacing,
                        min: PageProps.minBgSpacing,
                        max: PageProps.maxBgSpacing,
                        divisions: 28,
                        onChanged: app.setDefaultBgSpacing,
                      ),
                    ),
                    SizedBox(
                      width: 30,
                      child: Text('${app.defaultBgSpacing.round()}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ]),
                ),
              ),
              _row(
                'Paper',
                _pick(
                    app.defaultPaper,
                    {
                      for (final p in kPapers.where((p) => p != 'image'))
                        p: paperLabel(p)
                    },
                    app.setDefaultPaper),
              ),
              _row(
                'Page size',
                _pick(
                    app.defaultPageSize,
                    {
                      'canvas': 'Canvas (boundless)',
                      for (final p in PaperSize.all) p.name: p.name,
                    },
                    app.setDefaultPageSize),
              ),
              _section('Connections'),
              _door(
                  Icons.sync,
                  'Sync',
                  'Back up and share this notebook — GitHub or a folder.',
                  () => showSyncDialog(context, app)),
              _door(
                  Icons.smart_toy_outlined,
                  'AI access',
                  app.mcpEnabled
                      ? 'On — AI helpers on this computer can use your notes.'
                      : 'Off — connect Claude or other AI helpers.',
                  () => showMcpDialog(context, app)),
              _section('Keyboard'),
              _door(
                  Icons.keyboard_outlined,
                  'Keyboard shortcuts',
                  'Everything has a key — the full list.  (Ctrl+/)',
                  () => showShortcutOverlay(context)),
              _section('About'),
              _row(
                'Slate $kAppVersion',
                _checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(
                        onPressed: _checkNow,
                        child: const Text('Check for updates',
                            style: TextStyle(fontSize: 12)),
                      ),
              ),
              // The release notice, moved here from the toolbar: it leads
              // with the version so the row answers "to what?" before the
              // click, and the button opens the same dialog it always did.
              if (app.updateAvailable != null)
                _row(
                  'Version ${app.updateAvailable!.version} is available',
                  TextButton(
                    onPressed: () => showUpdateDialog(context, app),
                    child:
                        const Text('Update…', style: TextStyle(fontSize: 12)),
                  ),
                ),
              if (_updateNote != null)
                Text(_updateNote!,
                    style: const TextStyle(
                        fontSize: 11.5, color: OnoteColors.graphite400)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => PlatformOpen.url(
                      'https://github.com/icmric/openote/releases'),
                  child:
                      const Text("What's new", style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }
}
