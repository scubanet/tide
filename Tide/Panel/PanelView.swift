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
  let onOpenSettings: () -> Void

  var body: some View {
    HStack {
      Button(action: onNew) {
        Label("Neu", systemImage: "plus")
      }
      .buttonStyle(.borderless)
      .keyboardShortcut("n", modifiers: .command)
      Spacer()
      Button(action: onOpenSettings) {
        Image(systemName: "gear")
      }
      .buttonStyle(.borderless)
    }
    .padding(12)
  }
}
