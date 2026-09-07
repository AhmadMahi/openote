import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/onote_theme.dart';

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
    this.radius = 16,
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
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: r,
            color: (dark ? OnoteColors.night0 : Colors.white)
                .withValues(alpha: dark ? .72 : .74),
            border: Border.all(
              color: (dark ? Colors.white : Colors.black)
                  .withValues(alpha: dark ? .10 : .07),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .40 : .16),
                blurRadius: 26,
                offset: const Offset(0, 10),
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
                      Colors.white.withValues(alpha: dark ? .22 : .75),
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
