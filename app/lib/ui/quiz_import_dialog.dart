import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../model/models.dart';
import '../quiz/quiz_import.dart';
import '../state/app_state.dart';
import 'onote_dialog.dart';

/// Insert a quiz: name it, hand out a template if wanted, upload a CSV or
/// Excel file, and drop the block on the page. The dialog does the reading and
/// validating; nothing lands on the page unless the file parsed cleanly.
Future<void> showQuizImportDialog(
    BuildContext context, AppState app, Offset at) async {
  final draft = await showOnoteDialog<_QuizDraft>(
    context: context,
    builder: (_) => const QuizImportDialog(),
  );
  if (draft == null) return;
  final b = app.addBlock(Block(
    type: BlockType.quiz,
    x: at.dx,
    y: at.dy,
    w: 420,
    content: {
      'name': draft.name,
      'questions': [for (final q in draft.questions) q.toJson()],
      'answers': List<int>.filled(draft.questions.length, -1),
      'revealed': List<bool>.filled(draft.questions.length, false),
    },
  ));
  app.select(b.id);
}

class _QuizDraft {
  const _QuizDraft(this.name, this.questions);
  final String name;
  final List<QuizQuestion> questions;
}

class QuizImportDialog extends StatefulWidget {
  const QuizImportDialog({super.key});

  @override
  State<QuizImportDialog> createState() => _QuizImportDialogState();
}

class _QuizImportDialogState extends State<QuizImportDialog> {
  final _name = TextEditingController(text: 'Quiz');
  List<QuizQuestion>? _questions;
  String? _error;
  String? _status;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [
        XTypeGroup(label: 'Quiz', extensions: ['csv', 'tsv', 'xlsx'])
      ]);
    } catch (e) {
      setState(() => _error = "Couldn't open the file picker: $e");
      return;
    }
    if (file == null) return;
    final Uint8List bytes = await file.readAsBytes();
    final res = parseQuizFile(file.name, bytes);
    if (!mounted) return;
    setState(() {
      if (res.isOk) {
        _questions = res.questions;
        _error = null;
        _status = '${res.questions.length} '
            'question${res.questions.length == 1 ? '' : 's'} loaded from '
            '${file!.name}';
        // Name the quiz after the file if it is still the placeholder.
        if (_name.text.trim().isEmpty || _name.text.trim() == 'Quiz') {
          final base = file.name.replaceAll(RegExp(r'\.[^.]+$'), '').trim();
          if (base.isNotEmpty) _name.text = base;
        }
      } else {
        _questions = null;
        _status = null;
        _error = res.error;
      }
    });
  }

  Future<void> _downloadTemplate() async {
    final loc = await getSaveLocation(
      suggestedName: 'quiz-template.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv'])
      ],
    );
    if (loc == null) return;
    try {
      await File(loc.path).writeAsString(quizTemplateCsv());
      if (mounted)
        setState(
            () => _status = 'Template saved. Fill it in, then upload it here.');
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't save the template: $e");
    }
  }

  void _create() {
    final qs = _questions;
    if (qs == null || qs.isEmpty) return;
    final name = _name.text.trim().isEmpty ? 'Quiz' : _name.text.trim();
    Navigator.of(context).pop(_QuizDraft(name, qs));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = _questions != null && _questions!.isNotEmpty;
    return AlertDialog(
      title: const Text('Create a quiz'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upload a CSV or Excel file: one row per question, with the '
              'question, four options, the correct answer (1-4, A-D or the '
              'exact text), and an optional explanation. One to 20 questions.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Quiz name',
                hintText: 'Chapter 3 review',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _downloadTemplate,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Download template'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(ready ? 'Choose another file' : 'Upload file'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 16, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(fontSize: 12.5, color: scheme.error)),
                  ),
                ],
              ),
            ],
            if (_status != null && _error == null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child:
                        Text(_status!, style: const TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: ready ? _create : null,
          child: const Text('Create quiz'),
        ),
      ],
    );
  }
}
