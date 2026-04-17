import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 真正的透明窗口 — 桌面宠物必备
    self.isOpaque = false
    self.backgroundColor = .clear
    self.hasShadow = false
    self.level = .floating

    // 让 Flutter 视图也透明
    if let flutterView = flutterViewController.view as? NSView {
      flutterView.wantsLayer = true
      flutterView.layer?.backgroundColor = CGColor.clear
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
