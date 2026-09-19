// The per-notebook sticky agenda: items, checking off, the "next" item the
// minimized note shows, delete/clear, and persistence.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('scope routes the agenda to per-notebook vs one shared key', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Per-notebook (default): items land under this notebook's own key.
    app.addStickyItem('for T only');
    expect(app.stickyScopeGlobal, isFalse);
    final perNb = repo.getSetting('sticky:$nbId') as Map;
    expect((perNb['items'] as List).length, 1);

    // Switch to shared: the note reads/writes one fixed key and starts fresh.
    app.setStickyScopeGlobal(true);
    expect(app.stickyItems, isEmpty, reason: 'shared list starts empty');
    app.addStickyItem('everywhere');

    final shared = repo.getSetting('sticky:__all__') as Map;
    expect((shared['items'] as List).first, containsPair('t', 'everywhere'));
    // The per-notebook list is untouched by writes made in shared scope.
    final perNbAgain = repo.getSetting('sticky:$nbId') as Map;
    expect((perNbAgain['items'] as List).length, 1);
    expect(
        (perNbAgain['items'] as List).first, containsPair('t', 'for T only'));

    // Switching back restores the per-notebook list in place.
    app.setStickyScopeGlobal(false);
    expect(app.stickyItems.map((e) => e.text), ['for T only']);
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
