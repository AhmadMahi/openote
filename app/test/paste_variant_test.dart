// A pasted text that reads as a question or an exclamation is tagged so its
// block can wear a matching textbook-style callout.
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/media_drop.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_paste_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('P');
    app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
  });

  tearDown(() {
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a pasted question / exclamation is tagged, plain text is not', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final q = insertPastedText(app, 'Why is the sky blue?', Offset.zero);
    expect(q.content['variant'], 'question');

    final x = insertPastedText(app, 'Mind the gap!  ', Offset.zero);
    expect(x.content['variant'], 'note', reason: 'trailing space is ignored');

    final plain = insertPastedText(app, 'Just a note', Offset.zero);
    expect(plain.content.containsKey('variant'), isFalse);
    app.cancelPendingSave();
  });
}
