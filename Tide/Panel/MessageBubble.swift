import SwiftUI
import Core
import Selection
import AppKit

struct MessageBubble: View {
  let message: Message
  /// Closure the bubble calls when the user taps "Replace selection".
  var onReplace: ((String) -> Void)? = nil

  var body: some View {
    HStack(alignment: .top) {
      if message.role == .user { Spacer(minLength: 40) }
      VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
        Text(message.content.isEmpty ? "…" : message.content)
          .padding(.horizontal, 11)
          .padding(.vertical, 8)
          .background(
            message.role == .user
              ? Color.accentColor.opacity(0.15)
              : Color.gray.opacity(0.08)
          )
          .clipShape(.rect(cornerRadius: 10))
          .textSelection(.enabled)
        if message.role == .assistant, hasSelectionContext, let onReplace {
          Button {
            onReplace(message.content)
          } label: {
            Label("Ersetzen", systemImage: "arrow.uturn.forward.square")
              .font(.system(size: 11))
          }
          .buttonStyle(.borderless)
          .foregroundStyle(.secondary)
        }
      }
      if message.role == .assistant { Spacer(minLength: 40) }
    }
    .padding(.horizontal, 12)
  }

  /// True when the preceding user message in this conversation carries a
  /// `selectionContextJSON` — i.e. this assistant turn was driven by a
  /// selection from another app and a Replace button makes sense.
  private var hasSelectionContext: Bool {
    guard let conv = message.conversation else { return false }
    let ordered = conv.orderedMessages
    guard let myIndex = ordered.firstIndex(where: { $0.id == message.id }) else { return false }
    // Walk backwards; find the most recent preceding user message.
    for i in stride(from: myIndex - 1, through: 0, by: -1) where ordered[i].role == .user {
      return ordered[i].selectionContextJSON != nil
    }
    return false
  }
}
