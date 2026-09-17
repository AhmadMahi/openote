// The quiz "present" round: a full-screen focus mode with a blurred backdrop,
// and a celebration on the results screen. State lives on the block, so the
// present overlay and the in-page card stay in step.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/quiz_block_view.dart';
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
    tmp = Directory.systemTemp.createTempSync('onote_quizpresent_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    await app.selectPage(page.id);
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

  Block _quiz() => app.addBlock(Block(
        type: BlockType.quiz,
        x: 0,
        y: 0,
        w: 420,
        content: {
          'name': 'Effective prompting',
          'questions': [
            {
              'q': 'Why is human validation important?',
              'options': ['Always wrong', 'Outputs may err', 'C', 'D'],
              'correct': 1,
              'explanation': 'AI can be confidently wrong.',
            },
          ],
        },
      ));

  Future<void> _pump(WidgetTester tester, Block b,
      {bool presentation = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 480,
              height: 640,
              child:
                  QuizBlockView(block: b, app: app, presentation: presentation),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('finishing the quiz shows the score celebration', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final b = _quiz();
    await _pump(tester, b);

    await tester.tap(find.text('Outputs may err'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See results'));
    await tester.pumpAndSettle();

    // The celebration replaces the old static score header.
    expect(find.text('Your score'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text('Perfect score!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Present opens a blurred overlay and Back closes it',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final b = _quiz();
    await _pump(tester, b);

    expect(find.byTooltip('Present'), findsOneWidget);
    await tester.tap(find.byTooltip('Present'));
    await tester.pumpAndSettle();

    // The overlay is up: a backdrop blur, and a second (presentation) quiz
    // whose header offers Back instead of Present.
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
