import SwiftUI
import Core

struct ApiKeyPromptView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("API-Key").font(.headline)
      Text("Tide braucht deinen Anthropic API-Key. Erstellbar unter console.anthropic.com.")
        .foregroundStyle(.secondary)
        .font(.callout)
      ApiKeyField()
      Spacer()
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
