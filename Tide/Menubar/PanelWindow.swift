import AppKit

/// The floating panel that appears below the menubar icon. NSPanel
/// subclass so it can become key without stealing main-app status, and
/// hides cleanly. Frame: 400×560, positioned by `MenubarController`.
final class PanelWindow: NSPanel {
  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
      styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered, defer: false
    )
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true
    isMovableByWindowBackground = false
    hidesOnDeactivate = false
    level = .floating
    isFloatingPanel = true
    becomesKeyOnlyIfNeeded = true
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
