import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// The bridge the app's drawn window lights talk over (lib/ui/window_chrome.dart).
  private var chrome: FlutterMethodChannel?

  /// The most recent mouse-down, kept for `performDrag(with:)`: a drag has to
  /// be started from the event that began it, and by the time Dart asks, the
  /// current event is already a mouse-dragged.
  private var lastMouseDown: NSEvent?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The window's own chrome — close, minimise, zoom — stays exactly where
    // macOS puts it and never scrolls, because it is the title bar's, not the
    // page's. The bar itself is transparent and the content runs full-size
    // beneath it, so the app's controls sit where the lights sit in every
    // modern Mac app. The title text is hidden (the app's own breadcrumb says
    // where you are); the window still reports it to the Dock and Mission
    // Control.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    // Say so explicitly: the storyboard never did, and without it
    // `toggleFullScreen(_:)` has nothing to do.
    self.collectionBehavior.insert(.fullScreenPrimary)
    // Light, not black: in full screen the title bar is revealed on hover as
    // a strip over the content, and that strip shows the window's background.
    self.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1)

    // The app draws the three lights itself (lib/ui/window_chrome.dart) so
    // they can stay on screen in full screen, where macOS hides the title
    // bar. One set of lights, so the native ones are hidden; the channel
    // below is how the drawn ones do the real thing.
    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      self.standardWindowButton(kind)?.isHidden = true
    }

    let channel = FlutterMethodChannel(
      name: "slate/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    chrome = channel
    channel.setMethodCallHandler { [weak self] call, result in
      NSLog("slate/window: %@", call.method)
      guard let window = self else { result(nil); return }
      switch call.method {
      case "close":
        window.performClose(nil)
        result(nil)
      case "minimize":
        window.miniaturize(nil)
        result(nil)
      case "zoom":
        // The green light means full screen, as it does natively on click.
        window.toggleFullScreen(nil)
        result(nil)
      case "startDrag":
        if let down = window.lastMouseDown { window.performDrag(with: down) }
        result(nil)
      case "isFullScreen":
        result(window.styleMask.contains(.fullScreen))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  /// The title bar's own view still claims mouse-downs in the top strip even
  /// when it is transparent and drawing nothing, which is where the app's
  /// lights live. Mouse events landing there go to whatever the content view
  /// has under the pointer instead — the Flutter view, which dispatches them
  /// to the app — and the title bar keeps everything else.
  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .leftMouseDown:
      lastMouseDown = event
      if forwardToContent(event) { return }
    case .leftMouseUp, .leftMouseDragged:
      if forwardToContent(event) { return }
    default:
      break
    }
    super.sendEvent(event)
  }

  private static let titleStrip: CGFloat = 28

  private func forwardToContent(_ event: NSEvent) -> Bool {
    guard !styleMask.contains(.fullScreen), let content = contentView else { return false }
    let point = content.convert(event.locationInWindow, from: nil)
    // Content views are not flipped: the strip is the top `titleStrip` points.
    guard point.y >= content.bounds.height - MainFlutterWindow.titleStrip else { return false }
    guard let target = content.hitTest(point) else { return false }
    switch event.type {
    case .leftMouseDown: target.mouseDown(with: event)
    case .leftMouseUp: target.mouseUp(with: event)
    case .leftMouseDragged: target.mouseDragged(with: event)
    default: return false
    }
    return true
  }
}
