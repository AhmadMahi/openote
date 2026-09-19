// The per-notebook sticky agenda: items, checking off, the "next" item the
// minimized note shows, delete/clear, and persistence.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late String nbId;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_sticky_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    nbId = nb.id;
    app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
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

  test('items add, check off, and the next-item advances', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.addStickyItem('Intro');
    app.addStickyItem('Demo');
    app.addStickyItem('Q&A');
    expect(app.stickyItems.map((e) => e.text), ['Intro', 'Demo', 'Q&A']);
    expect(app.nextStickyItem?.text, 'Intro',
        reason: 'the first unchecked item is what the minimized note shows');

    app.toggleStickyItem(0); // Intro done
    expect(app.stickyItems[0].done, isTrue);
    expect(app.nextStickyItem?.text, 'Demo', reason: 'it moves to the next');

    app.deleteStickyItem(1); // remove Demo
    expect(app.stickyItems.map((e) => e.text), ['Intro', 'Q&A']);
    expect(app.nextStickyItem?.text, 'Q&A');

    app.clearStickyItems();
    expect(app.stickyItems, isEmpty);
    expect(app.nextStickyItem, isNull);
  });

  test('setStickyItems replaces the list, dropping blanks', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.addStickyItem('old');
    app.setStickyItems(['One', '  ', 'Two']);
    expect(app.stickyItems.map((e) => e.text), ['One', 'Two']);
  });

  test('open state, position and items are persisted per notebook', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.toggleStickyOpen();
    app.addStickyItem('Persist me');
    app.toggleStickyItem(0);
    app.setStickyPos(120, 60);
    final raw = repo.getSetting('sticky:$nbId');
    expect(raw, isA<Map>());
    final m = raw as Map;
    expect(m['open'], isTrue);
    expect(m['x'], 120);
    expect(m['y'], 60);
    expect((m['items'] as List).length, 1);
    expect((m['items'] as List).first, containsPair('t', 'Persist me'));
    expect((m['items'] as List).first, containsPair('d', true));
  });
}
