import AppKit
import ApplicationServices
import OSLog

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "selection")

/// Reads the currently selected text from the frontmost application.
/// Two strategies, tried in order:
///   1. **Accessibility API.** Fast, no side-effects. Works in native
///      `NSText*` widgets (Mail.app, Notes, native text fields).
///   2. **Simulated ⌘C.** Slower (~80ms), briefly hijacks the clipboard,
///      but works in apps with custom text rendering — Spark, Slack,
///      Notion, Electron apps, browsers' web content.
/// The clipboard fallback restores the user's original clipboard
/// contents before returning, so the user shouldn't notice.
public enum SelectionReader {
  /// Best-effort read. Returns `nil` if both strategies fail (no
  /// permission, no selection, or unsupported app).
  public static func readFromFrontmostApp() -> SelectedText? {
    guard AXIsProcessTrusted() else {
      log.debug("not AX-trusted")
      return nil
    }
    guard let frontApp = NSWorkspace.shared.frontmostApplication else {
      log.debug("no frontmost app")
      return nil
    }

    if let viaAX = readViaAX(frontApp: frontApp) {
      log.debug("selection via AX (\(viaAX.text.count, privacy: .public) chars)")
      return viaAX
    }
    log.debug("AX miss — falling back to ⌘C")
    if let viaCopy = readViaClipboardCopy(frontApp: frontApp) {
      log.debug("selection via ⌘C (\(viaCopy.text.count, privacy: .public) chars)")
      return viaCopy
    }
    log.debug("no selection")
    return nil
  }

  // MARK: - Strategy 1: AX

  private static func readViaAX(frontApp: NSRunningApplication) -> SelectedText? {
    let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
    var focused: CFTypeRef?
    let focusStatus = AXUIElementCopyAttributeValue(
      appElement, kAXFocusedUIElementAttribute as CFString, &focused
    )
    guard focusStatus == .success, let focused = focused else { return nil }
    let focusedElement = focused as! AXUIElement
    var value: CFTypeRef?
    let valueStatus = AXUIElementCopyAttributeValue(
      focusedElement, kAXSelectedTextAttribute as CFString, &value
    )
    guard valueStatus == .success,
          let text = value as? String,
          !text.isEmpty else { return nil }
    return SelectedText(
      text: text,
      sourceAppBundleID: frontApp.bundleIdentifier ?? "",
      sourceAppName: frontApp.localizedName ?? ""
    )
  }

  // MARK: - Strategy 2: simulated ⌘C

  private static func readViaClipboardCopy(frontApp: NSRunningApplication) -> SelectedText? {
    let pasteboard = NSPasteboard.general
    let originalString = pasteboard.string(forType: .string)
    let originalChangeCount = pasteboard.changeCount

    sendCommandC()

    // Wait up to 200ms for the copy to land in the pasteboard.
    let deadline = Date().addingTimeInterval(0.2)
    while Date() < deadline && pasteboard.changeCount == originalChangeCount {
      Thread.sleep(forTimeInterval: 0.01)
    }

    let copied = pasteboard.string(forType: .string)

    // Restore original clipboard contents. We do this BEFORE returning
    // so the user's clipboard is intact whether or not we extracted text.
    pasteboard.clearContents()
    if let originalString {
      pasteboard.setString(originalString, forType: .string)
    }

    guard let text = copied,
          !text.isEmpty,
          text != originalString else {
      return nil
    }

    return SelectedText(
      text: text,
      sourceAppBundleID: frontApp.bundleIdentifier ?? "",
      sourceAppName: frontApp.localizedName ?? ""
    )
  }

  /// Posts a ⌘C key combination to the frontmost app via CGEvents.
  private static func sendCommandC() {
    let source = CGEventSource(stateID: .combinedSessionState)
    let cKeyCode: CGKeyCode = 0x08  // 'c'
    let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
    let cDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true)
    cDown?.flags = .maskCommand
    let cUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
    cUp?.flags = .maskCommand
    let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

    cmdDown?.post(tap: .cghidEventTap)
    cDown?.post(tap: .cghidEventTap)
    cUp?.post(tap: .cghidEventTap)
    cmdUp?.post(tap: .cghidEventTap)
  }

  /// Prompt macOS to ask the user for Accessibility permission. Safe to
  /// call repeatedly — no dialog appears if permission is already
  /// granted or already explicitly denied.
  ///
  /// We hard-code the option key as a string literal instead of
  /// referencing `kAXTrustedCheckOptionPrompt`. Under Swift 6 strict
  /// concurrency that CFString constant is flagged as shared mutable
  /// state and won't compile. The constant's documented value never
  /// changes — `"AXTrustedCheckOptionPrompt"`.
  public static func requestAccessibilityPermission() {
    let opts: NSDictionary = [
      "AXTrustedCheckOptionPrompt" as NSString: true
    ]
    _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
  }
}
