import SwiftUI
import AppKit
import Core
import LLM

struct PanelView: View {
  let conversationStore: ConversationStore
  let chatViewModel: ChatViewModel
  var onOpenSettings: () -> Void = {}
  var onCheckForUpdates: () -> Void = {}
  @State private var hasKey: Bool = KeychainHelper.get(key: "anthropic.api_key") != nil

  var body: some View {
    VStack(spacing: 0) {
      TopBar(
        viewModel: chatViewModel,
        onOpenSettings: onOpenSettings,
        onCheckForUpdates: onCheckForUpdates,
        onQuit: { NSApp.terminate(nil) }
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
  let viewModel: ChatViewModel
  let onOpenSettings: () -> Void
  let onCheckForUpdates: () -> Void
  let onQuit: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      Button { viewModel.startNew() } label: {
        Label("Neu", systemImage: "plus")
      }
      .buttonStyle(.borderless)
      .keyboardShortcut("n", modifiers: .command)
      .accessibilityLabel("Neue Konversation")

      historyMenu

      Spacer()
      // ⌘. is the macOS-standard "stop / cancel current action" shortcut.
      // Cancels an in-flight response AND any TTS; a no-op when idle, so
      // it's harmless to mash.
      Button { viewModel.cancelStreaming() } label: {
        Image(systemName: "stop.circle")
      }
      .buttonStyle(.borderless)
      .keyboardShortcut(".", modifiers: .command)
      .help("Stoppen (⌘.)")
      .accessibilityLabel("Stoppen")

      Button(action: onCheckForUpdates) {
        Image(systemName: "arrow.down.circle")
      }
      .buttonStyle(.borderless)
      .help("Nach Updates suchen…")
      .accessibilityLabel("Nach Updates suchen")

      Button(action: onOpenSettings) {
        Image(systemName: "gear")
      }
      .buttonStyle(.borderless)
      .help("Einstellungen")
      .accessibilityLabel("Einstellungen")
      // ⌘Q is the macOS-standard quit shortcut. Without it (or this
      // button) there's no obvious exit path — Tide hides its Dock
      // icon via LSUIElement, so there's no App-menu either.
      Button(action: onQuit) {
        Image(systemName: "power.circle")
      }
      .buttonStyle(.borderless)
      .keyboardShortcut("q", modifiers: .command)
      .help("Tide beenden (⌘Q)")
      .accessibilityLabel("Tide beenden")
    }
    .padding(12)
  }

  private var historyMenu: some View {
    Menu {
      let conversations = viewModel.recentConversations()
      if conversations.isEmpty {
        Text("Kein Verlauf")
      } else {
        ForEach(conversations) { conv in
          Button { viewModel.switchTo(conv) } label: { Text(conv.title) }
        }
        Divider()
        Menu("Löschen") {
          ForEach(conversations) { conv in
            Button(role: .destructive) { viewModel.delete(conv) } label: {
              Text(conv.title)
            }
          }
        }
      }
    } label: {
      Image(systemName: "clock.arrow.circlepath")
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .help("Verlauf")
    .accessibilityLabel("Verlauf")
  }
}
