import SwiftUI
import Core

/// Settings tab for standalone dictation: per-mode transform prompts +
/// the on-screen pill position.
///
/// The five transform modes (polished/calmer/emoji/bullets/professional)
/// each have an editable system prompt. A picker selects which one the
/// editor shows; writing saves to that mode's `AppSettings` key.
/// `raw` has no prompt and is excluded from the picker.
struct DictationSection: View {
  @State private var settings = AppSettings()
  @State private var selectedMode: PromptMode = .polished

  /// The prompt-bearing modes (everything except raw).
  enum PromptMode: String, CaseIterable, Identifiable {
    case polished, calmer, emoji, bullets, professional
    var id: String { rawValue }
    var label: String {
      switch self {
      case .polished:     "Polished"
      case .calmer:       "Calmer"
      case .emoji:        "Emoji"
      case .bullets:      "Bullets"
      case .professional: "Professional"
      }
    }
    @MainActor var `default`: String {
      switch self {
      case .polished:     AppSettings.defaultPolishPrompt
      case .calmer:       AppSettings.defaultCalmerPrompt
      case .emoji:        AppSettings.defaultEmojiPrompt
      case .bullets:      AppSettings.defaultBulletsPrompt
      case .professional: AppSettings.defaultProfessionalPrompt
      }
    }
  }

  /// A binding to the `AppSettings` prompt backing the given mode.
  private func promptBinding(for mode: PromptMode) -> Binding<String> {
    switch mode {
    case .polished:     Binding(get: { settings.dictationPolishPrompt }, set: { settings.dictationPolishPrompt = $0 })
    case .calmer:       Binding(get: { settings.dictationCalmerPrompt }, set: { settings.dictationCalmerPrompt = $0 })
    case .emoji:        Binding(get: { settings.dictationEmojiPrompt }, set: { settings.dictationEmojiPrompt = $0 })
    case .bullets:      Binding(get: { settings.dictationBulletsPrompt }, set: { settings.dictationBulletsPrompt = $0 })
    case .professional: Binding(get: { settings.dictationProfessionalPrompt }, set: { settings.dictationProfessionalPrompt = $0 })
    }
  }

  var body: some View {
    @Bindable var settings = settings
    Form {
      Section {
        Picker("Modus:", selection: $selectedMode) {
          ForEach(PromptMode.allCases) { mode in
            Text(mode.label).tag(mode)
          }
        }
        .pickerStyle(.menu)

        Text("System-Prompt für den gewählten Transform-Modus. Wird vor "
          + "jeder Sitzung dieses Modus an Claude gesendet; der Rohtext "
          + "kommt als User-Nachricht hinterher.")
          .font(.caption)
          .foregroundStyle(.secondary)

        TextEditor(text: promptBinding(for: selectedMode))
          .font(.system(size: 12, design: .monospaced))
          .frame(minHeight: 120)
          .overlay(
            RoundedRectangle(cornerRadius: 4)
              .stroke(Color.gray.opacity(0.3), lineWidth: 1)
          )

        HStack {
          Button("Standard wiederherstellen") {
            promptBinding(for: selectedMode).wrappedValue = selectedMode.default
          }
          .controlSize(.small)
          Spacer()
        }
      } header: { Text("Transform-Prompts") }

      Section {
        Picker("Position:", selection: $settings.dictationPillPosition) {
          Text("Oben Mitte").tag("topCenter")
          Text("Oben Rechts").tag("topRight")
          Text("Unten Rechts").tag("bottomRight")
        }
        .pickerStyle(.menu)

        Text("Wo erscheint die kleine Aufnahme-Pille während des Diktats.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: { Text("Aufnahme-Pille") }
    }
    .formStyle(.grouped)
  }
}
