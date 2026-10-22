// The shapes palette: the stroke builders turn a drag rectangle into pen
// strokes, and arming a shape switches to the Shapes tool.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/ink/shape_snap.dart' show Offset2;
import 'package:openote/ink/shapes.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  group('shape stroke builders', () {
    final from = Offset2(0, 0), to = Offset2(120, 90);

    test('every palette kind builds strokes from a drag rect', () {
      for (final kind in shapeKinds) {
        final strokes = shapeStrokes(kind,
            from: from, to: to, colorHex: '#2E9E5B', size: 2);
        expect(strokes, isNotEmpty, reason: '$kind should produce strokes');
        // The colour is carried through.
        expect(strokes.first.colorHex, '#2E9E5B');
      }
    });

    test('a cross is two separate strokes (the two diagonals)', () {
      final strokes =
          shapeStrokes('cross', from: from, to: to, colorHex: '#000', size: 2);
      expect(strokes.length, 2);
    });

    test('a degenerate drag places nothing', () {
      final p = Offset2(10, 10);
      for (final kind in shapeKinds) {
        expect(shapeStrokes(kind, from: p, to: p, colorHex: '#000', size: 2),
            isEmpty,
            reason: '$kind from a zero drag');
      }
    });
  });

  group('the palette arms the Shapes tool', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_shapes_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('S');
      app = AppState(repo)..notebookId = nb.id;
    });

    tearDown(() {
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('opening the palette arms the Shapes tool', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      expect(app.shapesOpen, isFalse);
      app.toggleShapesOpen();
      expect(app.shapesOpen, isTrue);
      expect(app.tool, Tool.shape);
    });

    test('picking the cross arms it in red, the check in green', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.armShape('cross', colorHex: 0xFFE5484D);
      expect(app.tool, Tool.shape);
      expect(app.shapeKind, 'cross');
      expect(app.shapeColorHex, 0xFFE5484D);

      app.armShape('check', colorHex: 0xFF2E9E5B);
      expect(app.shapeKind, 'check');
      expect(app.shapeColorHex, 0xFF2E9E5B);

      // A geometric shape keeps whatever colour is set.
      app.armShape('circle');
      expect(app.shapeKind, 'circle');
      expect(app.shapeColorHex, 0xFF2E9E5B);
    });
  });
}
