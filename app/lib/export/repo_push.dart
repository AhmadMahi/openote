/// Pushing a page — and everything on it — into the notebook's push-target
/// repo, as PDFs and files.
///
/// The whole point: while teaching, one action sends the current session's
/// whiteboard to the repo the notebook is connected to — no Save-as, no
/// download, no browser. Everything for a page lands in one tidy folder,
/// `Whiteboards/<page>/`:
///
/// - `<page> - whiteboard.pdf`   the page itself
/// - `<page> - mindmap.md`       each mind map, fully expanded, as an outline
/// - `<page> - quiz.pdf`         each quiz (questions, then all answers)
/// - `<page> - <name>.pdf`       each presentation / imported PDF
/// - `assets/PDF|PPT|code|other/` the teacher's bucket of shared files
///
/// The page, quizzes and presentations go up as PDFs and each mind map as
/// Markdown; the page's own images and non-PDF blocks are not uploaded, so the
/// generated set stays clean. Separately, files the teacher gathered in the
/// bucket ride along under `assets/`, sorted by kind. It uploads through
/// GitHub's Contents API and never touches the notebook's own sync. Re-pushing
/// overwrites the same files, so a session taught twice does not pile up copies.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../mindmap/mindmap.dart';
import '../model/models.dart';
import '../quiz/quiz_import.dart';
import '../state/app_state.dart';
import '../sync/github_api.dart';
import 'mindmap_md.dart';
import 'pdf_export.dart' show buildPageRasterPdf;
import 'pdf_vector_export.dart' show buildPagePdf;
import 'quiz_pdf.dart';

/// The outcome of a push: a short summary on success, or an error to show.
class RepoPushResult {
  const RepoPushResult.ok(this.summary) : error = null;
  const RepoPushResult.fail(this.error) : summary = null;
  final String? summary;
  final String? error;
  bool get ok => error == null;
}

/// One thing to upload.
class _Upload {
  _Upload(this.path, this.bytes, this.message);
  final String path;
  final List<int> bytes;
  final String message;
}

/// Push the current page and its contents. The page, each mind map, each quiz,
/// and each presentation/PDF on it go up (page/quiz/presentation as PDF, mind
/// maps as Markdown). Any [bucketFiles] the teacher gathered ride along into
/// `assets/`, sorted by kind into `PDF/`, `PPT/`, `code/` and `other/`. Never
/// throws.
Future<RepoPushResult> pushPageToRepo(AppState app,
    {List<String> bucketFiles = const []}) async {
  final id = app.pageId;
  if (id == null) return const RepoPushResult.fail('Open a page first.');
  if (!app.connectedForPush || (app.pushRepo?.isEmpty ?? true)) {
    return const RepoPushResult.fail(
        'This notebook is not connected to a repository. Connect one in Sync.');
  }
  final api = app.githubApi();
  if (api == null) {
    return const RepoPushResult.fail('Connect a GitHub account first.');
  }
  final full = repoFullNameFromRemote(app.pushRepo!);
  if (full == null) {
    return const RepoPushResult.fail(
        "The push target is not a GitHub repository.");
  }
  final page = app.nodes.where((n) => n.id == id).firstOrNull;
  if (page == null) {
    return const RepoPushResult.fail('That page no longer exists.');
  }
  final pageTitle = page.title.trim().isNotEmpty ? page.title : 'Untitled';
  final dir = whiteboardDir(pageTitle);
  final base = whiteboardSegment(pageTitle);

  await app.flushSave();

  final uploads = <_Upload>[];

  // 1) The page itself, as a PDF (vector, with the raster fallback the exporter
  //    uses for a page the vector build cannot render).
  Uint8List pageBytes;
  try {
    pageBytes = await buildPagePdf(app, id, title: pageTitle);
  } catch (_) {
    final fb = await buildPageRasterPdf(app);
    if (fb == null) {
      return const RepoPushResult.fail('Could not build a PDF of this page.');
    }
    pageBytes = fb;
  }
  uploads.add(
      _Upload('$dir/$base - whiteboard.pdf', pageBytes, 'Slate: $pageTitle'));

  // 2) The blocks on the page, each turned into a PDF of its own. PDFs only:
  //    a mind map goes up as a Markdown outline, a quiz as a PDF; presentations
  //    and imported files ride along only when they are already PDFs. Images and
  //    other file types are deliberately skipped.
  var mind = 0, quiz = 0, doc = 0;
  for (final b in app.blocks) {
    switch (b.type) {
      case BlockType.mindmap:
        final raw = b.content['root'];
        if (raw is! Map) break;
        final root = MindNode.fromJson(raw.cast<String, dynamic>());
        // A structured, fully-expanded Markdown outline rather than a PDF —
        // it reads far better on GitHub than the outline rendered to a page.
        final bytes =
            Uint8List.fromList(utf8.encode(mindmapToMarkdown(pageTitle, root)));
        mind++;
        final s = mind == 1 ? 'mindmap' : 'mindmap-$mind';
        uploads.add(
            _Upload('$dir/$base - $s.md', bytes, 'Slate: $pageTitle mind map'));
      case BlockType.quiz:
        final qs = <QuizQuestion>[
          for (final q in (b.content['questions'] as List? ?? const []))
            if (q is Map) QuizQuestion.fromJson(q.cast<String, dynamic>())
        ];
        if (qs.isEmpty) break;
        final bytes =
            await buildQuizPdf(b.content['name'] as String? ?? 'Quiz', qs);
        quiz++;
        final s = quiz == 1 ? 'quiz' : 'quiz-$quiz';
        uploads.add(
            _Upload('$dir/$base - $s.pdf', bytes, 'Slate: $pageTitle quiz'));
      case BlockType.presentation:
        // A presentation is stored as a PDF blob.
        final bytes = _blobOf(app, b.content['pdf']);
        if (bytes == null) break;
        final label = _stripExt((b.content['name'] as String?)?.trim());
        doc++;
        final safe =
            whiteboardSegment(label.isEmpty ? 'presentation-$doc' : label);
        uploads.add(_Upload(
            '$dir/$base - $safe.pdf', bytes, 'Slate: $pageTitle presentation'));
      case BlockType.file:
        // Only PDFs ride along; other file types are skipped.
        if (!_isPdf(b.content)) break;
        final bytes = _blobOf(app, b.content['blob']);
        if (bytes == null) break;
        final label = _stripExt((b.content['name'] as String?)?.trim());
        doc++;
        final safe = whiteboardSegment(label.isEmpty ? 'document-$doc' : label);
        uploads.add(
            _Upload('$dir/$base - $safe.pdf', bytes, 'Slate: $pageTitle file'));
      default:
        break;
    }
  }

  // 2b) The shared files the teacher gathered in the bucket, read from disk and
  //     filed under assets/<KIND>/. Only the paths were held until now; a file
  //     that has since moved or been deleted is skipped, not fatal.
  for (final path in bucketFiles) {
    try {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = await file.readAsBytes();
      final name = path.split(Platform.pathSeparator).last;
      final sub = assetSubfolderFor(name);
      uploads.add(_Upload(
          '$dir/assets/$sub/$name', bytes, 'Slate: $pageTitle shared file'));
    } catch (_) {
      // unreadable file — skip it, keep the rest
    }
  }

  // 3) Upload them all. One failure does not abort the rest; the summary says
  //    what happened.
  final failures = <String>[];
  for (final u in uploads) {
    final err = await api.putFile(full, u.path, u.bytes, u.message);
    if (err != null) failures.add(err);
  }
  final n = uploads.length - failures.length;
  if (failures.isNotEmpty) {
    return RepoPushResult.fail(
        '$n of ${uploads.length} pushed. ${failures.first}');
  }
  return RepoPushResult.ok('$dir ($n file${n == 1 ? '' : 's'})');
}

/// Which `assets/` subfolder a shared file belongs in, by its extension.
String assetSubfolderFor(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  if (ext == 'pdf') return 'PDF';
  if (const {'ppt', 'pptx', 'key', 'odp'}.contains(ext)) return 'PPT';
  if (const {
    'ipynb', 'py', 'js', 'ts', 'dart', 'java', 'cpp', 'cc', 'c', 'h', 'go',
    'rb', 'rs', 'sh', 'sql', 'json', 'yaml', 'yml', 'html', 'css', 'r', 'swift',
    'kt', 'php', 'scala', 'jl' //
  }.contains(ext)) {
    return 'code';
  }
  return 'other';
}

/// Bytes of a `sha256:…` blob reference, or null.
Uint8List? _blobOf(AppState app, Object? ref) {
  if (ref is! String || ref.isEmpty) return null;
  final hash = ref.replaceFirst('sha256:', '');
  return app.blob(hash);
}

String _stripExt(String? name) {
  if (name == null || name.isEmpty) return '';
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// Whether a file block holds a PDF (by mime or by name), so only PDFs push.
bool _isPdf(Map<String, dynamic> content) {
  final mime = (content['mime'] as String? ?? '').toLowerCase();
  if (mime == 'application/pdf') return true;
  final name = (content['name'] as String? ?? '').toLowerCase();
  return name.endsWith('.pdf');
}
