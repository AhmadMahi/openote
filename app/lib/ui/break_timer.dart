import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ai/ai_prompts.dart';
import '../ai/ai_provider.dart';
import '../export/markdown_export.dart';
import '../state/app_state.dart';
import 'onote_dialog.dart';

/// A teaching break: pick how long, and whether to show a message, then the
/// whole window becomes a calm full-screen countdown until the class returns.
///
/// The message is either a canned motivating line or — with an AI provider
/// connected — a short, quirky one-liner written from what the current
/// notebook is about (its persona lives in Settings as
/// [AiFeature.breakMessage]).

/// What the setup dialog collects.
enum BreakMessageMode { off, motivating, ai }

class _BreakSetup {
  const _BreakSetup(this.minutes, this.mode);
  final int minutes;
  final BreakMessageMode mode;
}

const List<String> _cannedMessages = [
  'Back soon — stretch, breathe, and recharge. ⚡',
  'Take five. Your brain files away what you just learned while you rest. 🧠',
  'Quick breather: water, a wander, and we go again. 💧',
  'Rest your eyes and roll your shoulders. See you in a moment. 🌿',
  'Step away, come back sharper. The best ideas arrive on breaks. ✨',
  'Recharging in progress… back with fresh energy soon. 🔋',
];

Future<void> showBreakTimer(BuildContext context, AppState app) async {
  final setup = await showOnoteDialog<_BreakSetup>(
    context: context,
    builder: (_) => const _BreakSetupDialog(),
  );
  if (setup == null || !context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Break',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) =>
        _BreakScreen(app: app, minutes: setup.minutes, mode: setup.mode),
    transitionBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _BreakSetupDialog extends StatefulWidget {
  const _BreakSetupDialog();
  @override
  State<_BreakSetupDialog> createState() => _BreakSetupDialogState();
}

class _BreakSetupDialogState extends State<_BreakSetupDialog> {
  int _minutes = 5;
  BreakMessageMode _mode = BreakMessageMode.motivating;
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Take a break'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How long?',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const [5, 10, 15, 20])
                  ChoiceChip(
                    label: Text('$m min'),
                    selected: _custom.text.isEmpty && _minutes == m,
                    onSelected: (_) => setState(() {
                      _minutes = m;
                      _custom.clear();
                    }),
                  ),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _custom,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Custom',
                      suffixText: 'min',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Message',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _modeTile(BreakMessageMode.motivating, 'A motivating line',
                'A friendly canned message.'),
            _modeTile(BreakMessageMode.ai, 'Quirky, from this notebook',
                'AI writes a short line about what you are teaching.'),
            _modeTile(BreakMessageMode.off, 'No message', 'Just the timer.'),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton.icon(
          icon: const Icon(Icons.timer_outlined, size: 18),
          label: const Text('Start break'),
          onPressed: () {
            final custom = int.tryParse(_custom.text.trim());
            final minutes = (custom != null && custom > 0 ? custom : _minutes)
                .clamp(1, 180);
            Navigator.pop(context, _BreakSetup(minutes, _mode));
          },
        ),
      ],
    );
  }

  Widget _modeTile(BreakMessageMode mode, String title, String subtitle) {
    final on = _mode == mode;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _mode = mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 18, color: on ? scheme.primary : null),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11.5,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakScreen extends StatefulWidget {
  const _BreakScreen(
      {required this.app, required this.minutes, required this.mode});
  final AppState app;
  final int minutes;
  final BreakMessageMode mode;

  @override
  State<_BreakScreen> createState() => _BreakScreenState();
}

class _BreakScreenState extends State<_BreakScreen> {
  late int _remaining = widget.minutes * 60;
  Timer? _timer;
  String? _message;
  bool _loadingMessage = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _prepareMessage();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remaining > 0) {
          _remaining--;
          if (_remaining == 0) _done = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _prepareMessage() async {
    switch (widget.mode) {
      case BreakMessageMode.off:
        return;
      case BreakMessageMode.motivating:
        setState(() => _message =
            _cannedMessages[math.Random().nextInt(_cannedMessages.length)]);
        return;
      case BreakMessageMode.ai:
        final client = widget.app.aiClient();
        if (client == null) {
          // No provider — fall back to a canned line rather than nothing.
          setState(() => _message =
              _cannedMessages[math.Random().nextInt(_cannedMessages.length)]);
          return;
        }
        setState(() => _loadingMessage = true);
        final context = _notebookContext();
        final res = await client.chat([
          AiMessage.system(widget.app.systemPromptFor(AiFeature.breakMessage)),
          AiMessage.user(context == null
              ? 'Write the break-time one-liner.'
              : 'The class is learning about this. Write the break-time '
                  'one-liner, tied lightly to it:\n\n$context'),
        ], temperature: 0.9);
        widget.app.addAiTokens(res.totalTokens);
        if (!mounted) return;
        setState(() {
          _loadingMessage = false;
          _message = res.ok && res.text.trim().isNotEmpty
              ? res.text.trim()
              : _cannedMessages[math.Random().nextInt(_cannedMessages.length)];
        });
    }
  }

  /// A little of the current page's text (and the notebook name) as context,
  /// capped so the request stays small. Null when there is nothing to go on.
  String? _notebookContext() {
    try {
      final app = widget.app;
      final parts = <String>[];
      final nb =
          app.notebooks.where((n) => n.id == app.notebookId).firstOrNull?.title;
      if (nb != null && nb.trim().isNotEmpty) parts.add('Notebook: $nb');
      final id = app.pageId;
      if (id != null) {
        final page = app.nodes.where((n) => n.id == id).firstOrNull;
        final md =
            pageMarkdownOf(app, page?.title ?? 'Page', app.blocks).trim();
        if (md.isNotEmpty) {
          parts.add(md.length > 1500 ? md.substring(0, 1500) : md);
        }
      }
      final joined = parts.join('\n\n').trim();
      return joined.isEmpty ? null : joined;
    } catch (_) {
      return null;
    }
  }

  String get _clock {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final total = widget.minutes * 60;
    final progress = total == 0 ? 1.0 : 1 - (_remaining / total);
    return Material(
      color: dark ? const Color(0xFF0E1116) : const Color(0xFFF6F7FB),
      child: Stack(
        children: [
          Positioned(
            top: 14,
            right: 16,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close, size: 18),
              label: Text(_done ? 'Back to the session' : 'End break'),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_done ? "Break's over" : 'On a break',
                    style: TextStyle(
                        fontSize: 15,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary)),
                const SizedBox(height: 18),
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 6,
                          backgroundColor:
                              scheme.primary.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation(
                              _done ? const Color(0xFF2E9E5B) : scheme.primary),
                        ),
                      ),
                      Text(_done ? '00:00' : _clock,
                          style: TextStyle(
                              fontSize: 52,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                              color: dark ? Colors.white : Colors.black87)),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: 420,
                  child: _loadingMessage
                      ? const Center(
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : Text(
                          _done
                              ? 'Welcome back — ready when you are.'
                              : (_message ?? ''),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 16,
                              height: 1.4,
                              color: dark ? Colors.white70 : Colors.black54)),
                ),
                if (_done) ...[
                  const SizedBox(height: 26),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Resume the session'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
