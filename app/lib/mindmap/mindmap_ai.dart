/// Generating a mind map from a prompt with a cloud model.
///
/// The model is asked for a **Markdown outline**, which is exactly what
/// [parseMarkdownOutline] already turns into a tree for the "import a Markdown
/// outline" button. So the AI path reuses the whole importer: the model's only
/// job is to produce good outline text, and the shape it becomes is the same
/// tested conversion an imported file goes through.
library;

import '../ai/ai_provider.dart';
import 'mindmap.dart';

/// The house rules: a single Markdown outline, nothing else.
String mindmapSystemPrompt() =>
    'You design mind maps and reply with ONLY a Markdown outline, no prose and '
    'no code fences. Use one top-level heading "# Central idea" for the centre, '
    'then nested bullet points ("-") for branches and sub-branches, indented '
    'two spaces per level. Keep every label short — a few words at most. Aim '
    'for three to six main branches, each with a few children.';

String mindmapUserPrompt(String topic) => 'Make a mind map about:\n$topic';

/// The round trip: ask the model, count tokens, hand back the outline it wrote
/// (parsing into a tree is the caller's job, via [parseMarkdownOutline]).
class MindmapAiResult {
  const MindmapAiResult({this.markdown, this.error, this.tokens = 0});
  final String? markdown;
  final String? error;
  final int tokens;
  bool get ok => error == null && (markdown?.trim().isNotEmpty ?? false);
}

Future<MindmapAiResult> generateMindmapOutline(
  AiClient client, {
  required String topic,
}) async {
  final res = await client.chat(
    [
      AiMessage.system(mindmapSystemPrompt()),
      AiMessage.user(mindmapUserPrompt(topic)),
    ],
    temperature: 0.6,
  );
  if (!res.ok) return MindmapAiResult(error: res.error, tokens: 0);
  final md = _stripFence(res.text);
  if (md.trim().isEmpty) {
    return MindmapAiResult(
        error: 'The model returned an empty outline. Try again.',
        tokens: res.totalTokens);
  }
  return MindmapAiResult(markdown: md, tokens: res.totalTokens);
}

/// Parse the model's outline into a tree, or null if nothing usable came back.
MindNode? mindmapFromOutline(String markdown) {
  final root = parseMarkdownOutline(_stripFence(markdown));
  // parseMarkdownOutline never fails, but an all-blank reply yields the bare
  // starter — treat that as "nothing generated".
  if (root.children.isEmpty && root.text == MindNode.starter().text) {
    return null;
  }
  return root;
}

String _stripFence(String s) {
  var t = s.trim();
  if (!t.startsWith('```')) return t;
  t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
  final end = t.lastIndexOf('```');
  if (end != -1) t = t.substring(0, end);
  return t.trim();
}
