import AppKit
import ApplicationServices
import Foundation
import OSLog
import UserNotifications

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "selection")

/// Inserts a string at the cursor of the frontmost (non-Tide) app.
///
/// **Strategy choice — Clipboard first, AX as fallback.**
/// Earlier iterations tried AX-Insert first and fell back to clipboard,
/// but the AX path silently lies in non-AppKit-native apps: Spark,
/// Slack, Notion-web, Discord, VS Code — anywhere there's a WKWebView
/// or Electron host — happily accept `AXUIElementSetAttributeValue`
/// with success, then never actually insert the text. Result is a
/// no-op the user notices but Tide reports as success. SuperWhisper
/// and WisprFlow go clipboard-first for the same reason; we follow
/// suit.
///
/// 1. **Clipboard-Paste** (default for any non-Tide frontmost app):
///    drop `text` on the pasteboard and post a synthetic ⌘V via
///    `ClipboardPaste.paste`. The user pre-clicked into a text-field
///    of the frontmost app; the ⌘V lands there. Works for AppKit,
///    Electron, WKWebView, terminals — anything that accepts ⌘V.
/// 2. **AX-Insert** (fallback when Tide itself is the frontmost app,
///    so a ⌘V would land in our own panel): try
///    `kAXSelectedTextAttribute` then `kAXValueAttribute` on the
///    focused element. In Tide's own panel this works because the
///    SwiftUI text field cooperates with AX. Returns `.axInsert`
///    when the AX path succeeded.
/// 3. **Pasteboard-only fallback** (no frontmost app, AX failed, or
///    target blocks ⌘V — e.g. clicked on the Desktop): drop the text
///    on the pasteboard and post a User Notification "Diktat in
///    Zwischenablage — ⌘V drücken". If notification authorization is
///    denied we silently keep the pasteboard set and log a warning.
public enum TextInjector {
  public enum Result: Equatable, Sendable {
    /// Strategy 1 succeeded: the focused AX element accepted our text.
    case axInsert
    /// Strategy 2 succeeded: we posted ⌘V to a non-Tide frontmost app.
    case clipboardPaste
    /// Strategy 3: pasteboard-only fallback (with optional notification).
    case pasteboardOnly
    /// Input was empty/whitespace-only after trimming. No clipboard
    /// mutation, no notification.
    case skippedEmpty
  }

  /// Test seam — overridable in unit tests. Default reads from
  /// `NSWorkspace.frontmostApplication`. Tests substitute their own
  /// closure to simulate "Tide is frontmost" vs. "another app is
  /// frontmost" without poking at the real `NSWorkspace`.
  ///
  /// Marked `nonisolated(unsafe)` to satisfy Swift 6 strict
  /// concurrency: the closure is only ever read/written from the
  /// main actor (the `insert(_:)` entry point is `@MainActor`-bound
  /// and tests run on the main thread under `@MainActor` XCTestCases),
  /// so the lack of a lock is fine in practice.
  nonisolated(unsafe) static var _frontmostBundleID: () -> String? = {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier
  }

  /// Test seam — the PID of the frontmost app, used by the AX
  /// strategy. Default reads from
  /// `NSWorkspace.frontmostApplication.processIdentifier`. See
  /// `_frontmostBundleID` for the `nonisolated(unsafe)` rationale.
  nonisolated(unsafe) static var _frontmostPID: () -> pid_t? = {
    NSWorkspace.shared.frontmostApplication?.processIdentifier
  }

  /// Test seam — when `false` the notification helpers become a no-op
  /// (no permission dialog, no UN request). Production keeps it `true`;
  /// unit tests flip it `false` in `setUp` to avoid triggering a
  /// real macOS permission prompt while the suite runs.
  nonisolated(unsafe) static var _notificationsEnabled: Bool = true

  /// Test seam — overridable in unit tests. Default reads the real AX
  /// trust state. `nonisolated(unsafe)`: only read/written on the main
  /// actor (insert is `@MainActor`, tests run `@MainActor`).
  nonisolated(unsafe) static var _isProcessTrusted: () -> Bool = { AXIsProcessTrusted() }

  /// Insert `text` at the frontmost app's cursor using the best
  /// available strategy. Returns the strategy that succeeded
  /// (or `.skippedEmpty` / `.pasteboardOnly` on full fall-through).
  @MainActor
  public static func insert(_ text: String) async -> Result {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      log.debug("insert skipped — empty after trimming")
      return .skippedEmpty
    }

    let frontBundle = _frontmostBundleID()
    let tideBundle = Bundle.main.bundleIdentifier

    // Strategy 1 (default): Clipboard-Paste into the frontmost non-Tide
    // app. ⌘V is the most reliable insert primitive across AppKit,
    // Electron, WKWebView, terminals — anywhere the user can normally
    // paste.
    if let front = frontBundle, front != tideBundle {
      // ⌘V is delivered via CGEvent, which requires Accessibility trust.
      // Untrusted → the keystroke is silently dropped, so don't claim
      // success: fall through to pasteboard-only + a notification.
      if _isProcessTrusted(), await ClipboardPaste.paste(trimmed) {
        log.debug("insert via clipboard-paste into \(front, privacy: .public) (\(trimmed.count, privacy: .public) chars)")
        return .clipboardPaste
      }
      log.debug("insert: AX untrusted or ⌘V failed — pasteboard-only fallback")
      // Pasteboard-only: leave the text on the clipboard + notify, then return.
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(trimmed, forType: .string)
      await postPasteboardNotification()
      return .pasteboardOnly
    }

    // Strategy 2: AX-Insert — only reached when Tide itself is the
    // frontmost app (so ⌘V would land in our own panel). The AX path
    // is reliable for our own SwiftUI text field; for other apps we
    // never get here because strategy 1 won.
    if attemptAXInsert(trimmed) {
      log.debug("insert via AX (\(trimmed.count, privacy: .public) chars) — Tide-frontmost path")
      return .axInsert
    }

    // Strategy 3: pasteboard-only + notification fallback. No
    // frontmost app, or Tide is frontmost AND AX failed.
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(trimmed, forType: .string)
    await postPasteboardNotification()
    log.debug("insert fell through to pasteboard-only (frontmost: \(frontBundle ?? "nil", privacy: .public))")
    return .pasteboardOnly
  }

  // MARK: - Strategy 1: AX

  /// Attempt to write `text` into the frontmost app's focused element
  /// via the Accessibility API. Returns `true` on success.
  ///
  /// Tries `kAXSelectedTextAttribute` first (replaces any selection or
  /// inserts at the cursor when the selection is empty), then falls back
  /// to `kAXValueAttribute` (full replace — used for plain text fields
  /// that don't expose selected-text). Either path requires Tide to be
  /// AX-trusted; an untrusted process gets `kAXErrorAPIDisabled` and
  /// this returns `false` immediately, letting strategy 2 take over.
  @MainActor
  private static func attemptAXInsert(_ text: String) -> Bool {
    guard AXIsProcessTrusted() else {
      log.debug("AX-Insert: process not trusted")
      return false
    }
    guard let pid = _frontmostPID() else {
      log.debug("AX-Insert: no frontmost PID")
      return false
    }
    let appElement = AXUIElementCreateApplication(pid)
    var focused: CFTypeRef?
    let focusStatus = AXUIElementCopyAttributeValue(
      appElement, kAXFocusedUIElementAttribute as CFString, &focused
    )
    guard focusStatus == .success, let focused,
          CFGetTypeID(focused) == AXUIElementGetTypeID() else {
      log.debug("AX-Insert: no focused element")
      return false
    }
    let element = focused as! AXUIElement

    // Prefer kAXSelectedTextAttribute — replaces selection / inserts at
    // cursor. Works for native NSText* widgets.
    let setSelected = AXUIElementSetAttributeValue(
      element, kAXSelectedTextAttribute as CFString, text as CFString
    )
    if setSelected == .success {
      return true
    }

    // Fallback: replace the entire value. Plain text fields without
    // selection support.
    let setValue = AXUIElementSetAttributeValue(
      element, kAXValueAttribute as CFString, text as CFString
    )
    return setValue == .success
  }

  // MARK: - Strategy 3 helper: notification

  /// Lazily request notification permission and post the
  /// "in clipboard" toast. Failures (denied permission, missing usage
  /// description) degrade gracefully — the text is already on the
  /// pasteboard either way.
  private static func postPasteboardNotification() async {
    guard _notificationsEnabled else { return }
    await TideNotification.post(
      body: "Diktat in Zwischenablage — ⌘V drücken",
      idPrefix: "tide.dictation.clipboard"
    )
  }
}
