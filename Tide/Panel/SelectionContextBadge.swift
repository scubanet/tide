import SwiftUI
import Selection

struct SelectionContextBadge: View {
  let selection: SelectedText
  let onDismiss: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "text.quote")
        .foregroundStyle(Color.accentColor)
      VStack(alignment: .leading, spacing: 1) {
        Text(selection.sourceAppName.isEmpty ? "Selektion" : "Selektion aus \(selection.sourceAppName)")
          .font(.system(size: 11, weight: .semibold))
        Text("\(selection.text.count) Zeichen")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(action: onDismiss) {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color.accentColor.opacity(0.08))
    .clipShape(.rect(cornerRadius: 8))
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
  }
}
