import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    if #available(macOS 13.0, *) {
      registerAudioCapture(with: flutterViewController.engine.binaryMessenger)
    }

    super.awakeFromNib()
  }
}
