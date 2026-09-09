// Renders the shell to PNGs so the restyle can be LOOKED at before a CI
// build. Not a test of anything; skipped unless UI_PREVIEW_OUT is set.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/settings_dialog.dart';

import '../support/sqlite.dart';

void main() {
  final out = Platform.environment['UI_PREVIEW_OUT'];
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    if (!haveSqlite || out == null) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_preview_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Physics');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    app.importPage(
        nb.id,
        page.id,
        [
          Block(type: BlockType.text, x: 60, y: 80, w: 520, h: 200, content: {
            'text': '# Waves and optics\n\nThe **wavelength** sets the colour; '
                'the *amplitude* sets the brightness.\n\n- reflection\n- refraction'
          }),
        ],
        PageProps());
    app.addSection();
    app.addSection();
    app.reloadNodes();
    await app.selectPage(page.id);
    app.markOnboardingSeen();
  });

  tearDown(() {
    AppState.syncLogEnabled = true;
    if (!haveSqlite || out == null) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> loadFonts() async {
    final inter = FontLoader('Inter');
    for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/inter/Inter-$f.ttf'));
    }
    await inter.load();
  }

  Future<void> shoot(WidgetTester t, String name) async {
    final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  for (final mode in [Brightness.light, Brightness.dark]) {
    testWidgets('preview ${mode.name}', (t) async {
      if (!haveSqlite || out == null) return markTestSkipped('preview only');
      await t.runAsync(loadFonts);
      t.view.physicalSize = const Size(1280, 780);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: onoteTheme(mode),
        home: RepaintBoundary(
            key: const ValueKey('shot'), child: AppShell(app: app)),
      ));
      await t.pump(const Duration(milliseconds: 900));
      await t.pump(const Duration(milliseconds: 300));
      await shoot(t, 'home-${mode.name}');
      await t.tap(find.text('Draw'));
      await t.pump(const Duration(milliseconds: 300));
      app.setTool(Tool.pen);
      await t.pump(const Duration(milliseconds: 300));
      await shoot(t, 'draw-${mode.name}');
      await t.tap(find.text('View'));
      await t.pump(const Duration(milliseconds: 300));
      await shoot(t, 'view-${mode.name}');
      // Content under the glass: scroll the page up so the heading passes
      // beneath the bars, which is the only state in which glass is visible.
      app.canvas.panBy(const Offset(0, -150));
      await t.pump(const Duration(milliseconds: 300));
      await shoot(t, 'scrolled-${mode.name}');
      app.cancelPendingSave();
    });
  }

  // A themed variant: green accent, cream ruled paper, the Settings dialog
  // open on its new sections.
  testWidgets('preview themed', (t) async {
    if (!haveSqlite || out == null) return markTestSkipped('preview only');
    await t.runAsync(loadFonts);
    t.view.physicalSize = const Size(1280, 780);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    app.setAccent(OnoteAccent.green);
    app.setPaper('cream');
    app.setBackground('ruled');
    await t.pumpWidget(MaterialApp(
      theme: onoteTheme(Brightness.light, accent: app.accent),
      home: RepaintBoundary(
          key: const ValueKey('shot'), child: AppShell(app: app)),
    ));
    await t.pump(const Duration(milliseconds: 900));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('View'));
    await t.pump(const Duration(milliseconds: 300));
    await shoot(t, 'themed-green-cream');
    app.setPaper('texture');
    await t.pump(const Duration(milliseconds: 300));
    await shoot(t, 'themed-texture');
    showSettingsDialog(t.element(find.byType(AppShell)), app);
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    await shoot(t, 'themed-settings');
    app.setAccent(OnoteAccent.blue);
    app.cancelPendingSave();
  });
}
