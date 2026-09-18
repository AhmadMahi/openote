/// A mind map as a structured Markdown outline, for pushing to a repo alongside
/// a page.
///
/// The owner asked for the map "as it is shown" and fully expanded — so this
/// walks the WHOLE tree regardless of any node's collapsed state and writes the
/// central topic as an H1 and every branch as a nested bullet. Markdown reads
/// cleanly on GitHub, stays searchable, and is far tidier than the outline
/// rendered to PDF that this replaces.
library;

import '../mindmap/mindmap.dart';

/// Build the Markdown for [root]. [title] is a fallback heading when the root
/// node has no text of its own.
String mindmapToMarkdown(String title, MindNode root) {
  final buf = StringBuffer();
  final heading = root.text.trim().isEmpty ? title.trim() : root.text.trim();
  buf.writeln('# ${heading.isEmpty ? 'Mind map' : heading}');
  buf.writeln();

  // The root is the H1; its children are the top-level bullets, and depth grows
  // from there. Collapsed flags are ignored so the whole map is written out.
  void walk(MindNode n, int depth) {
    for (final c in n.children) {
      final text = c.text.trim().isEmpty ? '(untitled)' : c.text.trim();
      buf.writeln('${'  ' * depth}- $text');
      walk(c, depth + 1);
    }
  }

  walk(root, 0);
  return buf.toString();
}
