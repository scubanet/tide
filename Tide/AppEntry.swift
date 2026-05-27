import SwiftUI
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
