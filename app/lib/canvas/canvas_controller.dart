import 'package:flutter/scheduler.dart' show Ticker, TickerProvider;
import 'package:flutter/widgets.dart';

/// First-party pan/zoom (Tech Eval §7.3: own transform, no InteractiveViewer).
/// Maps between screen space and page space. The model is unbounded, but
/// panning is clamped to the page origin (`clampToPage`) so the page can't be
/// lost off-screen (CANVAS-1 v0.3).
class CanvasController extends ChangeNotifier {
  double scale = 1.0;
  Offset offset = Offset.zero; // page-space origin's screen position

  static const minScale = 0.15;
  static const maxScale = 8.0;

  Matrix4 get matrix => Matrix4.identity()
    ..translate(offset.dx, offset.dy)
    ..scale(scale);

  Offset screenToPage(Offset screen) => (screen - offset) / scale;
  Offset pageToScreen(Offset page) => page * scale + offset;

  void panBy(Offset delta) {
    // Horizontal movement is dropped outright when the page already fits,
    // rather than applied and then clamped away: a trackpad's sideways
    // component is never exactly zero, so "apply then clamp" spent every
    // vertical scroll fighting a horizontal one.
    offset += canPanHorizontally ? delta : Offset(0, delta.dy);
    clampToPage();
    notifyListeners();
  }

  /// Zoom keeping the given screen point fixed (style guide §8.2).
  void zoomAt(Offset screenFocal, double factor) {
    final newScale = (scale * factor).clamp(minScale, maxScale);
    final pageFocal = screenToPage(screenFocal);
    scale = newScale;
    offset = screenFocal - pageFocal * scale;
    clampToPage();
    notifyListeners();
  }

  /// Restore an exact view (used by PDF export).
  void jumpTo(double s, Offset o) {
    scale = s;
    offset = o;
    notifyListeners();
  }

  void reset() {
    scale = 1.0;
    offset = Offset.zero; // clampToPage centres it if it fits
    clampToPage();
    notifyListeners();
  }

  /// Last known viewport size (set by the canvas widget each layout).
  Size viewport = Size.zero;

  /// Current page-surface size in page coords (set by the canvas each build);
  /// used to clamp panning so the page can't be lost (CANVAS-1 v0.3).
  Size? pageSize;

  /// Keep the page in view, and CENTRE it horizontally when it is narrower
  /// than the window.
  ///
  /// It used to pin top-left on both axes, so a page narrower than the window
  /// sat hard against the left edge with a band of desk down the right — and
  /// because zoom re-clamps, zooming out walked the page leftwards instead of
  /// shrinking it in place. Horizontally that is wrong for a document: a
  /// sheet you are writing on belongs in the middle of the window, and
  /// zooming should happen around the middle of what you are looking at.
  ///
  /// VERTICALLY it still pins to the top. A page grows downwards and you read
  /// it from the top; centring a short page would float it in the middle of
  /// the window and move the first line every time the content got longer.
  void clampToPage() {
    final ps = pageSize;
    if (ps == null || viewport == Size.zero) return;
    final wPx = ps.width * scale;
    offset = Offset(
      // Fits: centred, and there is nowhere to scroll to. Overflows: free to
      // pan, but never past an edge.
      wPx <= viewport.width
          ? (viewport.width - wPx) / 2
          : offset.dx.clamp(viewport.width - wPx, 0.0),
      () {
        final hPx = ps.height * scale;
        return hPx <= viewport.height ? 0.0 : offset.dy.clamp(viewport.height - hPx, 0.0);
      }(),
    );
  }

  // ── Momentum (CANVAS-12) ─────────────────────────────────────────────
  //
  // A flick used to stop the instant the fingers left the trackpad, which
  // reads as the page being stuck to the glass. Every other scrolling surface
  // on the machine carries on and eases out, and the eye notices the absence
  // long before anyone can name it.
  //
  // Deliberately hand-rolled rather than borrowed from `Scrollable`: this
  // canvas is a transform, not a viewport of a list, and adopting Flutter's
  // physics would mean adopting its scroll model for two axes it does not own.
  // The decay is the standard exponential one — velocity × friction per frame
  // — stopped at a pixel a frame, which is below the point anything is
  // visibly still moving.

  /// Pixels per frame, decaying. Null when nothing is gliding.
  Offset? _glide;
  Ticker? _ticker;

  /// How much of the velocity survives each frame. 0.92 at 60fps is ~0.3s of
  /// visible travel: long enough to feel like release, short enough that a
  /// deliberate scroll still lands where it was aimed.
  static const _friction = 0.92;
  static const _stopBelow = 0.4;

  /// Hand [velocity] (pixels per frame) to the glide. Called on the last
  /// pointer movement of a scroll or a drag-pan.
  void fling(Offset velocity, TickerProvider vsync) {
    if (velocity.distance < 1) return;
    _glide = velocity;
    _ticker ??= vsync.createTicker((_) => _step());
    if (!_ticker!.isActive) _ticker!.start();
  }

  /// Kill any glide in progress. Anything that TOUCHES the page must call
  /// this first — a stroke that begins while the page is still moving would
  /// be drawn across a page sliding underneath it.
  void stopGlide() {
    _glide = null;
    if (_ticker?.isActive ?? false) _ticker!.stop();
  }

  void _step() {
    final v = _glide;
    if (v == null) {
      _ticker?.stop();
      return;
    }
    panBy(v);
    final next = v * _friction;
    if (next.distance < _stopBelow) {
      stopGlide();
      return;
    }
    _glide = next;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  /// Whether the page is wider than the window, which is the only state in
  /// which horizontal panning means anything. Everything that pans reads this
  /// so a sideways trackpad flick cannot nudge a page that already fits — it
  /// would move a page that has nowhere to go and then snap it back.
  bool get canPanHorizontally {
    final ps = pageSize;
    if (ps == null || viewport == Size.zero) return false;
    return ps.width * scale > viewport.width + 0.5;
  }

  /// Initial view: page anchored top-left, filling the window (the page is at
  /// least viewport-wide, so no backdrop shows in normal use). Zooming out
  /// later reveals the page bounds — "a page that can become a canvas."
  void centerPage() {
    scale = 1.0;
    offset = Offset.zero;
    clampToPage();
    notifyListeners();
  }

  /// Fit [contentWidth] page-px to the viewport width, anchored top-left. Only
  /// zooms OUT (never past 100%), so a narrow page keeps its natural size while
  /// a wide imported page reveals its full width — including images placed to
  /// the right of the text at their original OneNote offsets, which otherwise
  /// sit off-screen at 100%. Vertical position stays at the top (scroll down
  /// for the rest), so text stays readable rather than shrinking to fit height.
  void fitWidth(double contentWidth) {
    if (viewport == Size.zero || contentWidth <= 0) {
      centerPage();
      return;
    }
    const pad = 24.0;
    final needed = contentWidth + pad;
    scale = needed <= viewport.width
        ? 1.0
        : (viewport.width / needed).clamp(minScale, 1.0);
    offset = Offset.zero;
    clampToPage();
    notifyListeners();
  }

  /// Scale so [contentWidth] page-px exactly spans the viewport width.
  ///
  /// The difference from [fitWidth] is the direction it is allowed to move:
  /// `fitWidth` only ever zooms OUT and stops at 100%, which is right for
  /// opening an imported page (never magnify somebody's notes at them). This
  /// is the deliberate "make the page fill the window" action, so it zooms IN
  /// as well — on a 1470px window an A4 sheet at 100% leaves a third of the
  /// screen as desk, and stopping at 100% would silently do nothing.
  void fillWidth(double contentWidth) {
    if (viewport == Size.zero || contentWidth <= 0) {
      centerPage();
      return;
    }
    // EXACTLY the window width, with no breathing room.
    //
    // A 16px pad each side was "tidier" and it is what left a sliver to
    // scroll to: the page then ends 32px short of the window, `clampToPage`
    // centres it, and dragging one way finds slack the other. Fit means fit.
    scale = (viewport.width / contentWidth).clamp(minScale, maxScale);
    offset = Offset.zero; // clampToPage puts it flush
    clampToPage();
    notifyListeners();
  }

  /// Put page-space Y at the top of the viewport, leaving X alone.
  ///
  /// Distinct from [centerOn]: jumping to a sheet is a *scroll*, and centring
  /// a sheet's top would hang half a viewport of the sheet before it above
  /// the fold — you would land looking at the end of the previous page.
  void scrollToPageY(double pageY) {
    offset = Offset(offset.dx, -pageY * scale);
    clampToPage();
    notifyListeners();
  }

  /// Center a page-space point in the viewport (find, navigation).
  void centerOn(Offset pagePoint) {
    offset = Offset(viewport.width / 2, viewport.height / 2) - pagePoint * scale;
    clampToPage();
    notifyListeners();
  }

  /// Zoom around the middle of the window.
  ///
  /// The vertical focal point is the centre so the line you are looking at
  /// stays put; the horizontal one only matters once the page is wider than
  /// the window, since [clampToPage] centres it otherwise.
  void setZoom(double newScale) {
    zoomAt(Offset(viewport.width / 2, viewport.height / 2), newScale / scale);
  }

  /// Zoom-to-fit a page-space rectangle (style guide §8.2).
  void fitTo(Rect pageBounds) {
    if (viewport == Size.zero || pageBounds.isEmpty) {
      reset();
      return;
    }
    const pad = 48.0;
    final sx = (viewport.width - pad * 2) / pageBounds.width;
    final sy = (viewport.height - pad * 2) / pageBounds.height;
    scale = (sx < sy ? sx : sy).clamp(minScale, maxScale);
    offset = Offset(
      (viewport.width - pageBounds.width * scale) / 2 - pageBounds.left * scale,
      (viewport.height - pageBounds.height * scale) / 2 - pageBounds.top * scale,
    );
    notifyListeners();
  }
}
