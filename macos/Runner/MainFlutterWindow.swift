import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.minSize = NSSize(width: 960, height: 680)
    if let screen = NSScreen.main {
      let sf = screen.visibleFrame
      let w = min(max(self.frame.width, 1200), sf.width)
      let h = min(max(self.frame.height, 760), sf.height)
      let x = sf.origin.x + (sf.width - w) / 2
      let y = sf.origin.y + (sf.height - h) / 2
      self.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
