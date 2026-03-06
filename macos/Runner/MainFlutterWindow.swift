import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.configureMethodChannelsIfNeeded()
    }

    super.awakeFromNib()
  }

  override func sendEvent(_ event: NSEvent) {
    if isCommandOnlyModifierEvent(event) {
      return
    }

    super.sendEvent(event)
  }

  private func isCommandOnlyModifierEvent(_ event: NSEvent) -> Bool {
    guard event.type == .flagsChanged else {
      return false
    }

    guard event.keyCode == 54 || event.keyCode == 55 else {
      return false
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let nonCommandFlags: NSEvent.ModifierFlags = [
      .capsLock,
      .shift,
      .control,
      .option,
      .function,
    ]

    return flags.intersection(nonCommandFlags).isEmpty
  }
}
