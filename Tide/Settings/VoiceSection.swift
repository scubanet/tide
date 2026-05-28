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

  private var appleVoices: [AVSpeechSynthesisVoice] {
    AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language.hasPrefix("de") || $0.language.hasPrefix("en") }
      .sorted { $0.name < $1.name }
  }

  var body: some View {
    Form {
      Section {
        Toggle("Antworten vorlesen", isOn: Binding(
          get: { settings.voiceEnabled },
          set: { settings.voiceEnabled = $0 }
        ))
      } header: { Text("Text-to-Speech") }

      Section {
        Picker("TTS-Provider:", selection: Binding(
          get: { settings.ttsProvider },
          set: { settings.ttsProvider = $0 }
        )) {
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
          Picker("Stimme:", selection: Binding(
            get: { settings.voiceIdentifier },
            set: { settings.voiceIdentifier = $0 }
          )) {
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
            Picker("Stimme:", selection: Binding(
              get: { settings.elevenLabsVoiceID },
              set: { settings.elevenLabsVoiceID = $0 }
            )) {
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
        // Bridge the typed enum to the String-backed AppSettings property.
        // AppSettings stores the raw string (Core has no TideSpeech dep);
        // the picker speaks SpeechRecognizerChoice.
        Picker("Recognizer:", selection: Binding<SpeechRecognizerChoice>(
          get: {
            SpeechRecognizerChoice(rawValue: settings.speechRecognizer)
              ?? .default
          },
          set: { newChoice in
            // Key-required choice without a stored key? Snap back to
            // Apple and surface a hint. The hint clears next time the
            // user lands on a valid combo.
            if newChoice.requiresElevenLabsKey, elevenLabsKey.isEmpty {
              settings.speechRecognizer = SpeechRecognizerChoice.apple.rawValue
              showRecognizerKeyMissingHint = true
            } else {
              settings.speechRecognizer = newChoice.rawValue
              showRecognizerKeyMissingHint = false
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

        Text("Hybrid empfohlen: Apple liefert sofortige Live-Vorschau, "
          + "ElevenLabs ersetzt am Ende mit höher-genauer Transkription.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: { Text("Spracherkennung") }

      Section {
        Toggle("Selektion standardmäßig ersetzen", isOn: Binding(
          get: { settings.replaceSelectionByDefault },
          set: { settings.replaceSelectionByDefault = $0 }
        ))
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
