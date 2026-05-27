import SwiftUI
import Core

/// Horizontal pill row. Tap a pill to "arm" the corresponding action —
/// the next message will use that action's system prompt. Tap again to
/// disarm. After the message is sent, the selection clears automatically
/// (driven by ChatViewModel).
struct QuickActionsBar: View {
  let actions: [QuickAction]
  @Binding var selectedSlug: String?

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(actions) { action in
          Pill(action: action,
               isSelected: selectedSlug == action.slug) {
            if selectedSlug == action.slug {
              selectedSlug = nil
            } else {
              selectedSlug = action.slug
            }
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
  }

  private struct Pill: View {
    let action: QuickAction
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
      Button(action: onTap) {
        Text(action.label)
          .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
          .foregroundStyle(isSelected ? Color.white : Color.primary)
          .padding(.horizontal, 11)
          .padding(.vertical, 5)
          .background(isSelected ? Color.accentColor : Color.gray.opacity(0.12))
          .clipShape(.capsule)
      }
      .buttonStyle(.plain)
    }
  }
}
