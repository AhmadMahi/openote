// The per-page share bucket: paths add/dedupe/remove/clear and persist, and
// files sort into the right assets/ subfolder by extension.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/repo_push.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('assetSubfolderFor', () {
    test('sorts by extension into PDF / PPT / code / other', () {
      expect(assetSubfolderFor('slides.pdf'), 'PDF');
      expect(assetSubfolderFor('deck.PPTX'), 'PPT');
      expect(assetSubfolderFor('talk.key'), 'PPT');
      expect(assetSubfolderFor('demo.ipynb'), 'code');
      expect(assetSubfolderFor('main.dart'), 'code');
      expect(assetSubfolderFor('notes.txt'), 'other');
      expect(assetSubfolderFor('noext'), 'other');
    });
  });

  group('the bucket', () {
    late Directory tmp;
    late Repository repo;
    late AppState app;
    late String pageId;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_bucket_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('T');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      await app.selectPage(page.id);
      pageId = page.id;
    });

    tearDown(() {
      AppState.syncLogEnabled = true;
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('files add, dedupe, remove, clear, and persist per page', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.addBucketFiles(['/a/slides.pdf', '/a/demo.ipynb']);
      app.addBucketFiles(['/a/slides.pdf']); // duplicate ignored
      expect(app.bucket, ['/a/slides.pdf', '/a/demo.ipynb']);

      final raw = repo.getSetting('bucket:$pageId');
      expect(raw, isA<List>());
      expect((raw as List).length, 2);

      app.removeBucketPath('/a/slides.pdf');
      expect(app.bucket, ['/a/demo.ipynb']);

      app.clearBucket();
      expect(app.bucket, isEmpty);
      expect((repo.getSetting('bucket:$pageId') as List), isEmpty);
    });
  });
}
