import AppKit

/// Tints the menubar status item to signal that a dictation session is
/// in flight.
///
/// Holds a weak reference to the `NSStatusBarButton` from
/// `MenubarController`'s `NSStatusItem`. Idle state shows the bundled
/// Tide app icon (colour). Active state swaps to a red-filled
/// `wave.3.right.circle.fill` so it reads instantly as "recording in
/// progress" — keeping the idle icon and only tinting it red would not
/// stand out against the menubar.
///
/// On `deactivate()` we restore the resized + non-template app icon
/// (mirroring what `MenubarController` set at construction). We
/// snapshot the original image on first `activate()` and reuse that
/// snapshot rather than re-fetching `applicationIconImage`, so any
/// resize the caller applied stays consistent.
///
/// `activate()` and `deactivate()` are idempotent — calling either twice
/// in a row is a no-op. The button reference is weak so the tint helper
/// never artificially extends the status item's lifetime; if the menubar
/// controller goes away the tint helper simply does nothing.
@MainActor
final class MenubarTint {
  private weak var button: NSStatusBarButton?
  private var isActive: Bool = false
  private var savedImage: NSImage?
  private var savedTint: NSColor?

  init(button: NSStatusBarButton) {
    self.button = button
  }

  /// Switch the status-item icon into the red recording-active state.
  /// No-op if already active or if the button has been deallocated.
  func activate() {
    guard !isActive, let button else { return }
    isActive = true
    savedImage = button.image
    savedTint = button.contentTintColor
    let image = NSImage(
      systemSymbolName: "wave.3.right.circle.fill",
      accessibilityDescription: "Tide is recording"
    )
    image?.isTemplate = false
    button.image = image
    button.contentTintColor = .systemRed
  }

  /// Restore the status-item icon to whatever was in place before
  /// `activate()` (the Tide app icon, in current wiring).
  /// No-op if already deactivated or if the button has been deallocated.
  func deactivate() {
    guard isActive, let button else { return }
    isActive = false
    button.image = savedImage
    button.contentTintColor = savedTint
    savedImage = nil
    savedTint = nil
  }
}
