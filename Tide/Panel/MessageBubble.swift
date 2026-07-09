import SwiftUI
import Core
import Selection
import AppKit

struct MessageBubble: View {
  let message: Message
  /// True while this bubble's content is still streaming in. Live bubbles
  /// render plain text — parsing the whole (growing) message as Markdown
  /// on every token is O(n²) over a long reply. The finished bubble
  /// renders Markdown once when streaming ends.
  var isLive: Bool = false
  /// Whether the preceding user message carried selection context (the
  /// "Ersetzen" button then makes sense). Computed once in `MessageList`
  /// — deriving it here would re-walk the conversation per render.
  var hasSelectionContext: Bool = false
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
                .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Antwort kopieren")
            if hasSelectionContext, let onReplace {
              Button {
                onReplace(message.content)
              } label: {
                Label("Ersetzen", systemImage: "arrow.uturn.forward.square")
                  .font(.subheadline)
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
    if isLive { return AttributedString(message.content) }
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
}
