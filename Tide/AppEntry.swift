import SwiftUI
import AppKit
import Core
import Hotkeys

@main
struct TideApp: App {
  @NSApplicationDelegateAdaptor(TideAppDelegate.self) var delegate

  var body: some Scene {
    Settings { EmptyView() }
  }
}

final class TideAppDelegate: NSObject, NSApplicationDelegate {
  @MainActor private var menubarController: MenubarController?
  @MainActor private var conversationStore: ConversationStore?
  @MainActor private var pushToTalk: PushToTalkHandler?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Single-instance enforcement: if another Tide is already running
    // (e.g. a leftover Xcode-built one while the user double-clicks the
    // shipped /Applications copy, or vice versa) we hand control back
    // to it and terminate this one. Two instances would otherwise both
    // register the same global push-to-talk hotkey, both stick a status
    // item in the menubar, and fight over the microphone.
    if let bundleID = Bundle.main.bundleIdentifier {
      let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0 != NSRunningApplication.current }
      if let existing = others.first {
        existing.activate(options: [])
        NSApp.terminate(nil)
        return
      }
    }

    Task { @MainActor in
      do {
        let store = try ConversationStore()
        self.conversationStore = store
        let controller = MenubarController(conversationStore: store)
        self.menubarController = controller
        self.pushToTalk = PushToTalkHandler(
          onPress: { [weak controller] in
            guard let controller else { return }
            // Capture selection BEFORE bringing Tide to the front —
            // otherwise the prior app loses focus and AX can't read its
            // selection any more.
            controller.capturePendingSelection()
            controller.openPanel()
            Task { @MainActor in
              await controller.chatViewModel.startRecording()
            }
          },
          onRelease: { [weak controller] in
            guard let controller else { return }
            Task { @MainActor in
              await controller.chatViewModel.stopRecording()
            }
          }
        )
      } catch {
        NSLog("Tide: failed to init store: \(error)")
      }
    }
  }
}
