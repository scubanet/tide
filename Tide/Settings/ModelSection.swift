import SwiftUI
import Core

struct ModelSection: View {
  let settings: AppSettings

  private let availableModels = [
    "claude-sonnet-5",
    "claude-opus-4-8",
    "claude-haiku-4-5-20251001",
  ]

  var body: some View {
    @Bindable var settings = settings
    Form {
      Section {
        Picker("Anthropic-Modell:", selection: $settings.selectedModel) {
          ForEach(availableModels, id: \.self) { model in
            Text(modelLabel(for: model)).tag(model)
          }
        }
        Text("Sonnet 5: schnell, gut. Opus 4.8: stärker, langsamer. Haiku 4.5: günstig, kurz.")
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
    case "claude-sonnet-5":           "Claude Sonnet 5"
    case "claude-opus-4-8":           "Claude Opus 4.8"
    case "claude-haiku-4-5-20251001": "Claude Haiku 4.5"
    default: id
    }
  }
}
