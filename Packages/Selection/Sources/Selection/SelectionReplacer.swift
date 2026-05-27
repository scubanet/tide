import AppKit
import OSLog

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "selection")

/// Writes text back into the previous app's selection by swapping the
/// pasteboard, simulating ⌘V, and restoring the original clipboard.
public enum SelectionReplacer {
  /// Replaces the current frontmost app's selection with `text`, then
  /// restores the original clipboard contents after a short delay.
  /// Caller is responsible for first calling `NSApp.hide(nil)` or
  /// otherwise yielding focus before invoking this.
  public static func replaceSelection(with newText: String) {
    let pasteboard = NSPasteboard.general
    let oldContents = pasteboard.string(forType: .string)

    pasteboard.clearContents()
    pasteboard.setString(newText, forType: .string)

    let source = CGEventSource(stateID: .combinedSessionState)
    let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
    let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
    vDown?.flags = .maskCommand
    let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    vUp?.flags = .maskCommand
    let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

    cmdDown?.post(tap: .cghidEventTap)
    vDown?.post(tap: .cghidEventTap)
    vUp?.post(tap: .cghidEventTap)
    cmdUp?.post(tap: .cghidEventTap)

    log.debug("posted ⌘V with \(newText.count, privacy: .public) chars")

    // Restore original clipboard after the paste lands.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      pasteboard.clearContents()
      if let old = oldContents {
        pasteboard.setString(old, forType: .string)
      }
    }
  }
}
