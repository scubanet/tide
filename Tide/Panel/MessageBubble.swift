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
        Text(rendered)
          .padding(.horizontal, 11)
          .padding(.vertical, 8)
          .background(
            message.role == .user
              ? Color.accentColor.opacity(0.15)
              : Color.gray.opacity(0.08)
          )
          .clipShape(.rect(cornerRadius: 10))
          .textSelection(.enabled)
        if message.role == .assistant, !message.content.isEmpty {
          HStack(spacing: 12) {
            Button {
              copyToClipboard(message.content)
            } label: {
              Label("Kopieren", systemImage: "doc.on.doc")
                .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Antwort kopieren")
            if hasSelectionContext, let onReplace {
              Button {
                onReplace(message.content)
              } label: {
                Label("Ersetzen", systemImage: "arrow.uturn.forward.square")
                  .font(.system(size: 11))
              }
              .buttonStyle(.borderless)
              .foregroundStyle(.secondary)
              .accessibilityLabel("Selektion ersetzen")
            }
          }
        }
      }
      if message.role == .assistant { Spacer(minLength: 40) }
    }
    .padding(.horizontal, 12)
  }

  /// Assistant/​user text rendered as Markdown. Claude replies in Markdown,
  /// so bold/italic/inline-code/links render instead of showing raw `**`.
  /// `.inlineOnlyPreservingWhitespace` keeps line breaks (chat, not a doc)
  /// and tolerates the half-formed Markdown seen mid-stream; on any parse
  /// failure we fall back to the raw string.
  private var rendered: AttributedString {
    if message.content.isEmpty { return AttributedString("…") }
    if let attributed = try? AttributedString(
      markdown: message.content,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
      return attributed
    }
    return AttributedString(message.content)
  }

  private func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
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
