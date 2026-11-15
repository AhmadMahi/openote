// The central backup materializes EVERY notebook, including ones that are not
// the open one — so the notebook-scoped read path (nodesOf/readPageOf/blobOf)
// has to produce a full folder tree for a notebook without opening it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/export/open_export.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:path/path.dart' as p;

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  test('materializes a notebook that is not the open one', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final ws = Directory.systemTemp.createTempSync('onote_central_');
    final out = Directory.systemTemp.createTempSync('onote_central_out_');
    final repo = await Repository.openAt(ws);
    addTearDown(() {
      repo.dispose();
      for (final d in [ws, out]) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    final alpha = await repo.createNotebook('Alpha');
    final beta = await repo.createNotebook('Beta');
    // Open Alpha; Beta stays closed.
    final app = AppState(repo)..notebookId = alpha.id;
    app.reloadNodes();

    // Materialize the CLOSED notebook into a fresh folder.
    final root = p.join(out.path, 'Beta');
    await materializeNotebookInto(app, beta.id, root);

    final manifest = File(p.join(root, 'notebook.json'));
    expect(manifest.existsSync(), isTrue,
        reason: 'a notebook.json is written for the non-open notebook');
    final json = jsonDecode(manifest.readAsStringSync()) as Map;
    expect((json['notebook'] as Map)['title'], 'Beta');
    expect(json['format'], 'openote-materialized/1');
  });

  // ── The backup costs what changed, not what exists ──────────────────────
  //
  // The central backup used to wipe each notebook's folder and rebuild all of
  // it every five minutes, on the UI thread — the periodic hang. These pin the
  // incremental export that replaced it. "Left alone" is proved with a
  // sentinel written into a file between runs: a run that rewrites the file
  // destroys it, one that leaves it alone does not.
  group('incremental export', () {
    late Directory ws, out;
    late Repository repo;
    late AppState app;
    late String nb, page1;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      ws = Directory.systemTemp.createTempSync('onote_incr_');
      out = Directory.systemTemp.createTempSync('onote_incr_out_');
      repo = await Repository.openAt(ws);
      nb = (await repo.createNotebook('Course')).id;
      app = AppState(repo)
        ..notebookId = nb
        ..spellCheckEnabled = false;
      app.reloadNodes();
      page1 = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      await app.selectPage(page1);
      // Settle any save opening the page queued, so nothing writes the open
      // page from memory behind the test's back.
      await app.flushSave();
    });

    tearDown(() {
      AppState.syncLogEnabled = true;
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      for (final d in [ws, out]) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    void write(String pageId, String text, {String? blob}) => app.importPage(
        nb,
        pageId,
        [
          Block(
              type: BlockType.text,
              x: 60,
              y: 60,
              w: 400,
              content: {'text': text}),
          if (blob != null)
            Block(
                type: BlockType.image,
                x: 60,
                y: 200,
                w: 200,
                content: {'blob': blob, 'mime': 'image/png'}),
        ],
        PageProps());

    String pageDir(String root, String pageId) {
      final m = jsonDecode(File(p.join(root, 'notebook.json')).readAsStringSync())
          as Map;
      final e = (m['pages'] as List)
          .cast<Map>()
          .firstWhere((x) => x['id'] == pageId);
      return p.joinAll([root, ...(e['path'] as String).split('/')]);
    }

    Future<String> addPage() async {
      final before = {
        for (final n in app.nodes)
          if (n.kind == NodeKind.page) n.id
      };
      await app.addPage();
      await app.flushSave();
      return app.nodes
          .firstWhere((n) => n.kind == NodeKind.page && !before.contains(n.id))
          .id;
    }

    test('a second run with nothing changed touches nothing', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      write(page1, 'Hello');
      final root = p.join(out.path, 'Course');
      final state = MaterializedNotebook();
      expect(await materializeNotebookInto(app, nb, root, incremental: state),
          isTrue);
      final dir = pageDir(root, page1);
      expect(File(p.join(dir, 'page.json')).readAsStringSync(),
          contains('Hello'));
      final md = File(p.join(dir, 'page.md'))..writeAsStringSync('SENTINEL');
      final manifest = File(p.join(root, 'notebook.json')).readAsStringSync();

      expect(await materializeNotebookInto(app, nb, root, incremental: state),
          isFalse,
          reason: 'nothing changed, so nothing to commit');
      expect(md.readAsStringSync(), 'SENTINEL',
          reason: 'an unchanged page is not rewritten');
      expect(File(p.join(root, 'notebook.json')).readAsStringSync(), manifest,
          reason: 'notebook.json is not rewritten just to bump exportedAt — '
              'that made every sweep a commit');
    });

    test('editing one page rewrites that page and leaves the others',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final page2 = await addPage();
      write(page1, 'One');
      write(page2, 'Two');
      final root = p.join(out.path, 'Course');
      final state = MaterializedNotebook();
      await materializeNotebookInto(app, nb, root, incremental: state);
      final md1 = File(p.join(pageDir(root, page1), 'page.md'))
        ..writeAsStringSync('SENTINEL');
      final md2 = File(p.join(pageDir(root, page2), 'page.md'))
        ..writeAsStringSync('SENTINEL');

      write(page2, 'Two, edited');
      expect(await materializeNotebookInto(app, nb, root, incremental: state),
          isTrue);
      expect(md1.readAsStringSync(), 'SENTINEL',
          reason: 'the page that did not change is left alone');
      expect(md2.readAsStringSync(), isNot('SENTINEL'));
      expect(File(p.join(pageDir(root, page2), 'page.json')).readAsStringSync(),
          contains('Two, edited'));
    });

    test('a deleted page leaves the backup; a closed notebook keeps old PDFs',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final page2 = await addPage();
      write(page1, 'One');
      write(page2, 'Two');
      final root = p.join(out.path, 'Course');
      final state = MaterializedNotebook();
      await materializeNotebookInto(app, nb, root, incremental: state);
      final dir1 = pageDir(root, page1);
      final dir2 = pageDir(root, page2);
      expect(Directory(dir2).existsSync(), isTrue);
      // A PDF from the last time this notebook was open. A run for a closed
      // notebook cannot rebuild it, so it must not delete it either.
      final pdf = File(p.join(dir1, 'Old.pdf'))..writeAsStringSync('%PDF-1.4');

      await app.deleteNode(page2);
      await app.flushSave();
      expect(await materializeNotebookInto(app, nb, root, incremental: state),
          isTrue);
      expect(Directory(dir2).existsSync(), isFalse,
          reason: 'a deleted page does not linger in the backup');
      expect(File(p.join(dir1, 'page.json')).existsSync(), isTrue);
      expect(pdf.existsSync(), isTrue,
          reason: 'a closed notebook keeps the PDFs it cannot rebuild');
    });

    test('a picture is written once, and removed when nothing uses it',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final bytes = Uint8List.fromList(List.generate(64, (i) => i));
      final hash = app.importBlob(nb, bytes, 'image/png');
      final hex = hash.replaceFirst('sha256:', '');
      write(page1, 'With a picture', blob: hash);
      final root = p.join(out.path, 'Course');
      final state = MaterializedNotebook();
      await materializeNotebookInto(app, nb, root, incremental: state);
      final asset = File(p.join(root, 'assets', '$hex.png'));
      expect(asset.readAsBytesSync(), bytes);

      // Same length, different bytes: if the next run rewrote the picture,
      // this would be gone. Named by its hash, it never needs rewriting.
      asset.writeAsBytesSync(List.filled(64, 7));
      write(page1, 'Edited text, same picture', blob: hash);
      expect(await materializeNotebookInto(app, nb, root, incremental: state),
          isTrue);
      expect(asset.readAsBytesSync(), List.filled(64, 7),
          reason: 'a picture already in the backup is not read or rewritten');

      write(page1, 'No picture any more');
      await materializeNotebookInto(app, nb, root, incremental: state);
      expect(asset.existsSync(), isFalse,
          reason: 'a picture nothing references is removed');
    });

    test('the remembered state survives a round trip through JSON', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      write(page1, 'Hello');
      final root = p.join(out.path, 'Course');
      final state = MaterializedNotebook();
      await materializeNotebookInto(app, nb, root, incremental: state);
      final md = File(p.join(pageDir(root, page1), 'page.md'))
        ..writeAsStringSync('SENTINEL');

      // What the backup stores between launches.
      final reloaded = MaterializedNotebook.fromJson(
          jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>);
      expect(
          await materializeNotebookInto(app, nb, root, incremental: reloaded),
          isFalse);
      expect(md.readAsStringSync(), 'SENTINEL');
    });
  });
}
