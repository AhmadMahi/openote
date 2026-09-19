import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';

/// The share bucket: pick files (slides, PDFs, notebooks…) to send up alongside
/// the page. It only remembers the paths — nothing is copied or uploaded here;
/// the push (Export → "Push page + shared files") reads them and files them
/// under `assets/`. The bucket is per page.
Future<void> showBucketDialog(BuildContext context, AppState app) =>
    showOnoteDialog<void>(
      context: context,
      builder: (_) => _BucketDialog(app: app),
    );

class _BucketDialog extends StatelessWidget {
  const _BucketDialog({required this.app});
  final AppState app;

  Future<void> _add(BuildContext context) async {
    try {
      final files = await openFiles();
      if (files.isEmpty) return;
      app.addBucketFiles(files.map((f) => f.path));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text("Couldn't open the file picker: $e")));
      }
    }
  }

  IconData _iconFor(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
    if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
    if (const {'ppt', 'pptx', 'key', 'odp'}.contains(ext)) {
      return Icons.slideshow_outlined;
    }
    if (const {
      'ipynb',
      'py',
      'js',
      'ts',
      'dart',
      'java',
      'cpp',
      'c',
      'go',
      'rb'
    }.contains(ext)) {
      return Icons.code;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final files = app.bucket;
        return AlertDialog(
          title: Row(children: [
            const Icon(Icons.inventory_2_outlined, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Files to share')),
            if (files.isNotEmpty)
              Text('${files.length}',
                  style: TextStyle(fontSize: 13, color: s.textSecondary)),
          ]),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gather files to send up with this page — slides, PDFs, '
                  'notebooks. They are only remembered here; nothing uploads '
                  'until you push (Export → “Push page + shared files”), where '
                  'they are filed under assets/.',
                  style: OnoteType.ui
                      .copyWith(color: s.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 14),
                if (files.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('No files yet.',
                          style: TextStyle(color: s.textSecondary)),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: files.length,
                      itemBuilder: (context, i) {
                        final p = files[i];
                        return ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: Icon(_iconFor(p), size: 20),
                          title: Text(_basename(p),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(p,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            tooltip: 'Remove',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => app.removeBucketPath(p),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _add(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add files…'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (files.isNotEmpty)
              TextButton.icon(
                onPressed: app.clearBucket,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear'),
              ),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done')),
          ],
        );
      },
    );
  }
}
