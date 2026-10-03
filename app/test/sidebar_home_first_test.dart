// Home-first navigator: Home sits at the top of the sidebar at all times, and
// the open project's switcher, tree and footer only appear once a project is
// open. At Home the navigator is just Home + search — the projects themselves
// live in the main area, not the sidebar.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

Widget host(AppState app) => MaterialApp(
      theme: onoteTheme(Brightness.light),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => Sidebar(app: app),
        ),
      ),
    );

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_homefirst_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Alpha');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
  });

  tearDown(() {
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('with a project open: Home on top, plus the tree and footer',
      (t) async {
    if (!haveSqlite) return;
    expect(app.navHome, isFalse, reason: 'a project is open by default');
    await t.pumpWidget(host(app));
    await t.pumpAndSettle();

    // Home is the top of the navigator.
    expect(find.text('Home'), findsOneWidget);
    // The open project's switcher and its seeded notebook are shown.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Notebook 1'), findsOneWidget);
    // The footer has one clear, full-width primary action now.
    expect(find.widgetWithText(TextButton, 'Add a notebook'), findsOneWidget);
    // Opening the seeded notebook reveals an inline "Add page" line under its
    // pages — the quick way to add a page from inside the tree.
    await app.activateSection(
        app.nodes.firstWhere((n) => n.kind == NodeKind.section).id);
    await t.pumpAndSettle();
    expect(find.text('Add page'), findsOneWidget);
    // Collapse lives in the Home header, available either way.
    expect(find.byTooltip('Collapse the navigator  (Ctrl+)'), findsOneWidget);
    app.cancelPendingSave(); // activating a notebook schedules an autosave
  });

  testWidgets('at Home: just Home + search, no project tree or footer',
      (t) async {
    if (!haveSqlite) return;
    app.openHome();
    await t.pumpWidget(host(app));
    await t.pumpAndSettle();

    // Home is still there, now the active target.
    expect(find.text('Home'), findsOneWidget);
    // The project switcher, its tree and the footer are gone.
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Notebook 1'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Notebook'), findsNothing);
    // Search stays available.
    expect(find.byType(TextField), findsOneWidget);
  });
}
