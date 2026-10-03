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

  String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toUpperCase() : '';
  }

  /// A clear tap-to-add area. Large (a friendly empty state) when the bucket
  /// is empty, compact (a slim button) once it has files.
  Widget _addZone(BuildContext context, OnoteSurfaces s,
      {required bool large}) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: OnoteRadius.lgAll,
      onTap: () => _add(context),
      child: Container(
        width: double.infinity,
        padding:
            EdgeInsets.symmetric(vertical: large ? 26 : 12, horizontal: 16),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.05),
          borderRadius: OnoteRadius.lgAll,
          border: Border.all(
              color: accent.withValues(alpha: 0.35),
              width: 1,
              strokeAlign: BorderSide.strokeAlignInside),
        ),
        child: large
            ? Column(
                children: [
                  Icon(Icons.cloud_upload_outlined, size: 30, color: accent),
                  const SizedBox(height: 10),
                  Text('Add files to share with this page',
                      style: OnoteType.ui.copyWith(
                          color: s.textPrimary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Slides, PDFs, notebooks — click to choose',
                      style: OnoteType.small.copyWith(color: s.textSecondary)),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Text('Add more files',
                      style: OnoteType.ui.copyWith(
                          color: accent, fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }

  Widget _fileCard(BuildContext context, OnoteSurfaces s, String p) {
    final ext = _ext(p);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
      decoration: BoxDecoration(
        color: s.textPrimary.withValues(alpha: 0.03),
        borderRadius: OnoteRadius.lgAll,
        border: Border.all(color: s.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: s.textSecondary.withValues(alpha: 0.10),
              borderRadius: OnoteRadius.mdAll,
            ),
            child: Icon(_iconFor(p), size: 18, color: s.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(_basename(p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: s.textPrimary)),
                  ),
                  if (ext.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: s.textSecondary.withValues(alpha: 0.12),
                        borderRadius: OnoteRadius.smAll,
                      ),
                      child: Text(ext,
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: s.textSecondary)),
                    ),
                  ],
                ]),
                const SizedBox(height: 1),
                Text(p,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: s.textSecondary)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            onPressed: () => app.removeBucketPath(p),
          ),
        ],
      ),
    );
  }

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
                  _addZone(context, s, large: true)
                else ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 290),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: files.length,
                      itemBuilder: (context, i) =>
                          _fileCard(context, s, files[i]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _addZone(context, s, large: false),
                ],
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
