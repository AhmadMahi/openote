import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../math/graph_plot.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import 'md_common.dart';
import 'pdf_vector_export.dart' show buildPagePdf;

/// Open-format exporters (OPEN-5/6/7): the "glass box" promise made real.
///
/// * [materializeNotebook] writes the whole notebook as a plain folder tree of
///   open files (File Format Spec §8): a top-level `notebook.json` structure
///   tree, one folder per page under `pages/` (nested to mirror the section
///   hierarchy), each page carried by a fidelity `page.json` (the mirror), a
///   convenience `page.md`, a JSON Canvas `canvas.json`, a `page.inkml` when the
///   page has ink, and a single top-level `assets/` of content-addressed blobs
///   (shared across pages, so an image used twice is stored once). Nothing here
///   needs Openote to read.
/// * [exportPageJsonCanvas] exports the current page as a single
///   [JSON Canvas](https://jsoncanvas.org) file (Obsidian-compatible).
/// * [exportPageInkML] exports the current page's ink as W3C InkML.
///
/// Freeform layout flattens to reading order (top→bottom, then left→right) for
/// the Markdown projection; the JSON keeps exact coordinates (File Format Spec
/// §8: page.json is the fidelity path, page.md the convenience one).

// ── Whole-notebook materialize (OPEN-6) ───────────────────────────────────

/// Export every page of the current notebook into [rootDir]/<notebook>/…, one
/// folder per section and page. Returns the created root folder path, or null
/// if the user cancelled the folder picker.
/// [onProgress] is called with (page number, total) as each page is written,
/// so the caller can put something on screen. This walks every page in the
/// notebook and writes a folder for each: seconds of work on a term of notes,
/// and there used to be nothing at all to say so.
Future<String?> materializeNotebook(AppState app,
    {void Function(int done, int total)? onProgress}) async {
  if (app.notebookId == null) return null;
  await app.flushSave(); // include the open page's latest edits

  final dir = await getDirectoryPath(confirmButtonText: 'Export here');
  if (dir == null) return null;

  final nb = app.notebooks.firstWhere((n) => n.id == app.notebookId);
  final root = _uniqueDir(dir, safeFilename(nb.title));
  await materializeNotebookInto(app, app.notebookId!, root,
      onProgress: onProgress);
  return root;
}

/// Materialize ONE notebook (open or not) into [root], writing the same clean
/// folder tree as [materializeNotebook] but for an arbitrary notebook id and a
/// caller-chosen directory. Reads through the notebook-scoped accessors
/// ([AppState.nodesOf], [AppState.readPageOf], [AppState.blobOf]) so it never
/// has to make the notebook the open one — which is what lets the central
/// backup mirror every notebook without disturbing what the user is looking at.
///
/// The caller owns [root]: pass a fresh (or freshly cleaned) directory when a
/// clean snapshot is wanted — or pass [incremental] to keep [root] up to date
/// in place.
///
/// [withPagePdf] also writes a `<page>.pdf` beside each page's other files —
/// the same PDF the Export menu makes. It reads the OPEN page/notebook, so the
/// caller must only set it when [nbId] is the open notebook (the central backup
/// does this only for the notebook currently in view).
///
/// **[incremental]: cost what changed, not what exists.** The central backup
/// used to wipe each notebook's folder and rebuild all of it — read and decode
/// every page, pretty-print every stroke as JSON and again as InkML, render a
/// PDF of every page of the open notebook, rewrite every picture — every five
/// minutes for every notebook, on the UI thread. That was the periodic hang.
/// With [incremental], a page whose write counter
/// ([AppState.pageRevisionsOf]) and folder are what they were last time keeps
/// its files untouched; a picture already on disk at the right length is not
/// read or rewritten; a notebook where nothing moved returns before touching
/// the disk at all; and what an earlier run wrote that is no longer wanted is
/// removed instead of wiping the folder first. Untouched files keep their
/// timestamps, so git does not re-read them either. The state is updated in
/// place only once the run completes.
///
/// [breathe] is awaited before each page that has to be rebuilt and each
/// picture that has to be read, so a caller can let frames through and wait
/// for the user to pause.
///
/// Returns whether anything on disk changed (always true without
/// [incremental]).
Future<bool> materializeNotebookInto(AppState app, String nbId, String root,
    {void Function(int done, int total)? onProgress,
    bool withPagePdf = false,
    MaterializedNotebook? incremental,
    Future<void> Function()? breathe}) async {
  final nb = app.notebooks.firstWhere((n) => n.id == nbId);
  final assetsDir = p.join(root, 'assets');

  final nbNodes = app.nodesOf(nbId);
  final byId = {for (final n in nbNodes) n.id: n};
  final pageNodes = nbNodes.where((n) => n.kind == NodeKind.page).toList();

  // Which pages changed, without reading any of them. Null means unknown,
  // and unknown never counts as unchanged.
  final revs = incremental == null ? null : app.pageRevisionsOf(nbId);
  int revOf(String id) => revs?[id] ?? 0;
  final structure = [
    nb.title,
    for (final n in nbNodes)
      '${n.id}|${n.parentId}|${n.kind.name}|${n.title}|${n.position}|'
          '${n.color}|${n.level}|${n.createdAt}|${n.updatedAt}',
  ].join('\n');

  // Nothing about this notebook moved since the last run: no disk at all.
  if (incremental != null &&
      revs != null &&
      incremental.structure == structure &&
      incremental.pages.length == pageNodes.length &&
      await Directory(root).exists()) {
    var same = true;
    for (final node in pageNodes) {
      final prev = incremental.pages[node.id];
      if (prev == null ||
          prev.rev != revOf(node.id) ||
          (withPagePdf && !prev.pdf)) {
        same = false;
        break;
      }
    }
    if (same) return false;
  }

  await Directory(root).create(recursive: true);
  final manifestPages = <Map<String, dynamic>>[];
  final usedDirs = <String>{};
  // hash → "hash.ext"; collected across ALL pages then written once (dedup).
  final sharedAssets = <String, String>{};
  // What this run wrote or deliberately kept; everything else under [root]
  // is left over from an earlier run (incremental cleanup only).
  final keepFiles = <String>{};
  final keptPageDirs = <String>{};
  final nextPages = <String, MaterializedPage>{};
  var changed = incremental == null;

  var pagesDone = 0;
  for (final node in pageNodes) {
    onProgress?.call(++pagesDone, pageNodes.length);
    // Page folder = sanitized titles of every ancestor + this page (+ an id
    // suffix to guarantee uniqueness), so the section/group/subpage hierarchy
    // is mirrored as nested folders under pages/.
    final segments = <String>[];
    TreeNode? cur = node;
    while (cur != null) {
      segments.insert(0, safeFilename(cur.title));
      cur = cur.parentId == null ? null : byId[cur.parentId];
    }
    var rel = p.joinAll(segments);
    // De-collide sibling pages that sanitize to the same name.
    var candidate = rel;
    var i = 2;
    while (usedDirs.contains(candidate.toLowerCase())) {
      candidate = '$rel-$i';
      i++;
    }
    usedDirs.add(candidate.toLowerCase());
    rel = candidate;
    final relPosix = rel.replaceAll('\\', '/');

    final pageDir = p.join(root, 'pages', rel);
    keptPageDirs.add(pageDir);
    manifestPages.add({
      'id': node.id,
      'title': node.title,
      'path': 'pages/$relPosix',
      'level': node.level,
    });

    // Unchanged since it was last written: its files stay exactly as they are.
    final prev = incremental?.pages[node.id];
    final rev = revOf(node.id);
    if (revs != null &&
        prev != null &&
        prev.rev == rev &&
        prev.rel == relPosix &&
        await File(p.join(pageDir, 'page.json')).exists()) {
      sharedAssets.addAll(prev.assets);
      var keptFiles = prev.files;
      var hasPdf = prev.pdf;
      if (withPagePdf && !hasPdf) {
        // Last written while its notebook was closed: only the PDF is owed.
        await breathe?.call();
        final pdfName = await _writePagePdf(app, node, pageDir);
        if (pdfName != null) {
          keptFiles = [...keptFiles.where((f) => f != pdfName), pdfName];
          hasPdf = true;
          changed = true;
        }
      }
      for (final f in keptFiles) {
        keepFiles.add(p.join(pageDir, f));
      }
      nextPages[node.id] = MaterializedPage(
          rev: rev,
          rel: relPosix,
          files: keptFiles,
          assets: prev.assets,
          pdf: hasPdf);
      continue;
    }

    await breathe?.call();
    changed = true;
    await Directory(pageDir).create(recursive: true);
    // Relative path from this page's folder back to the shared assets/ dir,
    // in POSIX form so the Markdown/canvas links are portable.
    final assetPrefix =
        p.relative(assetsDir, from: pageDir).replaceAll('\\', '/');

    final data = app.readPageOf(nbId, node.id);
    final blocks = data.blocks;
    final files = <String>[];
    final pageAssets = <String, String>{};

    // 1) Fidelity mirror.
    await File(p.join(pageDir, 'page.json')).writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert(_mirrorMap(node.id, data.props, blocks)));
    files.add('page.json');

    // 2) Convenience Markdown + collected image assets.
    final md = _pageMarkdown(node.title, blocks, assetPrefix);
    await File(p.join(pageDir, 'page.md')).writeAsString(md.text);
    files.add('page.md');
    pageAssets.addAll(md.assets);

    // Also carry the bytes of presentations and imported files, keyed by hash,
    // so a restore can rebuild them (page.json already holds the block that
    // references them). Videos are deliberately left out — too large for a
    // notes backup. Images are already collected by the Markdown projection.
    for (final b in blocks) {
      if (b.type == BlockType.presentation) {
        final h =
            (b.content['pdf'] as String? ?? '').replaceFirst('sha256:', '');
        if (h.isNotEmpty) pageAssets[h] = '$h.pdf';
      } else if (b.type == BlockType.file) {
        final h =
            (b.content['blob'] as String? ?? '').replaceFirst('sha256:', '');
        if (h.isNotEmpty) {
          final name = b.content['name'] as String? ?? '';
          final dot = name.lastIndexOf('.');
          pageAssets[h] = dot > 0 ? '$h${name.substring(dot)}' : '$h.bin';
        }
      }
    }

    // 3) JSON Canvas.
    await File(p.join(pageDir, 'canvas.json')).writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert(_jsonCanvas(blocks, assetPrefix)));
    files.add('canvas.json');

    // 4) InkML when there's ink.
    final inkml = _inkML(blocks);
    if (inkml != null) {
      await File(p.join(pageDir, 'page.inkml')).writeAsString(inkml);
      files.add('page.inkml');
    }

    // 5) A PDF of the page — the readable artefact the owner wants in the
    // backup beside the open-format files. Only for the open notebook (the PDF
    // builder reads the open page); a page that cannot render just has none.
    var pdf = false;
    if (withPagePdf) {
      final name = await _writePagePdf(app, node, pageDir);
      if (name != null) {
        files.add(name);
        pdf = true;
      }
    }

    sharedAssets.addAll(pageAssets);
    for (final f in files) {
      keepFiles.add(p.join(pageDir, f));
    }
    nextPages[node.id] = MaterializedPage(
        rev: rev, rel: relPosix, files: files, assets: pageAssets, pdf: pdf);
  }

  // Write the shared, content-addressed asset store once.
  final nextAssets = <String, int>{};
  if (sharedAssets.isNotEmpty) {
    await Directory(assetsDir).create(recursive: true);
    for (final e in sharedAssets.entries) {
      final f = File(p.join(assetsDir, e.value));
      // Named by its content hash: a file of the right name and length that
      // this backup wrote is already these bytes, so it is not read again.
      final known = incremental?.assets[e.value];
      if (known != null && await f.exists() && await f.length() == known) {
        nextAssets[e.value] = known;
        keepFiles.add(f.path);
        continue;
      }
      await breathe?.call();
      final bytes = app.blobOf(nbId, e.key);
      if (bytes == null) {
        // The bytes are not on this computer (yet). Keep whatever an earlier
        // run wrote rather than deleting a picture from the backup that this
        // run cannot reproduce.
        if (await f.exists()) keepFiles.add(f.path);
        continue;
      }
      keepFiles.add(f.path);
      if (incremental != null &&
          await f.exists() &&
          await f.length() == bytes.length) {
        nextAssets[e.value] = bytes.length;
        continue;
      }
      await f.writeAsBytes(bytes);
      nextAssets[e.value] = bytes.length;
      changed = true;
    }
  }

  // notebook.json: the full structure tree (groups/sections/pages, order,
  // colours, timestamps) — the spec's §8 top-level structure file.
  final notebookInfo = {'id': nb.id, 'title': nb.title};
  final nodesJson = [
    for (final n in nbNodes)
      {
        'id': n.id,
        'kind': switch (n.kind) {
          NodeKind.sectionGroup => 'section_group',
          NodeKind.section => 'section',
          NodeKind.page => 'page',
        },
        'parentId': n.parentId,
        'title': n.title,
        'position': n.position,
        if (n.color != null) 'color': n.color,
        'level': n.level,
        'createdAt': n.createdAt,
        'updatedAt': n.updatedAt,
      }
  ];
  final nbFile = File(p.join(root, 'notebook.json'));
  keepFiles.add(nbFile.path);
  var writeNotebookJson = true;
  if (incremental != null && await nbFile.exists()) {
    // Rewritten only when the structure changed. `exportedAt` alone changing
    // used to make every sweep a commit — thousands of them.
    try {
      final old = jsonDecode(await nbFile.readAsString());
      if (old is Map) {
        old.remove('exportedAt');
        writeNotebookJson = jsonEncode(old) !=
            jsonEncode({
              'format': 'openote-materialized/1',
              'notebook': notebookInfo,
              'nodes': nodesJson,
              'pages': manifestPages,
            });
      }
    } catch (_) {}
  }
  if (writeNotebookJson) {
    await nbFile.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'format': 'openote-materialized/1',
      'notebook': notebookInfo,
      'exportedAt': DateTime.now().toIso8601String(),
      'nodes': nodesJson,
      'pages': manifestPages,
    }));
    changed = true;
  }

  if (incremental != null) {
    if (await _removeStale(root, keepFiles, keptPageDirs,
        keepOldPdfs: !withPagePdf)) {
      changed = true;
    }
    incremental
      ..structure = structure
      ..pages = nextPages
      ..assets = nextAssets;
  }
  return changed;
}

/// Write [node]'s page as a PDF into [pageDir]. Returns the file name, or null
/// when the page cannot render (a page that cannot render just has none).
Future<String?> _writePagePdf(
    AppState app, TreeNode node, String pageDir) async {
  try {
    final pdf = await buildPagePdf(app, node.id, title: node.title);
    final name = '${safeFilename(node.title)}.pdf';
    await File(p.join(pageDir, name)).writeAsBytes(pdf);
    return name;
  } catch (_) {
    return null;
  }
}

/// Delete what an earlier run wrote under [root] that this run did not keep —
/// pages that were deleted or moved, pictures nothing references any more —
/// then any folder left empty. A closed notebook's old page PDFs stay when
/// [keepOldPdfs]: it cannot rebuild them, and a stale PDF beats none.
Future<bool> _removeStale(String root, Set<String> keep, Set<String> pageDirs,
    {required bool keepOldPdfs}) async {
  var removed = false;
  final dirs = <String>[];
  await for (final e
      in Directory(root).list(recursive: true, followLinks: false)) {
    if (e is Directory) {
      dirs.add(e.path);
      continue;
    }
    if (keep.contains(e.path)) continue;
    if (keepOldPdfs &&
        e.path.toLowerCase().endsWith('.pdf') &&
        pageDirs.contains(p.dirname(e.path))) {
      continue;
    }
    try {
      await e.delete();
      removed = true;
    } catch (_) {}
  }
  // Deepest first, so a parent empties out after its children.
  dirs.sort((a, b) => b.length.compareTo(a.length));
  for (final d in dirs) {
    try {
      final dir = Directory(d);
      if (await dir.list().isEmpty) {
        await dir.delete();
        removed = true;
      }
    } catch (_) {}
  }
  return removed;
}

/// What an incremental [materializeNotebookInto] remembers about one notebook
/// between runs, so the next run can leave unchanged pages exactly as they are.
///
/// Only meaningful for the folder it was produced against: the central backup
/// keeps it inside its own clone, and it is thrown away with the clone.
class MaterializedNotebook {
  MaterializedNotebook();

  /// The notebook's tree (ids, titles, order, timestamps) as last written.
  String structure = '';

  /// Page id → what was written for it.
  Map<String, MaterializedPage> pages = {};

  /// Asset file name → its length when written.
  Map<String, int> assets = {};

  factory MaterializedNotebook.fromJson(Map<String, dynamic> j) {
    final n = MaterializedNotebook()
      ..structure = j['structure'] as String? ?? '';
    final pages = j['pages'];
    if (pages is Map) {
      pages.forEach((k, v) {
        if (k is String && v is Map) {
          n.pages[k] = MaterializedPage.fromJson(v.cast<String, dynamic>());
        }
      });
    }
    final assets = j['assets'];
    if (assets is Map) {
      assets.forEach((k, v) {
        if (k is String && v is num) n.assets[k] = v.toInt();
      });
    }
    return n;
  }

  Map<String, dynamic> toJson() => {
        'structure': structure,
        'pages': {for (final e in pages.entries) e.key: e.value.toJson()},
        'assets': assets,
      };
}

/// One page's share of a [MaterializedNotebook].
class MaterializedPage {
  MaterializedPage({
    required this.rev,
    required this.rel,
    required this.files,
    required this.assets,
    required this.pdf,
  });

  /// The page's write counter when its files were written.
  final int rev;

  /// Its folder under `pages/`, POSIX separators.
  final String rel;

  /// The file names written in that folder.
  final List<String> files;

  /// Hash → asset file name, for every picture or file the page references.
  final Map<String, String> assets;

  /// Whether a PDF was written for this revision.
  final bool pdf;

  factory MaterializedPage.fromJson(Map<String, dynamic> j) => MaterializedPage(
        rev: (j['rev'] as num?)?.toInt() ?? -1,
        rel: j['rel'] as String? ?? '',
        files: [
          for (final f in (j['files'] as List? ?? const []))
            if (f is String) f
        ],
        assets: {
          for (final e in ((j['assets'] as Map?) ?? const {}).entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String
        },
        pdf: j['pdf'] == true,
      );

  Map<String, dynamic> toJson() =>
      {'rev': rev, 'rel': rel, 'files': files, 'assets': assets, 'pdf': pdf};
}

// ── Single-page JSON Canvas (OPEN-6) ──────────────────────────────────────

Future<String?> exportPageJsonCanvas(AppState app) async {
  if (app.pageId == null) return null;
  await app.flushSave();
  final page = app.nodes.firstWhere((n) => n.id == app.pageId);
  final location = await getSaveLocation(
    suggestedName: '${safeFilename(page.title)}.canvas',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON Canvas', extensions: ['canvas'])
    ],
  );
  if (location == null) return null;
  await File(location.path).writeAsString(const JsonEncoder.withIndent('  ')
      .convert(_jsonCanvas(app.blocks, 'assets')));
  return location.path;
}

// ── Single-page InkML (OPEN-7) ────────────────────────────────────────────

Future<String?> exportPageInkML(AppState app) async {
  if (app.pageId == null) return null;
  await app.flushSave();
  final inkml = _inkML(app.blocks);
  final page = app.nodes.firstWhere((n) => n.id == app.pageId);
  final location = await getSaveLocation(
    suggestedName: '${safeFilename(page.title)}.inkml',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'InkML', extensions: ['inkml', 'xml'])
    ],
  );
  if (location == null) return null;
  await File(location.path).writeAsString(inkml ?? _emptyInkML());
  return location.path;
}

// ── Builders (pure; unit-testable) ────────────────────────────────────────

Map<String, dynamic> _mirrorMap(
        String pageId, PageProps props, List<Block> blocks) =>
    {
      'schema': 'onote-page/1',
      'pageId': pageId,
      'page': props.toJson(),
      'blocks': [for (final b in blocks) b.toJson()],
    };

class _Markdown {
  _Markdown(this.text, this.assets);
  final String text;
  final Map<String, String> assets; // hash -> relative asset path
}

/// [_pageMarkdown]'s text alone, for tests — this open-format projection is
/// built separately from `markdown_export.dart`'s `pageMarkdownOf` (the file
/// exporter's own, differently-worded one), so covering one does not cover
/// the other; a block silently falling through this switch is exactly how
/// `board` once went missing from a whole release of exports.
@visibleForTesting
String openPageMarkdownOf(String title, List<Block> blocks,
        {String assetPrefix = 'assets'}) =>
    _pageMarkdown(title, blocks, assetPrefix).text;

/// Build the page's Markdown projection. [assetPrefix] is the POSIX-relative
/// path from the page folder to the shared `assets/` dir; image links use it.
/// The returned `assets` map (hash → "hash.ext") is collected by the caller and
/// written once into the shared store.
_Markdown _pageMarkdown(String title, List<Block> blocks, String assetPrefix) {
  final ordered = [...blocks]..sort((a, b) {
      final dy = a.y.compareTo(b.y);
      return dy != 0 ? dy : a.x.compareTo(b.x);
    });
  final buf = StringBuffer('# $title\n\n');
  final assets = <String, String>{};
  var inkCount = 0;
  for (final b in ordered) {
    switch (b.type) {
      case BlockType.text:
        buf.writeln(
            markdownInline(b.content['text'] as String? ?? '').trimRight());
        buf.writeln();
      case BlockType.math:
        final latex = b.content['latex'] as String? ?? '';
        if (latex.isNotEmpty) buf.writeln('\$\$\n$latex\n\$\$\n');
      case BlockType.graph:
        // A curve has no Markdown, so what travels is the equation it is
        // a curve OF — written as an equation on its own line, which a
        // re-import can do something with. A missing case here writes
        // nothing at all, which is how `board` was left out of this file
        // for a whole release.
        final gtex = b.content['latex'] as String? ?? '';
        if (gtex.isNotEmpty) {
          buf.writeln('Graph of:\n\n\$\$\n$gtex\n\$\$\n');
        }
      case BlockType.substitute:
        // Same reasoning as a graph: what travels is the equation, plus
        // whatever value was last plugged into it.
        final stex = b.content['latex'] as String? ?? '';
        final sval = (b.content['value'] as String? ?? '').trim();
        if (stex.isNotEmpty) {
          if (sval.isEmpty) {
            buf.writeln('Evaluate:\n\n\$\$\n$stex\n\$\$\n');
          } else {
            final outcome = substituteInto(graphSourceFromLatex(stex), sval);
            buf.writeln('Evaluate:\n\n\$\$\n$stex\n\$\$\n\nat '
                '${outcome.variable} = $sval: ${outcome.result.display}\n');
          }
        }
      case BlockType.code:
        final lang = b.content['language'] as String? ?? '';
        buf.writeln('```$lang\n${b.content['source'] ?? ''}\n```\n');
      case BlockType.image:
        final hash =
            (b.content['blob'] as String? ?? '').replaceFirst('sha256:', '');
        if (hash.isNotEmpty) {
          final mime = b.content['mime'] as String? ?? 'image/png';
          final ext = mime.split('/').last.replaceFirst('jpeg', 'jpg');
          assets[hash] = '$hash.$ext';
          buf.writeln('![image]($assetPrefix/$hash.$ext)\n');
        }
      case BlockType.table:
        final table = tableToMarkdown(b.content['cells']);
        if (table.isNotEmpty) {
          buf.writeln(table);
          buf.writeln();
        }
      case BlockType.ink:
        inkCount += (b.content['strokes'] as List?)?.length ?? 0;
      default:
        break;
    }
  }
  if (inkCount > 0) {
    buf.writeln('> _This page also contains $inkCount ink strokes '
        '(see page.inkml for the vector data)._');
  }
  return _Markdown(buf.toString(), assets);
}

/// [_jsonCanvas], for tests.
@visibleForTesting
Map<String, dynamic> openJsonCanvasOf(List<Block> blocks,
        {String assetPrefix = 'assets'}) =>
    _jsonCanvas(blocks, assetPrefix);

/// Map blocks to a JSON Canvas document (https://jsoncanvas.org/spec/1.0/).
/// [assetPrefix] is the POSIX-relative path from the output file to `assets/`.
Map<String, dynamic> _jsonCanvas(List<Block> blocks, String assetPrefix) {
  final nodes = <Map<String, dynamic>>[];
  for (final b in blocks) {
    final x = b.x.round();
    final y = b.y.round();
    final w = b.w.round().clamp(1, 100000);
    final h = (b.h ?? 60).round().clamp(1, 100000);
    switch (b.type) {
      case BlockType.text:
        nodes.add({
          'id': b.id,
          'type': 'text',
          'text': b.content['text'] as String? ?? '',
          'x': x,
          'y': y,
          'width': w,
          'height': h,
        });
      case BlockType.graph:
        // JSON Canvas has no curve, so a graph travels as the text of its
        // equation. Better a readable node than a hole in the file.
        nodes.add({
          'id': b.id,
          'type': 'text',
          'text': 'Graph of \$${b.content['latex'] ?? ''}\$',
          'x': x,
          'y': y,
          'width': w,
          'height': h,
        });
      case BlockType.substitute:
        // Same reasoning as a graph: a substitute block travels as the text
        // of its equation and, when there is one, the value plugged into it.
        final slatex = b.content['latex'] as String? ?? '';
        final sval = (b.content['value'] as String? ?? '').trim();
        String stext;
        if (sval.isEmpty) {
          stext = 'Evaluate \$$slatex\$';
        } else {
          final outcome = substituteInto(graphSourceFromLatex(slatex), sval);
          stext = 'Evaluate \$$slatex\$ at ${outcome.variable} = $sval: '
              '${outcome.result.display}';
        }
        nodes.add({
          'id': b.id,
          'type': 'text',
          'text': stext,
          'x': x,
          'y': y,
          'width': w,
          'height': h,
        });
      case BlockType.math:
        final latex = b.content['latex'] as String? ?? '';
        nodes.add({
          'id': b.id,
          'type': 'text',
          'text': latex.isEmpty ? '' : '\$\$$latex\$\$',
          'x': x,
          'y': y,
          'width': w,
          'height': h,
        });
      case BlockType.code:
        final lang = b.content['language'] as String? ?? '';
        nodes.add({
          'id': b.id,
          'type': 'text',
          'text': '```$lang\n${b.content['source'] ?? ''}\n```',
          'x': x,
          'y': y,
          'width': w,
          'height': h,
        });
      case BlockType.table:
        nodes.add({
          'id': b.id,
          'type': 'text',
          'text': tableToMarkdown(b.content['cells']),
          'x': x,
          'y': y,
          'width': w,
          'height': h,
        });
      case BlockType.image:
        final hash =
            (b.content['blob'] as String? ?? '').replaceFirst('sha256:', '');
        final mime = b.content['mime'] as String? ?? 'image/png';
        final ext = mime.split('/').last.replaceFirst('jpeg', 'jpg');
        nodes.add({
          'id': b.id,
          'type': 'file',
          'file': '$assetPrefix/$hash.$ext',
          'x': x,
          'y': y,
          'width': w,
          'height': h,
        });
      default:
        break; // ink/file/embed have no JSON Canvas equivalent
    }
  }
  return {'nodes': nodes, 'edges': <Map<String, dynamic>>[]};
}

/// Build a W3C InkML document from every ink stroke on the page, or null if
/// the page has no ink. Channels X Y F (F = pressure, 0..1).
String? _inkML(List<Block> blocks) {
  final strokes = <Stroke>[];
  for (final b in blocks.where((b) => b.type == BlockType.ink)) {
    for (final sj in (b.content['strokes'] as List? ?? const [])) {
      strokes.add(Stroke.fromJson((sj as Map).cast<String, dynamic>()));
    }
  }
  if (strokes.isEmpty) return null;

  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<ink xmlns="http://www.w3.org/2003/InkML">')
    ..writeln('  <definitions>')
    ..writeln('    <inkSource xml:id="openote">')
    ..writeln('      <traceFormat>')
    ..writeln('        <channel name="X" type="decimal"/>')
    ..writeln('        <channel name="Y" type="decimal"/>')
    ..writeln('        <channel name="F" type="decimal" min="0" max="1"/>')
    ..writeln('        <channel name="T" type="integer" units="ms"/>')
    ..writeln('      </traceFormat>')
    ..writeln('    </inkSource>');
  // One brush per distinct (tool,color,size,opacity).
  final brushes = <String, String>{}; // key -> brush id
  for (final s in strokes) {
    final key = '${s.tool}|${s.colorHex}|${s.size}|${s.opacity}';
    brushes.putIfAbsent(key, () {
      final id = 'br${brushes.length + 1}';
      buf
        ..writeln('    <brush xml:id="$id">')
        ..writeln('      <brushProperty name="tool" value="${_xml(s.tool)}"/>')
        ..writeln(
            '      <brushProperty name="color" value="${_xml(s.colorHex)}"/>')
        ..writeln('      <brushProperty name="width" value="${s.size}"/>')
        ..writeln('      <brushProperty name="opacity" value="${s.opacity}"/>')
        ..writeln('    </brush>');
      return id;
    });
  }
  buf.writeln('  </definitions>');
  for (final s in strokes) {
    final key = '${s.tool}|${s.colorHex}|${s.size}|${s.opacity}';
    final brushRef = brushes[key];
    final pts = <String>[];
    for (var i = 0; i < s.x.length; i++) {
      final pr = i < s.p.length ? s.p[i] : 1.0;
      final t = i < s.t.length ? s.t[i] : 0;
      pts.add('${_num(s.x[i])} ${_num(s.y[i])} ${_num(pr)} $t');
    }
    buf.writeln('  <trace brushRef="#$brushRef">${pts.join(', ')}</trace>');
  }
  buf.writeln('</ink>');
  return buf.toString();
}

String _emptyInkML() => '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<ink xmlns="http://www.w3.org/2003/InkML"/>\n';

String _num(double v) {
  final r = (v * 100).roundToDouble() / 100; // 2 dp, drop trailing zeros
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _uniqueDir(String parent, String name) {
  var candidate = p.join(parent, name);
  var i = 2;
  while (Directory(candidate).existsSync() || File(candidate).existsSync()) {
    candidate = p.join(parent, '$name-$i');
    i++;
  }
  return candidate;
}
