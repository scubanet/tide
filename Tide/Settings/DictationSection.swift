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
  @State private var promptText: String = ""
  @State private var pillPosition: String = "topCenter"

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

  private func currentPrompt(_ mode: PromptMode) -> String {
    switch mode {
    case .polished:     settings.dictationPolishPrompt
    case .calmer:       settings.dictationCalmerPrompt
    case .emoji:        settings.dictationEmojiPrompt
    case .bullets:      settings.dictationBulletsPrompt
    case .professional: settings.dictationProfessionalPrompt
    }
  }

  private func setPrompt(_ mode: PromptMode, _ value: String) {
    switch mode {
    case .polished:     settings.dictationPolishPrompt = value
    case .calmer:       settings.dictationCalmerPrompt = value
    case .emoji:        settings.dictationEmojiPrompt = value
    case .bullets:      settings.dictationBulletsPrompt = value
    case .professional: settings.dictationProfessionalPrompt = value
    }
  }

  var body: some View {
    Form {
      Section {
        Picker("Modus:", selection: $selectedMode) {
          ForEach(PromptMode.allCases) { mode in
            Text(mode.label).tag(mode)
          }
        }
        .pickerStyle(.menu)
        .onChange(of: selectedMode) { _, newMode in
          promptText = currentPrompt(newMode)
        }

        Text("System-Prompt für den gewählten Transform-Modus. Wird vor "
          + "jeder Sitzung dieses Modus an Claude gesendet; der Rohtext "
          + "kommt als User-Nachricht hinterher.")
          .font(.caption)
          .foregroundStyle(.secondary)

        TextEditor(text: $promptText)
          .font(.system(size: 12, design: .monospaced))
          .frame(minHeight: 120)
          .overlay(
            RoundedRectangle(cornerRadius: 4)
              .stroke(Color.gray.opacity(0.3), lineWidth: 1)
          )
          .onChange(of: promptText) { _, newValue in
            setPrompt(selectedMode, newValue)
          }

        HStack {
          Button("Standard wiederherstellen") {
            promptText = selectedMode.default
            setPrompt(selectedMode, selectedMode.default)
          }
          .controlSize(.small)
          Spacer()
        }
      } header: { Text("Transform-Prompts") }

      Section {
        Picker("Position:", selection: $pillPosition) {
          Text("Oben Mitte").tag("topCenter")
          Text("Oben Rechts").tag("topRight")
          Text("Unten Rechts").tag("bottomRight")
        }
        .pickerStyle(.menu)
        .onChange(of: pillPosition) { _, newValue in
          settings.dictationPillPosition = newValue
        }

        Text("Wo erscheint die kleine Aufnahme-Pille während des Diktats.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: { Text("Aufnahme-Pille") }
    }
    .formStyle(.grouped)
    .task {
      promptText = currentPrompt(selectedMode)
      pillPosition = settings.dictationPillPosition
    }
  }
}
