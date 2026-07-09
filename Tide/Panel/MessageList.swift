import SwiftUI
import Core
import Selection
import AppKit

struct MessageList: View {
  let messages: [Message]
  /// True while the last assistant message is still streaming in. The
  /// live bubble then renders plain text (no per-token Markdown parse)
  /// and auto-scroll skips its animation (competing animation
  /// transactions per token cause janky scrolling).
  var isStreaming: Bool = false

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
    // Computed once per list change (body does not re-run per streamed
    // token) — the bubbles must not walk/sort the conversation themselves.
    let withContext = Self.selectionContextIDs(messages)
    return ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 8) {
          ForEach(messages) { msg in
            MessageBubble(
              message: msg,
              isLive: isStreaming && msg.id == messages.last?.id,
              hasSelectionContext: withContext.contains(msg.id),
              onReplace: { text in
                // Hide panel so the previous app regains focus, then paste.
                NSApp.hide(nil)
                Task { @MainActor in
                  try? await Task.sleep(for: .milliseconds(150))
                  SelectionReplacer.replaceSelection(with: text)
                }
              }
            )
            .id(msg.id)
          }
        }
        .padding(.vertical, 12)
      }
      .onChange(of: messages.last?.content) { _, _ in
        guard let last = messages.last else { return }
        if isStreaming {
          proxy.scrollTo(last.id, anchor: .bottom)
        } else {
          withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
      }
    }
  }

  /// IDs of assistant messages whose most recent preceding user message
  /// carried selection context — i.e. where a "Ersetzen" button makes
  /// sense. One linear pass over the already-ordered array.
  private static func selectionContextIDs(_ messages: [Message]) -> Set<UUID> {
    var ids = Set<UUID>()
    var lastUserHadSelection = false
    for msg in messages {
      switch msg.role {
      case .user:
        lastUserHadSelection = msg.selectionContextJSON != nil
      case .assistant:
        if lastUserHadSelection { ids.insert(msg.id) }
      case .tool:
        break
      }
    }
    return ids
  }
}
