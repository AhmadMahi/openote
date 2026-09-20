// The sticky agenda: items, checking off, the "next" item the minimized note
// shows, delete/clear, and per-page / whole-notebook scope + persistence.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/sticky_note.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late String nbId;
  late String pageId;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_sticky_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    nbId = nb.id;
    app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    // A page is needed for the default (per-page) scope to have a home.
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

  test('nextStickyIndex points at the first unchecked item, -1 when all done',
      () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setStickyItems(['A', 'B', 'C']);
    expect(app.nextStickyIndex, 0);
    app.toggleStickyItem(0); // A done
    expect(app.nextStickyIndex, 1, reason: 'the minimized circle ticks B next');
    app.toggleStickyItem(1);
    app.toggleStickyItem(2);
    expect(app.nextStickyIndex, -1);
    expect(app.nextStickyItem, isNull);
  });

  test('opacity setting clamps and persists', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setStickyOpacity(0.5);
    expect(app.stickyOpacity, 0.5);
    expect(repo.getSetting('stickyOpacity'), 0.5);
    app.setStickyOpacity(9); // out of range → clamped to max
    expect(app.stickyOpacity, AppState.maxStickyOpacity);
    app.setStickyOpacity(0); // below min → clamped to min
    expect(app.stickyOpacity, AppState.minStickyOpacity);
  });

  test('scope routes the agenda per page vs whole notebook', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Per page (default): items land under this page's own key.
    app.addStickyItem('this page only');
    expect(app.stickyWholeNotebook, isFalse);
    final perPage = repo.getSetting('sticky:page:$pageId') as Map;
    expect((perPage['items'] as List).length, 1);

    // Switch to whole-notebook: reads/writes one notebook key, starts fresh.
    app.setStickyWholeNotebook(true);
    expect(app.stickyItems, isEmpty,
        reason: 'the notebook-wide list starts empty');
    app.addStickyItem('notebook-wide');

    final nb = repo.getSetting('sticky:nb:$nbId') as Map;
    expect((nb['items'] as List).first, containsPair('t', 'notebook-wide'));
    // The per-page list is untouched by writes made in whole-notebook scope.
    final perPageAgain = repo.getSetting('sticky:page:$pageId') as Map;
    expect((perPageAgain['items'] as List).length, 1);
    expect((perPageAgain['items'] as List).first,
        containsPair('t', 'this page only'));

    // Switching back restores the page's own list in place.
    app.setStickyWholeNotebook(false);
    expect(app.stickyItems.map((e) => e.text), ['this page only']);
  });

  test('timer mode: start minimizes and runs one item, complete finishes it',
      () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.toggleStickyTimerMode();
    expect(app.stickyTimerMode, isTrue);
    app.addStickyItem('Intro', minutes: 20);
    app.addStickyItem('Demo', minutes: 40);
    expect(app.stickySessionMinutes, 60);

    app.startStickyItem(0);
    expect(app.stickyItems[0].running, isTrue);
    expect(app.stickyMinimized, isTrue, reason: 'starting folds the note away');
    expect(app.runningStickyIndex, 0);

    // Starting another stops the first without completing it (one runs at once).
    app.startStickyItem(1);
    expect(app.stickyItems[0].running, isFalse);
    expect(app.stickyItems[0].done, isFalse);
    expect(app.runningStickyIndex, 1);

    app.completeStickyItem(1);
    expect(app.stickyItems[1].done, isTrue);
    expect(app.runningStickyIndex, -1);
    // Timer mode + item times persist.
    final raw = repo.getSetting('sticky:page:$pageId') as Map;
    expect(raw['timer'], isTrue);
    expect((raw['items'] as List).first, containsPair('m', 20));
  });

  test('timer mode: reorder, minutes edit, and break detection', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.toggleStickyTimerMode();
    app.addStickyItem('One', minutes: 10);
    app.addStickyItem('Two', minutes: 10);
    app.reorderStickyItem(0, 2); // move "One" to the end (LV convention)
    expect(app.stickyItems.map((e) => e.text), ['Two', 'One']);

    app.setStickyItemMinutes(0, 25);
    expect(app.stickyItems[0].minutes, 25);

    expect(AppState.isBreakLabel('break'), isTrue);
    expect(AppState.isBreakLabel('Break 20'), isTrue);
    // Word-boundary: "breakfast" is not a break.
    expect(AppState.isBreakLabel('breakfast plans'), isFalse);
    expect(AppState.isBreakLabel('lunch'), isFalse);
    app.addStickyItem('Break', minutes: 15, isBreak: true);
    expect(app.stickyItems.last.isBreak, isTrue);
    expect(app.stickyItems.last.minutes, 15);
  });

  test('open state, position and items are persisted per page', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.toggleStickyOpen();
    app.addStickyItem('Persist me');
    app.toggleStickyItem(0);
    app.setStickyPos(120, 60);
    final raw = repo.getSetting('sticky:page:$pageId');
    expect(raw, isA<Map>());
    final m = raw as Map;
    expect(m['open'], isTrue);
    expect(m['x'], 120);
    expect(m['y'], 60);
    expect((m['items'] as List).length, 1);
    expect((m['items'] as List).first, containsPair('t', 'Persist me'));
    expect((m['items'] as List).first, containsPair('d', true));
  });

  // The bug the owner hit: the note sat behind the zoom controls and could
  // not be grabbed, and in a drawing tool the whole card ignored the pointer
  // so it could not be dragged at all. The header must stay draggable in EVERY
  // tool — that is what makes it movable in focus mode with a pen in hand.
  testWidgets('the header drags the note even while a pen is up', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.toggleStickyOpen();
    app.setTool(Tool.pen); // a drawing tool: the body ignores the pointer
    app.setStickyPos(100, 100);

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) =>
              Stack(children: [StickyNote(app: app, topInset: 0)]),
        ),
      ),
    ));
    await t.pump();

    // The grip lives in the always-live header. Dragging it moves the note
    // even though a pen is up — before the fix the whole card was wrapped in
    // IgnorePointer in a drawing tool, so the note could not be grabbed at all
    // and both coordinates would stay put.
    final grip = find.byIcon(Icons.drag_indicator);
    expect(grip, findsOneWidget);
    await t.drag(grip, const Offset(40, 30));
    await t.pump();
    // The drag persisted through the autosave debounce; cancel it here (the
    // widget-tree invariant runs before tearDown) so no timer outlives the test.
    app.cancelPendingSave();

    expect(app.stickyX, greaterThan(100), reason: 'header drag moved it right');
    expect(app.stickyY, greaterThan(100), reason: 'header drag moved it down');
  });
}
