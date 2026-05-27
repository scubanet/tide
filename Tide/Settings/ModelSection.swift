import SwiftUI
import Core

struct ModelSection: View {
  @State private var settings = AppSettings()

  private let availableModels = [
    "claude-sonnet-4-6",
    "claude-opus-4-6",
    "claude-haiku-4-5-20251001",
  ]

  var body: some View {
    Form {
      Section {
        Picker("Anthropic-Modell:", selection: Binding(
          get: { settings.selectedModel },
          set: { settings.selectedModel = $0 }
        )) {
          ForEach(availableModels, id: \.self) { model in
            Text(modelLabel(for: model)).tag(model)
          }
        }
        Text("Sonnet 4.6: schnell, gut. Opus 4.6: stärker, langsamer. Haiku 4.5: günstig, kurz.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("LLM")
      }
    }
    .formStyle(.grouped)
  }

  private func modelLabel(for id: String) -> String {
    switch id {
    case "claude-sonnet-4-6":         "Claude Sonnet 4.6"
    case "claude-opus-4-6":           "Claude Opus 4.6"
    case "claude-haiku-4-5-20251001": "Claude Haiku 4.5"
    default: id
    }
  }
}
