import AppKit
import Core

/// Visual feedback coordinator for a single dictation session.
///
/// Pairs the two indicator surfaces — the menubar tint and the floating
/// pill — behind a single API. The `DictationCoordinator` drives both as
/// one: `show()` on session-start, `update(partial:)` for each partial
/// transcript, `hide()` on session-stop.
///
/// Each `show()` re-reads `settings.dictationPillPosition` and passes it
/// to the pill so a user changing the position in Settings sees the new
/// corner the next time they dictate, without restarting Tide.
@MainActor
final class DictationIndicator {
  private let tint: MenubarTint?
  private let pill: FloatingPill
  private let settings: AppSettings

  init(statusItem: NSStatusItem, settings: AppSettings) {
    self.settings = settings
    // The status item retains its button strongly; we hold the button
    // weakly inside MenubarTint so the indicator never artificially
    // extends the menubar controller's lifetime. In the (essentially
    // impossible) case where `statusItem.button` is nil, the tint is
    // simply absent — the pill still provides visual feedback.
    self.tint = statusItem.button.map(MenubarTint.init(button:))
    self.pill = FloatingPill(position: settings.dictationPillPosition)
  }

  /// Start the visual feedback for a new session.
  func show() {
    pill.updatePosition(settings.dictationPillPosition)
    tint?.activate()
    pill.show(initialText: "")
  }

  /// Live partial-transcript update — currently only the pill cares.
  func update(partial: String) {
    pill.update(partial: partial)
  }

  /// Stop the visual feedback. Idempotent.
  func hide() {
    tint?.deactivate()
    pill.hide()
  }

  /// Show a transient hint on the pill (e.g. after a rejected
  /// recording). The menubar tint is untouched — by the time a reject
  /// is known the coordinator has already called `hide()`, which
  /// deactivated the tint.
  func flash(_ message: String) {
    pill.flash(message)
  }
}
