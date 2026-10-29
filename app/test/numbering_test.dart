// The numbering tool: each placement drops the next number as a stamp block,
// the counter steps up, and Reset starts the sequence over.
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

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_numbering_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('N');
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

  test('each placement stamps the next number and steps the counter', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    expect(app.numberNext, 1);
    app.addNumberAt(100, 100);
    app.addNumberAt(200, 100);
    app.addNumberAt(300, 100);

    final stamps = app.blocks.where((b) => b.type == BlockType.number).toList();
    expect(stamps.map((b) => b.content['n']).toList(), [1, 2, 3]);
    expect(app.numberNext, 4, reason: 'the counter is ready for the next one');
    // The stamp carries the current style/colour, and is square.
    expect(stamps.first.content['style'], 'circle');
    expect(stamps.first.content['color'], 0xFFE5484D);
    expect(stamps.first.w, stamps.first.h);
  });

  test('a dragged number takes the given size (square), a tap the default', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.addNumberAt(0, 0); // tap: default numberSize
    final tap = app.blocks.firstWhere((b) => b.type == BlockType.number);
    expect(tap.w, app.numberSize);
    expect(tap.w, tap.h);

    app.addNumberAt(200, 200, size: 90); // drag-sized
    final dragged = app.blocks.lastWhere((b) => b.type == BlockType.number);
    expect(dragged.w, 90);
    expect(dragged.w, dragged.h);
    app.cancelPendingSave();
  });

  test('the eraser defaults to whole-stroke', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    expect(app.eraserMode, EraserMode.stroke);
  });

  test('Reset starts the sequence over at 1', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.addNumberAt(10, 10);
    app.addNumberAt(20, 20);
    expect(app.numberNext, 3);
    app.resetNumbering();
    expect(app.numberNext, 1);
    app.addNumberAt(30, 30);
    expect(
        app.blocks.where((b) => b.type == BlockType.number).last.content['n'],
        1);
  });

  test('style, colour and size preferences flow into new stamps', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setNumberStyle('box');
    app.setNumberColorHex(0xFF2E9E5B);
    app.setNumberSize(64);
    app.addNumberAt(0, 0);
    final b = app.blocks.firstWhere((b) => b.type == BlockType.number);
    expect(b.content['style'], 'box');
    expect(b.content['color'], 0xFF2E9E5B);
    expect(b.w, 64);
    expect(b.h, 64);
  });
}
