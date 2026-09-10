/// The window's own controls, drawn by the app — macOS only.
///
/// **Why drawn.** macOS hides the title bar in full screen, traffic lights
/// included, and shows it again only while the pointer rests at the top edge.
/// The owner wants the three lights on screen in full screen as well, except
/// while drawing in focus mode; no native window can do that, so the app draws
/// them itself over the navigator card and asks the window to do the real
/// thing when one is clicked: close, minimise, enter or leave full screen. The
/// native buttons are hidden in `MainFlutterWindow.swift` so there is one set
/// of lights, never two.
///
/// Focus mode hides them with everything else, deliberately: that is the one
/// state where the window frame is meant to be gone.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// The bridge to `MainFlutterWindow.swift`.
abstract final class WindowChrome {
  static const _channel = MethodChannel('slate/window');

  static bool get supported => Platform.isMacOS;

  static Future<void> close() => _call('close');
  static Future<void> minimize() => _call('minimize');

  /// The green light: full screen, as macOS itself does on click.
  static Future<void> zoom() => _call('zoom');

  /// Begin moving the window with the current mouse drag. The title bar is
  /// transparent and full-size content sits under it, so the app's own bars
  /// have to offer the drag the bar used to.
  static Future<void> startDrag() => _call('startDrag');

  static Future<void> _call(String method) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Tests, or a host without the channel: nothing to do.
    } catch (e) {
      // Said out loud rather than swallowed: a light that does nothing is a
      // bug someone has to be able to see in the log.
      // ignore: avoid_print
      print('window chrome: $method failed: $e');
    }
  }
}

/// The three lights, at the size and spacing macOS draws them (12pt discs,
/// 8pt apart). Glyphs appear on hover, as they do natively.
class WindowLights extends StatefulWidget {
  const WindowLights({super.key});

  @override
  State<WindowLights> createState() => _WindowLightsState();
}

class _WindowLightsState extends State<WindowLights> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _Light(
          color: const Color(0xFFFF5F57),
          rim: const Color(0xFFE0443E),
          glyph: Icons.close,
          tooltip: 'Close',
          showGlyph: _hover,
          onTap: WindowChrome.close,
        ),
        const SizedBox(width: OnoteSpace.x4),
        _Light(
          color: const Color(0xFFFEBC2E),
          rim: const Color(0xFFDEA123),
          glyph: Icons.remove,
          tooltip: 'Minimise',
          showGlyph: _hover,
          onTap: WindowChrome.minimize,
        ),
        const SizedBox(width: OnoteSpace.x4),
        _Light(
          color: const Color(0xFF28C840),
          rim: const Color(0xFF1AAB29),
          glyph: Icons.unfold_more,
          glyphTurn: .125, // the two arrows sit on the diagonal, as macOS's
          tooltip: 'Full screen',
          showGlyph: _hover,
          onTap: WindowChrome.zoom,
        ),
      ]),
    );
  }
}

class _Light extends StatelessWidget {
  const _Light({
    required this.color,
    required this.rim,
    required this.glyph,
    required this.tooltip,
    required this.showGlyph,
    required this.onTap,
    this.glyphTurn = 0,
  });
  final Color color;
  final Color rim;
  final IconData glyph;
  final String tooltip;
  final bool showGlyph;
  final VoidCallback onTap;
  final double glyphTurn;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 900),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: rim.withValues(alpha: .6), width: .5),
          ),
          child: showGlyph
              ? RotationTransition(
                  turns: AlwaysStoppedAnimation(glyphTurn),
                  child: Icon(glyph,
                      size: 9, color: Colors.black.withValues(alpha: .55)),
                )
              : null,
        ),
      ),
    );
  }
}

/// A region that moves the window when dragged — what a title bar does,
/// offered by the bars that took its place. Taps still reach the controls
/// inside it; only a drag that starts on empty bar is taken. (No double-click
/// zoom: a double-tap recogniser in the arena would hold every single tap on
/// the bar's buttons until it had timed out.)
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!WindowChrome.supported) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => WindowChrome.startDrag(),
      child: child,
    );
  }
}
