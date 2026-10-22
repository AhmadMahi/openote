import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';

/// A numbering stamp: one digit, drawn plain or inside a circle or box, in the
/// stamp's own colour. The value is fixed (it came from the numbering counter
/// when the stamp was dropped); the block is moved, resized or deleted like any
/// other, never typed into.
class NumberBlockView extends StatelessWidget {
  const NumberBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final n = (block.content['n'] as num?)?.toInt() ?? 0;
    final style = block.content['style'] as String? ?? 'circle';
    final color =
        Color((block.content['color'] as num?)?.toInt() ?? 0xFFE5484D);
    final w = block.w;
    final h = block.h ?? w;
    return SizedBox(
      width: w,
      height: h,
      child: CustomPaint(
        painter: _NumberPainter(n: n, style: style, color: color),
      ),
    );
  }
}

class _NumberPainter extends CustomPainter {
  _NumberPainter({required this.n, required this.style, required this.color});
  final int n;
  final String style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final short = size.shortestSide;
    final strokeW = (short * 0.08).clamp(2.0, 6.0);
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..isAntiAlias = true;
    final r = rect.deflate(strokeW / 2 + 1);
    if (style == 'circle') {
      canvas.drawOval(r, outline);
    } else if (style == 'box') {
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(short * 0.18)), outline);
    }
    final digitFrac = style == 'plain' ? 0.82 : 0.52;
    final tp = TextPainter(
      text: TextSpan(
        text: '$n',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: short * digitFrac,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _NumberPainter old) =>
      old.n != n || old.style != style || old.color != color;
}
