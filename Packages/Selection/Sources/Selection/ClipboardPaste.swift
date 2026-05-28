import AppKit
import OSLog

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "selection")

/// Posts a synthetic ⌘V to the frontmost application after dropping
/// `text` on the pasteboard, then restores the prior clipboard 400ms
/// later. Used by both `SelectionReplacer` (replacing the user's previous
/// selection in the source app) and the dictation `TextInjector`
/// (inserting at the cursor).
public enum ClipboardPaste {
  /// Drop `text` on the pasteboard, post ⌘V, then restore whatever
  /// was on the pasteboard before. Returns immediately; the restore
  /// runs on the main queue after 400ms.
  public static func paste(_ text: String) {
    let pasteboard = NSPasteboard.general
    let oldContents = pasteboard.string(forType: .string)
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    Self.postCommandV()
    log.debug("ClipboardPaste posted ⌘V with \(text.count, privacy: .public) chars")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      pasteboard.clearContents()
      if let old = oldContents { pasteboard.setString(old, forType: .string) }
    }
  }

  private static func postCommandV() {
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
  }
}
