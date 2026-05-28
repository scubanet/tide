import SwiftUI
import Core

/// Settings tab for Welle 4 standalone dictation (Tide v0.3.0).
///
/// The hotkeys themselves are configured in the existing
/// `HotkeySection` (Settings → Hotkey) — keeping all
/// `KeyboardShortcuts.Recorder` widgets in one place avoids a
/// confusing "which tab do I go to" choice. This tab covers the
/// dictation-specific *behaviour* knobs: the polish-mode system
/// prompt and the on-screen pill position.
struct DictationSection: View {
  @State private var settings = AppSettings()
  @State private var polishPrompt: String = ""
  @State private var pillPosition: String = "topCenter"

  /// Default we ship — kept here so the "Restore default" button can
  /// reset to it without round-tripping through `AppSettings`.
  private static let defaultPolishPrompt =
    "You are a text editor. Fix grammar and punctuation in the user's "
    + "text. Reply in the SAME language as the input. Keep the meaning "
    + "1:1, do not shorten, do not add anything, do not explain. Output "
    + "ONLY the corrected text."

  var body: some View {
    Form {
      Section {
        Text("Wird vor jeder *Polish*-Diktatsitzung als System-Prompt an "
          + "Claude gesendet. Der Rohtext kommt als einzelne User-Nachricht "
          + "hinterher.")
          .font(.caption)
          .foregroundStyle(.secondary)

        TextEditor(text: $polishPrompt)
          .font(.system(size: 12, design: .monospaced))
          .frame(minHeight: 120)
          .overlay(
            RoundedRectangle(cornerRadius: 4)
              .stroke(Color.gray.opacity(0.3), lineWidth: 1)
          )
          .onChange(of: polishPrompt) { _, newValue in
            settings.dictationPolishPrompt = newValue
          }

        HStack {
          Button("Standard wiederherstellen") {
            polishPrompt = Self.defaultPolishPrompt
            settings.dictationPolishPrompt = Self.defaultPolishPrompt
          }
          .controlSize(.small)
          Spacer()
        }
      } header: { Text("Polish-Prompt") }

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

        Text("Wo erscheint die kleine Aufnahme-Pille während des "
          + "Diktats — direkt unter der Menubar (oben Mitte), in der "
          + "Ecke oben rechts oder am unteren Rand des Hauptbildschirms.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: { Text("Aufnahme-Pille") }
    }
    .formStyle(.grouped)
    .task {
      // Seed local @State from the persisted settings on first
      // appear. (AppSettings reads UserDefaults directly — these
      // properties are computed, not stored, so the @Observable
      // macro doesn't track them. Mirroring in @State is the same
      // pattern VoiceSection uses for the recognizer picker.)
      polishPrompt = settings.dictationPolishPrompt
      pillPosition = settings.dictationPillPosition
    }
  }
}
