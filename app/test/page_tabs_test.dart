// The editor's tab strip: opening pages as tabs, the cap of four, closing the
// active tab, persistence, and pruning a tab whose page was deleted.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
  late String nbId;
  final pages = <String>[];

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_tabs_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    nbId = nb.id;
    app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    final section = app.importNode(
        nb.id, TreeNode(kind: NodeKind.section, title: 'S', position: 'a0'));
    pages.clear();
    for (var i = 0; i < 6; i++) {
      final p = app.importNode(
          nb.id,
          TreeNode(
              kind: NodeKind.page,
              parentId: section.id,
              title: 'Page ${i + 1}',
              position: 'a${i + 1}'));
      pages.add(p.id);
    }
    app.reloadNodes();
    await app.selectPage(pages.first);
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

  PageTab tab(String pageId) => PageTab(nbId, pageId, '');

  test('opening a page as a tab adds it and switches to it', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await app.openInNewTab(pages[1]);
    expect(app.openTabs, contains(tab(pages[1])));
    expect(app.pageId, pages[1]);
    expect(app.isActiveTab(tab(pages[1])), isTrue);
    // Opening the same page again does not duplicate it.
    await app.openInNewTab(pages[1]);
    expect(app.openTabs.where((t) => t == tab(pages[1])).length, 1);
  });

  test('the tab count is capped at four, dropping the oldest', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    for (var i = 0; i < 5; i++) {
      await app.openInNewTab(pages[i]);
    }
    expect(app.openTabs.length, AppState.maxTabs);
    expect(app.openTabs, isNot(contains(tab(pages[0]))),
        reason: 'the oldest tab is dropped past the cap');
    expect(app.openTabs, contains(tab(pages[4])));
  });

  test('closing the active tab moves to a neighbour', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await app.openInNewTab(pages[1]);
    await app.openInNewTab(pages[2]); // active
    app.closeTab(tab(pages[2]));
    await Future<void>.delayed(Duration.zero); // activateTab is async
    expect(app.openTabs, isNot(contains(tab(pages[2]))));
    expect(app.pageId, pages[1], reason: 'fell back to the neighbouring tab');
  });

  test('open tabs are written to the store for next launch', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await app.openInNewTab(pages[1]);
    await app.openInNewTab(pages[2]);
    final raw = repo.getSetting('openTabs');
    expect(raw, isA<List>());
    expect((raw as List).length, 2);
  });

  test('a tab whose page was deleted is pruned on reload', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await app.openInNewTab(pages[3]);
    expect(app.openTabs, contains(tab(pages[3])));
    await app.deleteNode(pages[3]);
    app.reloadNodes();
    expect(app.openTabs, isNot(contains(tab(pages[3]))),
        reason: 'a deleted page leaves no dead tab');
  });
}
