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

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
