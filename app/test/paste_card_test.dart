// The "pasted card" round: pasted content is tagged so BlockView can wear the
// card look, and the preference that governs it defaults on and persists.
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
    tmp = Directory.systemTemp.createTempSync('onote_pastecard_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    await app.selectPage(page.id);
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

  test('pasteAsCard defaults on and the choice is written to the store',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    expect(app.pasteAsCard, isTrue, reason: 'on by default');

    app.setPasteAsCard(false);
    expect(app.pasteAsCard, isFalse);
    // Persisted, so init() picks it up on the next launch (same path the
    // other default toggles use).
    expect(repo.getSetting('pasteAsCard'), isFalse);
  });

  test('pasting text tags the block as pasted', () {
    if (!haveSqlite) return;
    final b = insertPastedText(
        app, 'A finance team receives invoices.', const Offset(80, 80));
    expect(b.type, BlockType.text);
    expect(b.content['pasted'], isTrue,
        reason: 'so BlockView can give it the card look');
    expect(b.content['text'], 'A finance team receives invoices.');
  });
}
