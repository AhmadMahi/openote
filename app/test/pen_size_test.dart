// Pen and highlighter each keep their own thickness, persisted separately, and
// setPenSize routes to whichever tool is active.
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

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_pensize_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
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

  test('pen and highlighter carry independent, persisted widths', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');

    app.setTool(Tool.pen);
    app.setPenSize(2);
    expect(app.penSize, 2);

    app.setTool(Tool.highlighter);
    // The highlighter starts thicker and is unaffected by the pen's width.
    expect(app.penSize, isNot(2));
    app.setPenSize(9);
    expect(app.penSize, 9);
    expect(repo.getSetting('highlighterSize'), 9);

    // Back to the pen: its own width is restored, not the highlighter's.
    app.setTool(Tool.pen);
    expect(app.penSize, 2);
    expect(repo.getSetting('penSize'), 2);
  });

  test('setPenSize clamps to the allowed range', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setTool(Tool.pen);
    app.setPenSize(999);
    expect(app.penSize, AppState.maxPenSize);
    app.setPenSize(-5);
    expect(app.penSize, AppState.minPenSize);
  });
}
