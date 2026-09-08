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

/// Which edge of a [ChromeBar] carries its hairline — the side that meets
/// the page.
enum ChromeEdge { top, bottom, none }

/// The material the fixed chrome is made of: command bar, status bar, the
/// bands between them.
///
/// Not glass. Glass needs something behind it to blur, and the only thing
/// behind the command bar is the window frame — a blur there costs a compositor
/// pass per frame and shows nothing for it. What *does* make a bar read as a
/// material rather than a filled rectangle is light: a faint gradient so the
/// surface is not perfectly flat, a specular hairline along the top where the
/// light lands, and one hairline on the edge that meets the page. Every bar in
/// the app is built from this, so every bar agrees.
class ChromeBar extends StatelessWidget {
  const ChromeBar({
    super.key,
    required this.child,
    this.edge = ChromeEdge.bottom,
    this.inset = false,
    this.height,
  });

  final Widget child;
  final ChromeEdge edge;

  /// Use the `chrome2` role — a band that sits *within* the chrome rather
  /// than being the chrome, like the object row.
  final bool inset;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = inset ? s.chrome2 : s.chrome;
    final side = BorderSide(color: s.border);
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(base, Colors.white, dark ? .02 : .5)!,
            base,
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
              color: Colors.white.withValues(alpha: dark ? .05 : .8),
            ),
          ),
        ),
      ]),
    );
  }
}
