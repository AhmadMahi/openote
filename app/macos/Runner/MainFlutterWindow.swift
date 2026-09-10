import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The window's own chrome — close, minimise, zoom — stays exactly where
    // macOS puts it and never scrolls, because it is the title bar's, not the
    // page's. The bar itself is transparent and the content runs full-size
    // beneath it, so the traffic lights sit over the navigator card the way
    // they do in every modern Mac app. The title text is hidden (the app's
    // own breadcrumb says where you are); the window still reports it to the
    // Dock and Mission Control.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
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
    channel.setMethodCallHandler { [weak self] call, result in
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
        if let event = NSApp.currentEvent { window.performDrag(with: event) }
        result(nil)
      case "isFullScreen":
        result(window.styleMask.contains(.fullScreen))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
