// Does a pen drag actually leave ink on the page?
//
// There was no test anywhere that drove a real pointer across the canvas with
// a drawing tool armed, so "the pen does not draw" could regress and the
// whole 2700-test suite would stay green. This is that test.
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/canvas/ink_painter.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Repository repo;
  late Directory tmp;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_inkdraw_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Canvas');
    app = AppState(repo)..notebookId = nb.id..spellCheckEnabled = false;
    app.reloadNodes();
    await app.selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
  });

  tearDown(() {
    AppState.syncLogEnabled = true;
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try { tmp.deleteSync(recursive: true); } catch (_) {}
  });

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 800, height: 600, child: PageCanvas(state: app)),
      ),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('a mouse drag leaves a stroke with AUTO SHAPES ON', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.autoShape = true;
    app.setTool(Tool.pen);
    await pump(t);
    final g = await t.startGesture(const Offset(300, 300),
        kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset(300 + i * 10.0, 300 + i * 5.0));
      await t.pump();
    }
    await g.up();
    await t.pumpAndSettle();
    final ink = app.blocks.where((b) => b.type == BlockType.ink).toList();
    expect(ink, isNotEmpty, reason: 'THE PEN MUST LEAVE INK');
    final strokes = ink.first.content['strokes'] as List;
    expect(strokes, isNotEmpty);
    final xs = (strokes.first as Map)['x'] as List;
    expect(xs, isNotEmpty, reason: 'a snapped stroke still has points');
    expect(ink.first.w, greaterThan(0));
    expect(ink.first.h, greaterThan(0));
    app.cancelPendingSave();
  });

  testWidgets('a mouse drag with the pen leaves a stroke', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setTool(Tool.pen);
    await pump(t);
    final g = await t.startGesture(const Offset(300, 300),
        kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset(300 + i * 10.0, 300 + i * 5.0));
      await t.pump();
    }
    await g.up();
    await t.pumpAndSettle();
    final ink = app.blocks.where((b) => b.type == BlockType.ink).toList();
    expect(ink, isNotEmpty, reason: 'THE PEN MUST LEAVE INK');
    final strokes = ink.first.content['strokes'] as List;
    expect(strokes, isNotEmpty);
    // The block has to have real BOUNDS as well as real points: the canvas
    // culls blocks that do not overlap the viewport, so a stroke with a
    // degenerate rect is stored perfectly and drawn nowhere.
    final b = ink.first;
    expect(b.w, greaterThan(0));
    expect(b.h, greaterThan(0));
    app.cancelPendingSave();
  });

  // ── Keeping the pen fluent ───────────────────────────────────────────────
  //
  // These pin the properties that make inking cost what you just did rather
  // than what is already on the page. Each was a measured hitch.

  List<InkPainter> painters(WidgetTester t) => [
        for (final c in t.widgetList<CustomPaint>(find.byType(CustomPaint)))
          if (c.painter is InkPainter) c.painter as InkPainter
      ];
  InkPainter dry(WidgetTester t) =>
      painters(t).firstWhere((p) => p.strokes.isNotEmpty);

  Future<void> stroke(WidgetTester t, Offset from, Offset to) async {
    final g = await t.startGesture(from, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 8)!);
      await t.pump();
    }
    await g.up();
    await t.pump();
  }

  testWidgets(
      'a new stroke keeps the strokes already on screen (no re-solve per pen '
      'lift), and the block rect is still the true bounds', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setTool(Tool.pen);
    await pump(t);
    await stroke(t, const Offset(300, 300), const Offset(380, 320));
    final first = dry(t).strokes.single;

    await stroke(t, const Offset(200, 420), const Offset(260, 480));
    await stroke(t, const Offset(500, 200), const Offset(560, 210));

    final ink = app.blocks.where((b) => b.type == BlockType.ink).toList();
    expect(ink.length, 1, reason: 'quick strokes share one block');
    final b = ink.single;
    final decoded = [
      for (final sj in b.content['strokes'] as List)
        Stroke.fromJson((sj as Map).cast<String, dynamic>())
    ];
    expect(decoded.length, 3);
    // What a full refit over every stroke would have produced.
    var mnx = double.infinity, mny = double.infinity, mxx = -1e18, mxy = -1e18;
    for (final s in decoded) {
      final bb = s.bounds();
      if (bb.minX < mnx) mnx = bb.minX;
      if (bb.minY < mny) mny = bb.minY;
      if (bb.maxX > mxx) mxx = bb.maxX;
      if (bb.maxY > mxy) mxy = bb.maxY;
    }
    expect(b.x, closeTo(mnx, 1e-6));
    expect(b.y, closeTo(mny, 1e-6));
    expect(b.w, closeTo(mxx - mnx, 1e-6));
    expect(b.h, closeTo(mxy - mny, 1e-6));

    final shown = dry(t).strokes;
    expect(shown.length, 3, reason: 'every committed stroke is painted');
    expect(identical(shown.first, first), isTrue,
        reason: 'the first stroke must be the SAME object after two more pen '
            'lifts — its solved outline is cached on it, and a fresh object '
            'means re-solving the whole block every time the pen comes up');
    app.cancelPendingSave();
  });

  testWidgets('the stroke in progress is painted on its own layer', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setTool(Tool.pen);
    await pump(t);
    await stroke(t, const Offset(300, 300), const Offset(380, 320));

    final g = await t.startGesture(const Offset(200, 420),
        kind: PointerDeviceKind.mouse);
    await g.moveTo(const Offset(230, 440));
    await t.pump();
    final ps = painters(t);
    final withDry = ps.where((p) => p.strokes.isNotEmpty).single;
    final wetLayer = ps.where((p) => p.strokes.isEmpty).single;
    expect(withDry.wet, isNull,
        reason: 'a pen sample must not repaint every stroke on the page');
    expect(wetLayer.wet, isNotNull);
    await g.up();
    await t.pump();
    expect(dry(t).strokes.length, 2);
    app.cancelPendingSave();
  });

  testWidgets('a highlighter stroke in progress stays in the ink layer',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setTool(Tool.pen);
    await pump(t);
    await stroke(t, const Offset(300, 300), const Offset(380, 320));
    app.setTool(Tool.highlighter);
    await t.pump();

    final g = await t.startGesture(const Offset(300, 310),
        kind: PointerDeviceKind.mouse);
    await g.moveTo(const Offset(360, 312));
    await t.pump();
    // It multiplies with the ink under it, which only works in one layer.
    expect(dry(t).wet, isNotNull);
    await g.up();
    await t.pump();
    app.cancelPendingSave();
  });

  testWidgets(
      'erasing one stroke keeps the others as they were, and the page shows '
      'exactly what is left', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setTool(Tool.pen);
    await pump(t);
    await stroke(t, const Offset(300, 300), const Offset(380, 300));
    await stroke(t, const Offset(300, 400), const Offset(380, 400));
    final kept = dry(t).strokes.last;

    app.setEraserMode(EraserMode.stroke);
    app.setTool(Tool.eraser);
    await t.pump();
    await stroke(t, const Offset(340, 280), const Offset(340, 320));

    final b = app.blocks.singleWhere((b) => b.type == BlockType.ink);
    expect((b.content['strokes'] as List).length, 1);
    final shown = dry(t).strokes;
    expect(shown.length, 1);
    expect(identical(shown.single, kept), isTrue,
        reason: 'the untouched stroke keeps its object, and so its outline');
    // The rect shrank to the stroke that is left.
    final bb = kept.bounds();
    expect(b.y, closeTo(bb.minY, 1e-6));
    expect(b.h, closeTo(bb.maxY - bb.minY, 1e-6));
    app.cancelPendingSave();
  });

  testWidgets(
      'rubbing out the middle of a stroke repaints it '
      '(regression: same count, same ends, different stroke)', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setTool(Tool.pen);
    await pump(t);
    await stroke(t, const Offset(300, 200), const Offset(380, 200));
    await stroke(t, const Offset(300, 300), const Offset(500, 300));
    await stroke(t, const Offset(300, 400), const Offset(380, 400));
    final before = dry(t);

    app.setEraserMode(EraserMode.area);
    app.setTool(Tool.eraser);
    await t.pump();
    // Nip the END off the middle stroke: one stroke in, one (shorter) out.
    final g = await t.startGesture(const Offset(500, 300),
        kind: PointerDeviceKind.mouse);
    await t.pump();
    await g.up();
    await t.pump();

    final after = dry(t);
    expect(after.strokes.length, 3);
    expect(identical(after.strokes.first, before.strokes.first), isTrue);
    expect(identical(after.strokes.last, before.strokes.last), isTrue);
    expect(after.shouldRepaint(before), isTrue,
        reason: 'the middle stroke changed; the layer has to be redrawn');
    app.cancelPendingSave();
  });

  testWidgets('scrolling reuses the block widgets, zooming rebuilds them',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.addBlock(Block(
        type: BlockType.text, x: 60, y: 120, w: 320, content: {'text': 'hi'}));
    app.select(null);
    await pump(t);
    final pointer = TestPointer(7, PointerDeviceKind.mouse);
    await t.sendEventToBinding(pointer.hover(const Offset(400, 300)));
    // The first notch of a scroll shows the scroll bar, which is a real
    // rebuild. Every notch after it is pan only.
    await t.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
    await t.pump();
    final before = t.widget<BlockView>(find.byType(BlockView));
    final topBefore = t.getTopLeft(find.byType(BlockView)).dy;

    await t.sendEventToBinding(pointer.scroll(const Offset(0, 60)));
    await t.pump();

    expect(t.getTopLeft(find.byType(BlockView)).dy, lessThan(topBefore),
        reason: 'the page really did scroll');
    expect(identical(t.widget<BlockView>(find.byType(BlockView)), before),
        isTrue,
        reason: 'a pan changes the transform only; rebuilding every visible '
            'block per scroll frame is what made scrolling heavy');

    app.canvas.zoomAt(const Offset(400, 300), 1.25);
    await t.pump();
    expect(identical(t.widget<BlockView>(find.byType(BlockView)), before),
        isFalse,
        reason: 'handles and hairlines are sized from the zoom');
    app.cancelPendingSave();
    await t.pump(const Duration(seconds: 2));
  });
}
