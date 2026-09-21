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

  test('size setting clamps and persists (one preferred size everywhere)', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setStickySize(400, 500);
    expect(app.stickyW, 400);
    expect(app.stickyH, 500);
    expect(repo.getSetting('stickyW'), 400);
    expect(repo.getSetting('stickyH'), 500);

    // Too big / too small → clamped to the note's limits.
    app.setStickySize(9999, 9999);
    expect(app.stickyW, AppState.maxStickyW);
    expect(app.stickyH, AppState.maxStickyH);
    app.setStickySize(0, 0);
    expect(app.stickyW, AppState.minStickyW);
    expect(app.stickyH, AppState.minStickyH);
  });

  test('background style, opacity and image persist', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    expect(app.backgroundStyle, 'none', reason: 'defaults to the current look');
    app.setBackgroundStyle('ambient-ocean');
    expect(app.backgroundStyle, 'ambient-ocean');
    expect(repo.getSetting('backgroundStyle'), 'ambient-ocean');

    app.setBackgroundOpacity(0.8);
    expect(app.backgroundOpacity, 0.8);
    expect(repo.getSetting('backgroundOpacity'), 0.8);
    app.setBackgroundOpacity(9); // clamped
    expect(app.backgroundOpacity, 1.0);

    // Setting a custom image switches to custom and persists the path.
    app.setBackgroundImagePath('/tmp/wall.png');
    expect(app.backgroundStyle, 'custom');
    expect(app.backgroundImagePath, '/tmp/wall.png');
    expect(repo.getSetting('backgroundImagePath'), '/tmp/wall.png');
  });

  test('break message mode is remembered (shared with agenda breaks)', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    expect(app.breakMessageMode, 1, reason: 'default is a motivating line');
    app.setBreakMessageMode(2); // AI-from-notebook
    expect(app.breakMessageMode, 2);
    expect(repo.getSetting('breakMessageMode'), 2);
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

  test(
      'completing clears the clock so a restart is fresh (no lingering overtime)',
      () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.toggleStickyTimerMode();
    app.addStickyItem('Talk', minutes: 20);

    // Start it in the past so it is deep in overtime.
    app.startStickyItem(0);
    app.stickyItems[0].startedAtMs =
        DateTime.now().millisecondsSinceEpoch - 30 * 60 * 1000; // 30m ago
    expect(app.stickyItems[0].running, isTrue);

    // Completing clears the start time, so it is no longer running/overtime.
    app.completeStickyItem(0);
    expect(app.stickyItems[0].done, isTrue);
    expect(app.stickyItems[0].startedAtMs, isNull);
    expect(app.stickyItems[0].running, isFalse);

    // Un-completing does NOT resurrect the old overtime clock.
    app.toggleStickyItem(0);
    expect(app.stickyItems[0].done, isFalse);
    expect(app.stickyItems[0].startedAtMs, isNull);
    expect(app.stickyItems[0].running, isFalse);

    // Starting again begins fresh (a start time within the last second).
    app.startStickyItem(0);
    final elapsed =
        DateTime.now().millisecondsSinceEpoch - app.stickyItems[0].startedAtMs!;
    expect(elapsed, lessThan(2000), reason: 'the clock restarted from full');
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

  test('parseAgendaLine reads CSV, trailing numbers, and breaks', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final a = AppState.parseAgendaLine('Introduction, 15');
    expect(a.text, 'Introduction');
    expect(a.minutes, 15);
    expect(a.isBreak, isFalse);

    final b = AppState.parseAgendaLine('Deep dive 40');
    expect(b.text, 'Deep dive');
    expect(b.minutes, 40);

    final c = AppState.parseAgendaLine('Break, 10');
    expect(c.text, 'Break');
    expect(c.minutes, 10);
    expect(c.isBreak, isTrue);

    final d = AppState.parseAgendaLine('- Wrap-up and Q&A, 20');
    expect(d.text, 'Wrap-up and Q&A', reason: 'leading bullet stripped');
    expect(d.minutes, 20);

    final e = AppState.parseAgendaLine('Just a topic');
    expect(e.text, 'Just a topic');
    expect(e.minutes, 0);
  });

  test('setStickyAgendaParsed builds a full timed agenda from CSV lines', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.toggleStickyTimerMode();
    app.setStickyAgendaParsed([
      'Introduction, 15',
      'Core concepts, 30',
      'Break, 10',
      'Hands-on, 40',
    ]);
    expect(app.stickyItems.map((e) => e.text),
        ['Introduction', 'Core concepts', 'Break', 'Hands-on']);
    expect(app.stickyItems.map((e) => e.minutes), [15, 30, 10, 40]);
    expect(app.stickyItems[2].isBreak, isTrue);
    expect(app.stickySessionMinutes, 95);

    // Appending a pasted block adds to the end.
    app.addStickyAgendaParsed(['Q&A, 20']);
    expect(app.stickyItems.length, 5);
    expect(app.stickyItems.last.minutes, 20);
  });

  test('the sample prompt is available and asks for CSV', () {
    expect(AppState.stickyAgendaSamplePrompt, contains('CSV'));
    expect(AppState.stickyAgendaSamplePrompt, contains('topic, minutes'));
    expect(AppState.stickyAgendaSamplePrompt.toLowerCase(), contains('break'));
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

  // Delete-all is the last row of the SCROLLING list — out of sight until you
  // reach the end — and earns its place only past five items.
  testWidgets('delete-all is at the end of the list, only past five items',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.toggleStickyOpen();
    app.setTool(Tool.select);
    for (var i = 0; i < 5; i++) {
      app.addStickyItem('Item ${i + 1}');
    }

    Widget host() => MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: app,
              builder: (_, __) =>
                  Stack(children: [StickyNote(app: app, topInset: 0)]),
            ),
          ),
        );

    // A tall note so the whole (short) list plus the trailing row all fit,
    // and the delete-all can be asserted without scrolling.
    app.setStickySize(AppState.minStickyW, AppState.maxStickyH);

    await t.pumpWidget(host());
    await t.pump();
    expect(tester_exception(t), isNull, reason: 'the list builds cleanly');
    expect(find.text('Delete all'), findsNothing,
        reason: 'five items is not enough for it to exist at all');

    app.addStickyItem('Item 6'); // now six
    await t.pump();
    expect(tester_exception(t), isNull,
        reason: 'adding the trailing delete-all row builds cleanly');
    expect(find.text('Delete all'), findsOneWidget,
        reason: 'past five items it is the last row of the list');
    app.cancelPendingSave();
  });
}

/// Returns and clears any exception the widget tree threw during build/layout.
Object? tester_exception(WidgetTester t) => t.takeException();
