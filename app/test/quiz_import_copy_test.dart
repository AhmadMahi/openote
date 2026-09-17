// "Copy sample schema and prompt" copies a prompt that carries the exact row
// format the parser accepts, so an AI's reply can be pasted straight back in.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/quiz/quiz_import.dart';
import 'package:openote/ui/quiz_import_dialog.dart';

void main() {
  test('the sample prompt states the format and the fields to fill in', () {
    expect(quizSchemaPrompt, contains('question, option 1, option 2'));
    expect(quizSchemaPrompt, contains('correct answer'));
    expect(quizSchemaPrompt.toLowerCase(), contains('topic:'));
    expect(quizSchemaPrompt.toLowerCase(), contains('number of questions'));
  });

  test('the example row in the prompt actually parses', () {
    // Pull the example line out of the prompt and feed it to the real parser,
    // so the schema we hand out can never drift from what the app accepts.
    final example = quizSchemaPrompt
        .split('\n')
        .firstWhere((l) => l.startsWith('"What is 2 + 2?"'));
    final res = parseQuizText(example);
    expect(res.isOk, isTrue, reason: res.error);
    expect(res.questions, hasLength(1));
    expect(res.questions.single.correct, 1); // "B" → index 1
  });
}
