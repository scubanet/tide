import SwiftUI
import Core

struct ApiKeySection: View {
  @State private var input: String = ""
  @State private var hasExistingKey: Bool = KeychainHelper.get(key: "anthropic.api_key") != nil
  @State private var savedToast: Bool = false

  var body: some View {
    Form {
      Section {
        if hasExistingKey {
          HStack {
            Label("API-Key gesetzt", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Spacer()
            Button("Zurücksetzen", role: .destructive) {
              KeychainHelper.delete(key: "anthropic.api_key")
              hasExistingKey = false
              input = ""
            }
          }
        }
        SecureField("sk-ant-...", text: $input)
          .textFieldStyle(.roundedBorder)
        HStack {
          Button("Speichern") {
            do {
              try KeychainHelper.set(key: "anthropic.api_key", value: input)
              hasExistingKey = true
              input = ""
              savedToast = true
              DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedToast = false }
            } catch {
              // ignore — sensible default
            }
          }
          .disabled(input.isEmpty)
          if savedToast {
            Text("Gespeichert ✓")
              .foregroundStyle(.green)
              .font(.callout)
          }
        }
        Text("Erstellbar unter console.anthropic.com. Neu starten nach Änderung.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("Anthropic API-Key")
      }
    }
    .formStyle(.grouped)
  }
}
