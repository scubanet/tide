import AppKit
import OSLog

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "selection")

/// Posts a synthetic ⌘V to the frontmost application after dropping
/// `text` on the pasteboard, then restores the prior clipboard later.
public enum ClipboardPaste {
  /// Drop `text` on the pasteboard, post ⌘V (serialized so the ⌘
  /// modifier registers before V), then restore the previous clipboard
  /// after a delay. Returns `false` if the synthetic events could not be
  /// created. `@MainActor` + `async` because it sleeps between events.
  @MainActor
  @discardableResult
  public static func paste(_ text: String) async -> Bool {
    let pasteboard = NSPasteboard.general
    let oldContents = pasteboard.string(forType: .string)
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    // Remember the change count of OUR write so the delayed restore can
    // tell whether the user copied something new in the meantime.
    let injectedChangeCount = pasteboard.changeCount

    let ok = await postCommandV()
    log.debug("ClipboardPaste ⌘V posted=\(ok, privacy: .public) (\(text.count, privacy: .public) chars)")

    // Only restore if the ⌘V was actually posted. If event creation
    // failed, the caller falls back to "text on clipboard, press ⌘V" —
    // restoring would wipe that text out from under the user.
    guard ok else { return false }

    // Restore after the target app has had time to consume the paste.
    // Electron/WebKit hosts read the pasteboard asynchronously; 800ms is
    // comfortably past their read window.
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 800_000_000)
      // Only restore if the pasteboard still holds Tide's injected text.
      // If the user copied something new during the window, leave their
      // fresh clipboard alone instead of clobbering it with stale data.
      guard pasteboard.changeCount == injectedChangeCount else { return }
      pasteboard.clearContents()
      if let old = oldContents { pasteboard.setString(old, forType: .string) }
    }
    return true
  }

  /// Post ⌘V as four events with a small inter-event gap so the ⌘
  /// modifier is registered before V (a no-gap burst races and lands as
  /// a bare "v" or nothing, worse in optimized release builds). The
  /// `.maskCommand` flag is stamped on the modifier-down + both V events.
  @MainActor
  private static func postCommandV() async -> Bool {
    let source = CGEventSource(stateID: .combinedSessionState)
    let cmdKey: CGKeyCode = 0x37
    let vKey: CGKeyCode = 0x09
    guard
      let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true),
      let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
      let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false),
      let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)
    else {
      log.error("postCommandV: CGEvent creation failed")
      return false
    }
    cmdDown.flags = .maskCommand
    vDown.flags = .maskCommand
    vUp.flags = .maskCommand
    cmdUp.flags = []

    let gap: UInt64 = 8_000_000  // 8ms
    cmdDown.post(tap: .cghidEventTap)
    try? await Task.sleep(nanoseconds: gap)
    vDown.post(tap: .cghidEventTap)
    try? await Task.sleep(nanoseconds: gap)
    vUp.post(tap: .cghidEventTap)
    try? await Task.sleep(nanoseconds: gap)
    cmdUp.post(tap: .cghidEventTap)
    return true
  }
}
