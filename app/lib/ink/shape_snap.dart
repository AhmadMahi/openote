import 'dart:math' as math;

import '../model/models.dart';

/// Auto shapes: turn a hand-drawn stroke into the shape it was meant to be.
///
/// OneNote and Notability both do this and it is the single cheapest way to
/// make a diagram look deliberate — nobody draws a clean circle freehand with
/// a mouse, and redrawing it four times is the usual alternative.
///
/// The recogniser is intentionally small and explainable. It answers three
/// questions in order, and each is a property of the stroke a person could
/// check by eye:
///
///  1. Is it CLOSED? (do the two ends nearly meet, relative to its size)
///  2. If open — is it STRAIGHT? (do the points hug the line between the ends)
///  3. If closed — how many CORNERS does the turning have? 0 → ellipse,
///     3 → triangle, 4 → rectangle.
///
/// Anything it is not confident about is left exactly as drawn. That is the
/// important half of the contract: a recogniser that mangles a stroke it
/// misread is worse than one that does nothing, because the user loses work
/// they cannot get back except by undoing and drawing again.
class ShapeSnap {
  /// Ends closer than this fraction of the stroke's size count as "joined".
  static const _closeFrac = 0.28;

  /// A straight line's points stay within this fraction of its length of the
  /// straight line between its ends.
  static const _straightFrac = 0.07;

  /// A turn sharper than this is a corner. ~55°, comfortably above the
  /// wobble of a hand-drawn arc and below a real corner's 90°.
  static const _cornerAngle = 0.95;

  /// The snapped stroke, or null to keep what was drawn.
  ///
  /// [s] is not modified; the caller decides whether to take the result.
  static Stroke? snap(Stroke s) {
    final n = s.x.length;
    if (n < 8) return null; // a flick is not a shape

    final pts = [for (var i = 0; i < n; i++) Offset2(s.x[i], s.y[i])];
    final minX = pts.map((p) => p.x).reduce(math.min);
    final maxX = pts.map((p) => p.x).reduce(math.max);
    final minY = pts.map((p) => p.y).reduce(math.min);
    final maxY = pts.map((p) => p.y).reduce(math.max);
    final w = maxX - minX, h = maxY - minY;
    final size = math.max(w, h);
    // Too small to be anything but a dot or a tick.
    if (size < 24) return null;

    final gap = _dist(pts.first, pts.last);
    final closed = gap < size * _closeFrac;

    if (!closed) {
      return _isStraight(pts) ? _line(s, pts.first, pts.last) : null;
    }

    final corners = _corners(pts);
    return switch (corners.length) {
      0 || 1 => _ellipse(s, minX, minY, w, h),
      3 => _polygon(s, corners),
      4 => _rect(s, minX, minY, w, h),
      _ => null,
    };
  }

  static double _dist(Offset2 a, Offset2 b) =>
      math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

  /// Every point within [_straightFrac] of the chord, measured against the
  /// chord's own length so a long line is allowed a proportional wobble.
  static bool _isStraight(List<Offset2> pts) {
    final a = pts.first, b = pts.last;
    final len = _dist(a, b);
    if (len < 24) return false;
    final tol = len * _straightFrac;
    final dx = b.x - a.x, dy = b.y - a.y;
    for (final p in pts) {
      // |cross product| / |chord| is the perpendicular distance.
      final d = ((p.x - a.x) * dy - (p.y - a.y) * dx).abs() / len;
      if (d > tol) return false;
    }
    return true;
  }

  /// Corner points, found by walking the stroke in fixed-length steps and
  /// measuring how far the direction turns at each.
  ///
  /// Fixed-length steps rather than every sample: sample density depends on
  /// how fast the hand moved, so consecutive raw points near a slow corner
  /// are millimetres apart and their angles are noise.
  static List<Offset2> _corners(List<Offset2> pts) {
    final resampled = _resample(pts, 32);
    final out = <Offset2>[];
    for (var i = 1; i < resampled.length - 1; i++) {
      final a = resampled[i - 1], b = resampled[i], c = resampled[i + 1];
      final a1 = math.atan2(b.y - a.y, b.x - a.x);
      final a2 = math.atan2(c.y - b.y, c.x - b.x);
      var turn = (a2 - a1).abs();
      if (turn > math.pi) turn = 2 * math.pi - turn;
      if (turn > _cornerAngle) {
        // One corner, not three: a real corner spans a couple of steps.
        if (out.isEmpty || _dist(out.last, b) > 20) out.add(b);
      }
    }
    return out;
  }

  /// [count] points spaced evenly along the path by ARC LENGTH.
  static List<Offset2> _resample(List<Offset2> pts, int count) {
    var total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      total += _dist(pts[i - 1], pts[i]);
    }
    if (total <= 0) return pts;
    final step = total / (count - 1);
    final out = <Offset2>[pts.first];
    var acc = 0.0;
    for (var i = 1; i < pts.length; i++) {
      var seg = _dist(pts[i - 1], pts[i]);
      if (seg <= 0) continue;
      while (acc + seg >= step && out.length < count) {
        final t = (step - acc) / seg;
        final nx = pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t;
        final ny = pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t;
        out.add(Offset2(nx, ny));
        // Continue from the point just emitted.
        seg = _dist(out.last, pts[i]);
        acc = 0;
      }
      acc += seg;
    }
    if (out.length < count) out.add(pts.last);
    return out;
  }

  // ── Builders ─────────────────────────────────────────────────────────
  //
  // Each returns a stroke with the SAME id, tool, colour, size and opacity —
  // only the geometry is replaced. Pressure is flattened to a constant: a
  // snapped shape is a drawn object, and carrying the speed wobble of the
  // hand that sketched it into a perfect circle looks like a mistake.

  static Stroke _shaped(Stroke s, List<Offset2> pts) => Stroke(
        id: s.id,
        tool: s.tool,
        colorHex: s.colorHex,
        size: s.size,
        opacity: s.opacity,
        x: [for (final p in pts) p.x],
        y: [for (final p in pts) p.y],
        p: List<double>.filled(pts.length, 0.6),
        t: [for (var i = 0; i < pts.length; i++) i * 4],
      );

  static Stroke _line(Stroke s, Offset2 a, Offset2 b) =>
      _shaped(s, [for (var i = 0; i <= 16; i++) _lerp(a, b, i / 16)]);

  static Offset2 _lerp(Offset2 a, Offset2 b, double t) =>
      Offset2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);

  static Stroke _ellipse(Stroke s, double x, double y, double w, double h) {
    final cx = x + w / 2, cy = y + h / 2, rx = w / 2, ry = h / 2;
    const steps = 48;
    return _shaped(s, [
      for (var i = 0; i <= steps; i++)
        Offset2(cx + rx * math.cos(i / steps * 2 * math.pi),
            cy + ry * math.sin(i / steps * 2 * math.pi)),
    ]);
  }

  static Stroke _rect(Stroke s, double x, double y, double w, double h) {
    final corners = [
      Offset2(x, y),
      Offset2(x + w, y),
      Offset2(x + w, y + h),
      Offset2(x, y + h),
    ];
    return _polygon(s, corners);
  }

  /// A closed polygon through [corners], with each edge subdivided so the
  /// renderer's smoothing has points to work with.
  static Stroke _polygon(Stroke s, List<Offset2> corners) {
    final pts = <Offset2>[];
    for (var i = 0; i < corners.length; i++) {
      final a = corners[i], b = corners[(i + 1) % corners.length];
      for (var k = 0; k < 8; k++) {
        pts.add(_lerp(a, b, k / 8));
      }
    }
    pts.add(corners.first); // close it
    return _shaped(s, pts);
  }
}

/// A plain (x, y) pair, so this file needs nothing from the widget layer.
class Offset2 {
  const Offset2(this.x, this.y);
  final double x;
  final double y;
}
