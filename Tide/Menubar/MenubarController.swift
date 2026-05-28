import AppKit
import SwiftUI
import Core
import LLM
import Selection

@MainActor
final class MenubarController {
  private let statusItem: NSStatusItem
  private let panel: PanelWindow
  private let conversationStore: ConversationStore
  let chatViewModel: ChatViewModel
  private var settingsWindow: NSWindow?

  /// Exposes the underlying `NSStatusItem` so the dictation coordinator
  /// can wire a `DictationIndicator` against the same status-bar button
  /// (Welle 4). Read-only — only `MenubarController` mutates the item's
  /// configuration.
  var menubarStatusItem: NSStatusItem { statusItem }

  init(
    conversationStore: ConversationStore,
    settings: AppSettings,
    provider: any LLMProvider
  ) {
    self.conversationStore = conversationStore
    self.chatViewModel = ChatViewModel(
      conversationStore: conversationStore,
      provider: provider,
      settings: settings
    )
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    panel = PanelWindow()
    if let button = statusItem.button {
      // Use the app's own bundled icon in the menubar instead of an
      // SF Symbol. `applicationIconImage` is the AppIcon asset Xcode
      // assembles from `Assets.xcassets/AppIcon.appiconset`. We
      // explicitly resize and disable `isTemplate` so the colour
      // logo survives (template would force it to monochrome).
      //
      // `applicationIconImage` is `NSImage?` in Swift 6's strict
      // mode — copy via `NSImage(data:)` of the icon's TIFF
      // representation so we get a fresh, non-shared instance we
      // can resize without mutating the global icon. Fall back to
      // the original SF Symbol if the AppIcon isn't loadable for
      // any reason.
      let menubarIcon: NSImage = {
        if let appIcon = NSApplication.shared.applicationIconImage,
           let tiff = appIcon.tiffRepresentation,
           let copy = NSImage(data: tiff) {
          copy.size = NSSize(width: 18, height: 18)
          copy.isTemplate = false
          return copy
        }
        let fallback = NSImage(
          systemSymbolName: "wave.3.right.circle",
          accessibilityDescription: "Tide"
        ) ?? NSImage()
        fallback.isTemplate = true
        return fallback
      }()
      button.image = menubarIcon
      button.target = self
      button.action = #selector(togglePanel)
    }
    let view = PanelView(
      conversationStore: conversationStore,
      chatViewModel: chatViewModel,
      onOpenSettings: { [weak self] in self?.openSettings() }
    )
    panel.contentViewController = NSHostingController(rootView: view)
  }

  /// Open (or focus) the Settings window. Wired from the panel's gear button.
  @objc func openSettings() {
    if let existing = settingsWindow {
      existing.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Tide Settings"
    window.contentViewController = NSHostingController(rootView: SettingsWindow())
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow = window
  }

  @objc private func togglePanel() {
    if panel.isVisible {
      panel.orderOut(nil)
    } else {
      positionPanelBelowStatusItem()
      panel.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  /// Capture the current selection from the frontmost app. Must be called
  /// BEFORE bringing Tide to the front — otherwise the prior app loses
  /// focus and AX can't read its selection any more.
  func capturePendingSelection() {
    let selection = SelectionReader.readFromFrontmostApp()
    chatViewModel.pendingSelection = selection
  }

  /// Open the panel if hidden. Called from the hotkey handler.
  func openPanel() {
    if !panel.isVisible {
      positionPanelBelowStatusItem()
      panel.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  private func positionPanelBelowStatusItem() {
    guard let button = statusItem.button,
          let buttonWindow = button.window else { return }
    let buttonFrameOnScreen = buttonWindow.convertToScreen(button.frame)
    let x = buttonFrameOnScreen.midX - panel.frame.width / 2
    let y = buttonFrameOnScreen.minY - panel.frame.height - 4
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
}
