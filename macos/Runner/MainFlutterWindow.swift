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
    if shouldLog(event) {
      NSLog(
        "SecondLoop key trace sendEvent type=%@ keyCode=%d chars=%@ charsIgnoring=%@ flags=%@ firstResponder=%@",
        String(describing: event.type),
        event.keyCode,
        event.characters ?? "",
        event.charactersIgnoringModifiers ?? "",
        String(describing: event.modifierFlags.intersection(.deviceIndependentFlagsMask)),
        firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
      )
    }

    if isCommandOnlyModifierEvent(event) {
      NSLog("SecondLoop key trace swallowed command-only flagsChanged event")
      return
    }

    super.sendEvent(event)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if shouldLog(event) {
      NSLog(
        "SecondLoop key trace performKeyEquivalent keyCode=%d chars=%@ charsIgnoring=%@ flags=%@",
        event.keyCode,
        event.characters ?? "",
        event.charactersIgnoringModifiers ?? "",
        String(describing: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
      )
    }
    return super.performKeyEquivalent(with: event)
  }

  @IBAction override func selectAll(_ sender: Any?) {
    NSLog(
      "SecondLoop key trace selectAll sender=%@ currentEvent=%@ firstResponder=%@",
      String(describing: sender),
      String(describing: NSApp.currentEvent),
      firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
    )
    super.selectAll(sender)
  }

  private func shouldLog(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags.contains(.command) {
      return true
    }
    return event.type == .flagsChanged && (event.keyCode == 54 || event.keyCode == 55)
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
