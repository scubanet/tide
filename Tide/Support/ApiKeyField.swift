import SwiftUI
import Core

/// The single Anthropic-API-key entry control, shared by the panel
/// prompt, onboarding and Settings. Saves to the keychain, surfaces
/// keychain errors consistently (instead of `try?`-swallowing them) and
/// posts `.tideApiKeyChanged` so every "has key" gate updates live.
struct ApiKeyField: View {
  /// Called after a successful save (input already cleared).
  var onSaved: () -> Void = {}
  @State private var input = ""
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SecureField("sk-ant-…", text: $input)
        .textFieldStyle(.roundedBorder)
      if let errorMessage {
        Text(errorMessage)
          .foregroundStyle(Color.red)
          .font(.caption)
      }
      Button("Speichern") {
        do {
          try KeychainHelper.set(key: KeychainKey.anthropic, value: input)
          input = ""
          errorMessage = nil
          NotificationCenter.default.post(name: .tideApiKeyChanged, object: nil)
          onSaved()
        } catch {
          errorMessage = "Keychain-Fehler: \(error.localizedDescription)"
        }
      }
      .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
    }
  }
}
