import 'dart:math' as math;

import '../model/models.dart';
import 'arrow.dart';
import 'rectangle.dart';
import 'shape_snap.dart' show Offset2;

/// The shapes-palette stroke builders. Each turns a drag rectangle ([from] to
/// [to]) into pen strokes in the given colour, so a palette shape commits,
/// erases, lassoes and recolours exactly like a hand-drawn one — it reuses the
/// whole ink pipeline, the same way the arrow and rectangle tools already do.
///
/// The kinds the palette offers beyond arrow and rectangle: a straight line,
/// an ellipse, a triangle, a five-point star, and the two teaching marks a
/// green check and a red cross.
const shapeKinds = <String>[
  'check',
  'cross',
  'circle',
  'rectangle',
  'triangle',
  'diamond',
  'pentagon',
  'hexagon',
  'star',
  'line',
  'arrow',
  'double_arrow',
  'plus',
  'minus',
  'cloud',
];

List<Stroke> shapeStrokes(
  String kind, {
  required Offset2 from,
  required Offset2 to,
  required String colorHex,
  required double size,
}) {
  switch (kind) {
    case 'rectangle':
      return rectangleStrokes(
          from: from, to: to, colorHex: colorHex, size: size);
    case 'arrow':
      return arrowStrokes(from: from, to: to, colorHex: colorHex, size: size);
    case 'line':
      return _lineStrokes(from, to, colorHex, size);
    case 'circle':
      return _circleStrokes(from, to, colorHex, size);
    case 'triangle':
      return _triangleStrokes(from, to, colorHex, size);
    case 'star':
      return _starStrokes(from, to, colorHex, size);
    case 'check':
      return _checkStrokes(from, to, colorHex, size);
    case 'cross':
      return _crossStrokes(from, to, colorHex, size);
    case 'diamond':
      return _polygonStrokes(from, to, colorHex, size, sides: 4, rotation: 0);
    case 'pentagon':
      return _polygonStrokes(from, to, colorHex, size,
          sides: 5, rotation: -math.pi / 2);
    case 'hexagon':
      return _polygonStrokes(from, to, colorHex, size,
          sides: 6, rotation: -math.pi / 2);
    case 'double_arrow':
      return _doubleArrowStrokes(from, to, colorHex, size);
    case 'plus':
      return _plusStrokes(from, to, colorHex, size);
    case 'minus':
      return _minusStrokes(from, to, colorHex, size);
    case 'cloud':
      return _cloudStrokes(from, to, colorHex, size);
    default:
      return const [];
  }
}

// ── helpers ─────────────────────────────────────────────────────────────

Stroke _poly(List<Offset2> pts, String colorHex, double size) => Stroke(
      tool: 'pen',
      colorHex: colorHex,
      size: size,
      x: [for (final p in pts) p.x],
      y: [for (final p in pts) p.y],
      // Flat pressure: a placed shape is a drawn object, not a gesture.
      p: List<double>.filled(pts.length, 0.6),
      t: [for (var i = 0; i < pts.length; i++) i * 4],
    );

/// A straight segment, subdivided so the ink smoother has points to work with.
List<Offset2> _seg(Offset2 a, Offset2 b, [int n = 12]) => [
      for (var i = 0; i <= n; i++)
        Offset2(a.x + (b.x - a.x) * i / n, a.y + (b.y - a.y) * i / n)
    ];

List<Offset2> _chain(List<Offset2> corners, {bool close = false}) {
  final pts = <Offset2>[];
  final cs = close ? [...corners, corners.first] : corners;
  for (var i = 0; i < cs.length - 1; i++) {
    final seg = _seg(cs[i], cs[i + 1]);
    if (i > 0) seg.removeAt(0); // avoid duplicating the shared vertex
    pts.addAll(seg);
  }
  return pts;
}

({
  double l,
  double r,
  double t,
  double b,
  double w,
  double h,
  double cx,
  double cy
}) _rect(Offset2 from, Offset2 to) {
  final l = math.min(from.x, to.x), r = math.max(from.x, to.x);
  final t = math.min(from.y, to.y), b = math.max(from.y, to.y);
  return (
    l: l,
    r: r,
    t: t,
    b: b,
    w: r - l,
    h: b - t,
    cx: (l + r) / 2,
    cy: (t + b) / 2
  );
}

bool _tooSmall(Offset2 from, Offset2 to) {
  final q = _rect(from, to);
  return q.w < 2 && q.h < 2;
}

// ── shapes ──────────────────────────────────────────────────────────────

List<Stroke> _lineStrokes(Offset2 from, Offset2 to, String hex, double size) {
  if (math.sqrt(math.pow(to.x - from.x, 2) + math.pow(to.y - from.y, 2)) < 2) {
    return const [];
  }
  return [_poly(_seg(from, to), hex, size)];
}

List<Stroke> _circleStrokes(Offset2 from, Offset2 to, String hex, double size) {
  if (_tooSmall(from, to)) return const [];
  final q = _rect(from, to);
  final rx = q.w / 2, ry = q.h / 2;
  const steps = 48;
  final pts = [
    for (var i = 0; i <= steps; i++)
      Offset2(q.cx + rx * math.cos(i / steps * 2 * math.pi),
          q.cy + ry * math.sin(i / steps * 2 * math.pi))
  ];
  return [_poly(pts, hex, size)];
}

List<Stroke> _triangleStrokes(
    Offset2 from, Offset2 to, String hex, double size) {
  if (_tooSmall(from, to)) return const [];
  final q = _rect(from, to);
  final corners = [
    Offset2(q.cx, q.t),
    Offset2(q.r, q.b),
    Offset2(q.l, q.b),
  ];
  return [_poly(_chain(corners, close: true), hex, size)];
}

List<Stroke> _starStrokes(Offset2 from, Offset2 to, String hex, double size) {
  if (_tooSmall(from, to)) return const [];
  final q = _rect(from, to);
  final rOuter = math.min(q.w, q.h) / 2;
  final rInner = rOuter * 0.42;
  final verts = <Offset2>[
    for (var i = 0; i < 10; i++)
      () {
        final ang = -math.pi / 2 + i * math.pi / 5;
        final rad = i.isEven ? rOuter : rInner;
        return Offset2(q.cx + rad * math.cos(ang), q.cy + rad * math.sin(ang));
      }()
  ];
  return [_poly(_chain(verts, close: true), hex, size)];
}

List<Stroke> _checkStrokes(Offset2 from, Offset2 to, String hex, double size) {
  if (_tooSmall(from, to)) return const [];
  final q = _rect(from, to);
  // A tick: down into the valley, then up to the high right.
  final pts = [
    Offset2(q.l + q.w * 0.16, q.t + q.h * 0.55),
    Offset2(q.l + q.w * 0.40, q.b - q.h * 0.18),
    Offset2(q.r - q.w * 0.10, q.t + q.h * 0.18),
  ];
  return [_poly(_chain(pts), hex, size)];
}

List<Stroke> _crossStrokes(Offset2 from, Offset2 to, String hex, double size) {
  if (_tooSmall(from, to)) return const [];
  final q = _rect(from, to);
  final a = q.w * 0.16, bInset = q.h * 0.16;
  return [
    _poly(_seg(Offset2(q.l + a, q.t + bInset), Offset2(q.r - a, q.b - bInset)),
        hex, size),
    _poly(_seg(Offset2(q.r - a, q.t + bInset), Offset2(q.l + a, q.b - bInset)),
        hex, size),
  ];
}

List<Stroke> _polygonStrokes(Offset2 from, Offset2 to, String hex, double size,
    {required int sides, required double rotation}) {
  if (_tooSmall(from, to)) return const [];
  final q = _rect(from, to);
  final r = math.min(q.w, q.h) / 2;
  final verts = <Offset2>[
    for (var i = 0; i < sides; i++)
      () {
        final ang = rotation + i * 2 * math.pi / sides;
        return Offset2(q.cx + r * math.cos(ang), q.cy + r * math.sin(ang));
      }()
  ];
  return [_poly(_chain(verts, close: true), hex, size)];
}

List<Stroke> _doubleArrowStrokes(
    Offset2 from, Offset2 to, String hex, double size) {
  if (math.sqrt(math.pow(to.x - from.x, 2) + math.pow(to.y - from.y, 2)) < 2) {
    return const [];
  }
  final head = arrowStrokes(from: from, to: to, colorHex: hex, size: size);
  final tail = arrowStrokes(from: to, to: from, colorHex: hex, size: size);
  if (head.length < 3 || tail.length < 3) return head;
  // One shaft, a head at each end.
  return [head[0], head[1], head[2], tail[1], tail[2]];
}

List<Stroke> _plusStrokes(Offset2 from, Offset2 to, String hex, double size) {
  if (_tooSmall(from, to)) return const [];
  final q = _rect(from, to);
  final ix = q.w * 0.10, iy = q.h * 0.10;
  return [
    _poly(_seg(Offset2(q.l + ix, q.cy), Offset2(q.r - ix, q.cy)), hex, size),
    _poly(_seg(Offset2(q.cx, q.t + iy), Offset2(q.cx, q.b - iy)), hex, size),
  ];
}

List<Stroke> _minusStrokes(Offset2 from, Offset2 to, String hex, double size) {
  if (_tooSmall(from, to)) return const [];
  final q = _rect(from, to);
  final ix = q.w * 0.10;
  return [
    _poly(_seg(Offset2(q.l + ix, q.cy), Offset2(q.r - ix, q.cy)), hex, size)
  ];
}

/// A thought cloud: a lumpy closed curve, an ellipse whose radius is modulated
/// by a sine so it bulges into soft bumps the way a cartoon cloud does.
List<Stroke> _cloudStrokes(Offset2 from, Offset2 to, String hex, double size) {
  if (_tooSmall(from, to)) return const [];
  final q = _rect(from, to);
  final rx = q.w / 2, ry = q.h / 2;
  const steps = 96, bumps = 8;
  const amp = 0.13;
  final pts = <Offset2>[
    for (var i = 0; i <= steps; i++)
      () {
        final a = i / steps * 2 * math.pi;
        final m = 1 + amp * math.sin(bumps * a - math.pi / 2);
        return Offset2(
            q.cx + rx * m * math.cos(a), q.cy + ry * m * math.sin(a));
      }()
  ];
  return [_poly(pts, hex, size)];
}
