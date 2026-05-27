import SwiftUI
import Core

struct ApiKeyPromptView: View {
  @Binding var hasKey: Bool
  @State private var input = ""
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("API-Key").font(.headline)
      Text("Tide braucht deinen Anthropic API-Key. Erstellbar unter console.anthropic.com.")
        .foregroundStyle(.secondary)
        .font(.callout)
      SecureField("sk-ant-...", text: $input)
        .textFieldStyle(.roundedBorder)
      if let errorMessage {
        Text(errorMessage)
          .foregroundStyle(Color.red)
          .font(.caption)
      }
      Button("Speichern") {
        do {
          try KeychainHelper.set(key: "anthropic.api_key", value: input)
          hasKey = true
        } catch {
          errorMessage = "Keychain-Fehler: \(error.localizedDescription)"
        }
      }
      .disabled(input.isEmpty)
      Spacer()
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
