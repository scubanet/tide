import SwiftUI
import Core
import LLM

struct PanelView: View {
  let conversationStore: ConversationStore
  let chatViewModel: ChatViewModel
  var onOpenSettings: () -> Void = {}
  @State private var hasKey: Bool = KeychainHelper.get(key: "anthropic.api_key") != nil

  var body: some View {
    VStack(spacing: 0) {
      TopBar(
        onNew: { chatViewModel.startNew() },
        onStopSpeaking: { chatViewModel.stopSpeaking() },
        onOpenSettings: onOpenSettings
      )
      Divider()
      if hasKey {
        ChatContainer(viewModel: chatViewModel)
      } else {
        ApiKeyPromptView(hasKey: $hasKey)
      }
    }
    .frame(width: 400, height: 560)
  }
}

private struct TopBar: View {
  let onNew: () -> Void
  let onStopSpeaking: () -> Void
  let onOpenSettings: () -> Void

  var body: some View {
    HStack {
      Button(action: onNew) {
        Label("Neu", systemImage: "plus")
      }
      .buttonStyle(.borderless)
      .keyboardShortcut("n", modifiers: .command)
      Spacer()
      // ⌘. is the macOS-standard "stop / cancel current action" shortcut.
      // Always enabled — calling synthesizer.stop() when nothing is
      // playing is a no-op, so the button is harmless to mash.
      Button(action: onStopSpeaking) {
        Image(systemName: "stop.circle")
      }
      .buttonStyle(.borderless)
      .keyboardShortcut(".", modifiers: .command)
      .help("Vorlesen stoppen (⌘.)")
      Button(action: onOpenSettings) {
        Image(systemName: "gear")
      }
      .buttonStyle(.borderless)
    }
    .padding(12)
  }
}
