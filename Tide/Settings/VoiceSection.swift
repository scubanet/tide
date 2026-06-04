import SwiftUI
import AVFoundation
import Core
import TideSpeech

struct VoiceSection: View {
  @State private var settings = AppSettings()
  @State private var elevenLabsKey: String = KeychainHelper.get(key: "elevenlabs.api_key") ?? ""
  @State private var elevenLabsVoices: [ElevenLabsClient.Voice] = []
  @State private var fetchingVoices = false
  @State private var fetchError: String?
  @State private var showRecognizerKeyMissingHint = false
  @State private var showLocalModelMissingHint = false

  private var appleVoices: [AVSpeechSynthesisVoice] {
    AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language.hasPrefix("de") || $0.language.hasPrefix("en") }
      .sorted { $0.name < $1.name }
  }

  var body: some View {
    @Bindable var settings = settings
    Form {
      Section {
        Toggle("Antworten vorlesen", isOn: $settings.voiceEnabled)
      } header: { Text("Text-to-Speech") }

      Section {
        Picker("TTS-Provider:", selection: $settings.ttsProvider) {
          Text("Apple (System)").tag("apple")
          Text("ElevenLabs (Cloud)").tag("elevenLabs")
        }
        .pickerStyle(.segmented)
        Text(settings.ttsProvider == "elevenLabs"
          ? "ElevenLabs: natürliche AI-Stimmen. Kostet ~$5/Monat (Hobby-Tier)."
          : "Apple: lokal & gratis. Lade Premium-Stimmen via Systemeinstellungen → Bedienungshilfen → Gesprochene Inhalte.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: { Text("Provider") }

      if settings.ttsProvider == "apple" {
        Section {
          Picker("Stimme:", selection: $settings.voiceIdentifier) {
            ForEach(appleVoices, id: \.identifier) { voice in
              Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
            }
          }
          .disabled(!settings.voiceEnabled)
        } header: { Text("Apple Stimme") }
      } else {
        Section {
          SecureField("xi-api-key", text: $elevenLabsKey)
            .textFieldStyle(.roundedBorder)
          HStack {
            Button("Key speichern + Stimmen laden") {
              try? KeychainHelper.set(key: "elevenlabs.api_key", value: elevenLabsKey)
              fetchVoices()
            }
            .disabled(elevenLabsKey.isEmpty)
            if fetchingVoices {
              ProgressView().controlSize(.small)
            }
          }
          if let fetchError {
            Text(fetchError)
              .foregroundStyle(.red)
              .font(.caption)
          }
          Text("Erstellbar unter elevenlabs.io. Tide-Restart nach Key-Änderung.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: { Text("ElevenLabs API-Key") }

        if !elevenLabsVoices.isEmpty {
          Section {
            Picker("Stimme:", selection: $settings.elevenLabsVoiceID) {
              ForEach(elevenLabsVoices) { voice in
                Text("\(voice.name)\(voice.category.map { " (\($0))" } ?? "")")
                  .tag(voice.voice_id)
              }
            }
            .disabled(!settings.voiceEnabled)
          } header: { Text("ElevenLabs Stimme") }
        }
      }

      Section {
        // The picker reads/writes `settings.speechRecognizer` through an
        // enum adapter whose `set` folds in the snap-back validation: a
        // choice that needs an ElevenLabs key or a missing local model
        // reverts to `.apple` and surfaces the matching hint.
        Picker("Recognizer:", selection: Binding(
          get: { SpeechRecognizerChoice(rawValue: settings.speechRecognizer) ?? .default },
          set: { newChoice in
            if newChoice.requiresElevenLabsKey, elevenLabsKey.isEmpty {
              settings.speechRecognizer = SpeechRecognizerChoice.apple.rawValue
              showRecognizerKeyMissingHint = true
              showLocalModelMissingHint = false
            } else if newChoice.requiresLocalModel,
                      !WhisperModelStore().isInstalled(settings.localModelName) {
              settings.speechRecognizer = SpeechRecognizerChoice.apple.rawValue
              showLocalModelMissingHint = true
              showRecognizerKeyMissingHint = false
            } else {
              settings.speechRecognizer = newChoice.rawValue
              showRecognizerKeyMissingHint = false
              showLocalModelMissingHint = false
            }
          }
        )) {
          ForEach(SpeechRecognizerChoice.allCases, id: \.self) { choice in
            Text(choice.displayName).tag(choice)
          }
        }
        .pickerStyle(.radioGroup)

        if showRecognizerKeyMissingHint {
          Text("ElevenLabs API-Key fehlt — siehe ElevenLabs-Provider oben, "
            + "dann erneut wählen.")
            .font(.caption)
            .foregroundStyle(.orange)
        }

        if showLocalModelMissingHint {
          Text("Kein lokales Modell installiert — lade erst eines im "
            + "‚Lokal'-Tab, dann erneut wählen.")
            .font(.caption)
            .foregroundStyle(.orange)
        }

        Text("Hybrid empfohlen: Apple liefert sofortige Live-Vorschau, "
          + "ElevenLabs ersetzt am Ende mit höher-genauer Transkription.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: { Text("Spracherkennung") }

      Section {
        Toggle("Nach Push-to-Talk automatisch senden", isOn: $settings.autoSendAfterPushToTalk)
        Text("Wenn aus: Der transkribierte Text landet im Eingabefeld — "
          + "du kannst ihn editieren und manuell mit Return senden. "
          + "Reiner Diktiermodus.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: { Text("Push-to-Talk-Verhalten") }

      Section {
        Toggle("Selektion standardmäßig ersetzen", isOn: $settings.replaceSelectionByDefault)
        Text("Wenn aktiv, ersetzt Tide den markierten Text automatisch nach dem Senden.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: { Text("Selektions-Verhalten") }
    }
    .formStyle(.grouped)
    .task {
      if settings.ttsProvider == "elevenLabs", !elevenLabsKey.isEmpty {
        fetchVoices()
      }
    }
  }

  private func fetchVoices() {
    let key = elevenLabsKey
    guard !key.isEmpty else { return }
    fetchingVoices = true
    fetchError = nil
    Task {
      do {
        let voices = try await ElevenLabsClient(apiKey: key).listVoices()
        await MainActor.run {
          elevenLabsVoices = voices.sorted { $0.name < $1.name }
          fetchingVoices = false
        }
      } catch {
        await MainActor.run {
          fetchError = "Fetch failed: \(error.localizedDescription)"
          fetchingVoices = false
        }
      }
    }
  }
}
