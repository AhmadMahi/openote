// Turning a model's Markdown outline into a mind map, via the shared importer.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/mindmap/mindmap_ai.dart';

void main() {
  group('mindmapFromOutline', () {
    test('a heading with nested bullets becomes a centre with branches', () {
      final root = mindmapFromOutline('''
# Water cycle
- Evaporation
  - From oceans
- Condensation
- Precipitation
''');
      expect(root, isNotNull);
      expect(root!.text, 'Water cycle');
      expect(root.children.map((c) => c.text),
          containsAll(['Evaporation', 'Condensation', 'Precipitation']));
      final evap = root.children.firstWhere((c) => c.text == 'Evaporation');
      expect(evap.children.single.text, 'From oceans');
    });

    test('a code fence around the outline is stripped', () {
      final root = mindmapFromOutline('```markdown\n# Idea\n- One\n- Two\n```');
      expect(root, isNotNull);
      expect(root!.text, 'Idea');
      expect(root.children.length, 2);
    });

    test('a blank reply yields null, not a bare starter map', () {
      expect(mindmapFromOutline('   \n  '), isNull);
    });
  });

  test('the prompts steer the model toward an outline', () {
    expect(mindmapSystemPrompt().toLowerCase(), contains('outline'));
    expect(mindmapUserPrompt('photosynthesis'), contains('photosynthesis'));
  });
}
