import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/onote_theme.dart';
import '../theme/tokens.dart';

/// A translucent, blurred panel — the material floating surfaces are made of.
///
/// Used only for things that sit OVER the page: the focus palette, dialogs,
/// popovers. Glass reads as glass when there is something behind it to see;
/// on the command bar, which has the window frame behind it and text on it,
/// the same treatment costs legibility and buys nothing.
///
/// Three layers, and each is doing a job:
///  * the **blur** is what makes it glass rather than a tint;
///  * the **fill** is deliberately not fully transparent — text on pure blur
///    fails contrast the moment a dark drawing passes underneath;
///  * the **hairline** along the top edge is the specular highlight that
///    stops the panel reading as a flat rectangle. Light from above, so it is
///    on the top edge only.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    required this.dark,
    this.radius = OnoteRadius.xl,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final bool dark;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: r,
            color: (dark ? OnoteColors.night50 : OnoteColors.paper50)
                .withValues(alpha: dark ? .70 : .72),
            border: Border.all(
              color: (dark ? Colors.white : Colors.black)
                  .withValues(alpha: dark ? .12 : .06),
            ),
            // Two shadows: a tight one that seats the panel and a wide soft
            // one that says how far above the page it floats.
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .30 : .08),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .45 : .16),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Stack(children: [
            child,
            // The highlight, drawn over the content rather than under it, so
            // it stays on the glass surface instead of behind whatever the
            // panel happens to contain.
            Positioned(
              left: radius,
              right: radius,
              top: 0,
              child: IgnorePointer(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: dark ? .26 : .9),
                      Colors.white.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Which edge of a bar carries its hairline.
enum ChromeEdge { top, bottom, none }

/// The glass the floating chrome is made of — the sheet the command bar, the
/// object row and the status bar sit on.
///
/// Real glass this time, because there is now something behind it: the canvas
/// is laid out under the bars (see [CanvasController.insets]) and the page
/// scrolls beneath them, the way content passes under a macOS toolbar. Three
/// things make it read as a material and not a tinted rectangle:
///  * the **blur**, with a little added saturation so what shows through
///    keeps its colour instead of greying out;
///  * a **fill** that is translucent but not thin — legibility of the text on
///    the bar comes first, and a dark drawing passing underneath must not
///    swallow a label;
///  * the **hairlines**: a specular line along the top where the light lands
///    and one on the edge that meets the page.
///
/// One sheet per stack of bars, not one per bar — a backdrop filter is paid
/// for per instance, and the bars share one.
class GlassSheet extends StatelessWidget {
  const GlassSheet({
    super.key,
    required this.child,
    this.edge = ChromeEdge.bottom,
  });

  final Widget child;

  /// The edge that meets the page: `bottom` for the top stack, `top` for the
  /// status bar.
  final ChromeEdge edge;

  /// Vibrancy: a touch more saturation on what shows through the blur.
  static const _saturate = ColorFilter.matrix(<double>[
    0.8967, 0.1533, -0.0500, 0, 0, //
    -0.1033, 1.1533, -0.0500, 0, 0, //
    -0.1033, 0.1533, 0.9500, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final side = BorderSide(color: s.border.withValues(alpha: dark ? .9 : .8));
    // The chrome role, so the accent's wash reaches the glass too.
    final tint = s.chrome;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: ui.ImageFilter.blur(
              sigmaX: 24, sigmaY: 24, tileMode: TileMode.mirror),
          inner: _saturate,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tint.withValues(alpha: dark ? .66 : .64),
                tint.withValues(alpha: dark ? .58 : .56),
              ],
            ),
            border: Border(
              top: edge == ChromeEdge.top ? side : BorderSide.none,
              bottom: edge == ChromeEdge.bottom ? side : BorderSide.none,
            ),
          ),
          child: Stack(fit: StackFit.passthrough, children: [
            child,
            // The specular edge — light from above.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: dark ? .07 : .85),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One bar within a [GlassSheet]: the command bar, the object row, the status
/// bar. It paints no material of its own — the sheet does that — only what
/// distinguishes it from its neighbours: an optional inset tint and a hairline
/// on the edge that meets the bar above or below.
///
/// Used on its own (tests, a bar outside any sheet) it is simply transparent,
/// which is the right answer there too.
class ChromeBar extends StatelessWidget {
  const ChromeBar({
    super.key,
    required this.child,
    this.edge = ChromeEdge.none,
    this.inset = false,
    this.height,
  });

  final Widget child;
  final ChromeEdge edge;

  /// Tint with the `chrome2` role — a band that sits *within* the chrome
  /// rather than being the chrome, like the object row.
  final bool inset;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final side = BorderSide(color: s.border.withValues(alpha: .7));
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: inset ? s.chrome2.withValues(alpha: .55) : null,
        border: Border(
          top: edge == ChromeEdge.top ? side : BorderSide.none,
          bottom: edge == ChromeEdge.bottom ? side : BorderSide.none,
        ),
      ),
      child: child,
    );
  }
}
