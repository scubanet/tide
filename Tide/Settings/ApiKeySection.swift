import SwiftUI
import Core

struct ApiKeySection: View {
  @State private var hasExistingKey: Bool = KeychainHelper.get(key: KeychainKey.anthropic)?.isEmpty == false
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
              KeychainHelper.delete(key: KeychainKey.anthropic)
              hasExistingKey = false
              NotificationCenter.default.post(name: .tideApiKeyChanged, object: nil)
            }
          }
        }
        ApiKeyField {
          hasExistingKey = true
          savedToast = true
          Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            savedToast = false
          }
        }
        if savedToast {
          Text("Gespeichert ✓")
            .foregroundStyle(.green)
            .font(.callout)
        }
        Text("Erstellbar unter console.anthropic.com. Gilt sofort — kein Neustart nötig.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("Anthropic API-Key")
      }

      Section {
        Button("Onboarding erneut starten") {
          NotificationCenter.default.post(name: .tideOpenOnboarding, object: nil)
        }
      } footer: {
        Text("Öffnet den Einrichtungs-Assistenten (API-Key, Berechtigungen, "
          + "Hotkeys, Stimme) erneut.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}
