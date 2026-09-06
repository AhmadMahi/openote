// Auto shapes (INK-10). The recogniser's contract has two halves, and the
// second one matters more than the first: it snaps what it is confident
// about, and it LEAVES ALONE what it is not. A recogniser that mangles a
// stroke it misread costs the user work they cannot get back except by
// undoing and drawing again.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/ink/shape_snap.dart';
import 'package:openote/model/models.dart';

Stroke strokeOf(List<(double, double)> pts) => Stroke(
      tool: 'pen',
      colorHex: '#000000',
      size: 2,
      x: [for (final p in pts) p.$1],
      y: [for (final p in pts) p.$2],
      p: [for (final _ in pts) 0.5],
    );

/// A shaky circle: a real one plus a wobble no hand avoids.
List<(double, double)> wobblyCircle(
    {double cx = 200, double cy = 200, double r = 80, int n = 60}) {
  final rnd = math.Random(7);
  return [
    for (var i = 0; i <= n; i++)
      (
        cx + (r + rnd.nextDouble() * 6 - 3) * math.cos(i / n * 2 * math.pi),
        cy + (r + rnd.nextDouble() * 6 - 3) * math.sin(i / n * 2 * math.pi),
      )
  ];
}

void main() {
  group('what it snaps', () {
    test('a wobbly circle becomes a round one', () {
      final out = ShapeSnap.snap(strokeOf(wobblyCircle()));
      expect(out, isNotNull, reason: 'a closed, cornerless loop is an ellipse');
      // Every point the same distance from the centre is what "round" means.
      final r = [
        for (var i = 0; i < out!.x.length; i++)
          math.sqrt(math.pow(out.x[i] - 200, 2) + math.pow(out.y[i] - 200, 2))
      ];
      final spread = r.reduce(math.max) - r.reduce(math.min);
      expect(spread, lessThan(2.0),
          reason: 'the wobble is gone, not merely reduced');
    });

    test('a shaky line becomes straight', () {
      final rnd = math.Random(3);
      final out = ShapeSnap.snap(strokeOf([
        for (var i = 0; i <= 30; i++)
          (100 + i * 6.0, 300 + rnd.nextDouble() * 4 - 2)
      ]));
      expect(out, isNotNull);
      final ys = out!.y;
      expect(ys.reduce(math.max) - ys.reduce(math.min), lessThan(1.0));
    });

    test('the snapped stroke keeps its identity, not just its shape', () {
      final s = strokeOf(wobblyCircle());
      final out = ShapeSnap.snap(s)!;
      expect(out.id, s.id, reason: 'same stroke, tidied — not a new one');
      expect(out.colorHex, s.colorHex);
      expect(out.size, s.size);
      expect(out.tool, s.tool);
    });
  });

  group('what it refuses to touch', () {
    test('a flick is left alone', () {
      expect(ShapeSnap.snap(strokeOf([(0, 0), (3, 3), (6, 5)])), isNull);
    });

    test('a tiny scribble is left alone', () {
      expect(
          ShapeSnap.snap(strokeOf([
            for (var i = 0; i < 20; i++) (i.toDouble(), (i % 3).toDouble())
          ])),
          isNull,
          reason: 'below the size floor it is a dot or a tick, not a shape');
    });

    test('handwriting is left alone', () {
      // An open, curvy, non-straight stroke — the shape of a written letter.
      final rnd = math.Random(11);
      final pts = [
        for (var i = 0; i < 40; i++)
          (
            100 + i * 4.0 + rnd.nextDouble() * 20,
            200 + math.sin(i / 3) * 40 + rnd.nextDouble() * 15,
          )
      ];
      expect(ShapeSnap.snap(strokeOf(pts)), isNull,
          reason: 'open and not straight means it is writing, and writing is '
              'the thing this must never rewrite');
    });
  });
}
