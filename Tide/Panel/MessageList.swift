import SwiftUI
import Core
import Selection
import AppKit

struct MessageList: View {
  let messages: [Message]

  var body: some View {
    if messages.isEmpty {
      emptyState
    } else {
      messageScroll
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "waveform.circle")
        .font(.system(size: 34))
        .foregroundStyle(.tertiary)
      Text("Halte deinen Push-to-Talk-Hotkey und sprich —\noder tippe unten eine Frage.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
  }

  private var messageScroll: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 8) {
          ForEach(messages) { msg in
            MessageBubble(message: msg, onReplace: { text in
              // Hide panel so the previous app regains focus, then paste.
              NSApp.hide(nil)
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                Task { @MainActor in
                  SelectionReplacer.replaceSelection(with: text)
                }
              }
            })
            .id(msg.id)
          }
        }
        .padding(.vertical, 12)
      }
      .onChange(of: messages.last?.content) { _, _ in
        if let last = messages.last {
          withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
      }
    }
  }
}
