import SwiftUI
import Core
import TideSpeech
import KeyboardShortcuts

// MARK: Welcome

struct WelcomeStep: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Tide ist deine immer-erreichbare KI in der Menubar.")
        .font(.title3).bold()
      Text("Dieser kurze Einrichtungs-Assistent verbindet deinen Anthropic-"
        + "API-Key, holt die nötigen Berechtigungen und richtet deine Hotkeys "
        + "ein. Alles ist später in den Einstellungen änderbar.")
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: API-Key

struct ApiKeyStep: View {
  @Binding var hasKey: Bool
  @State private var input = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Tide spricht mit Claude über die Anthropic-API. Den Key erstellst "
        + "du unter console.anthropic.com.")
        .foregroundStyle(.secondary)
      if hasKey {
        Label("API-Key gesetzt", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      }
      SecureField("sk-ant-…", text: $input)
        .textFieldStyle(.roundedBorder)
      Button("Speichern") {
        try? KeychainHelper.set(key: "anthropic.api_key", value: input)
        hasKey = KeychainHelper.get(key: "anthropic.api_key")?.isEmpty == false
        input = ""
      }
      .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
    }
  }
}

// MARK: Permissions

struct PermissionsStep: View {
  @State private var mic: PermissionStatus = .notDetermined
  @State private var speech: PermissionStatus = .notDetermined
  @State private var ax = false
  private let service = PermissionsService()

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Ohne diese Berechtigungen scheitern Diktat und Text-Selektion still.")
        .font(.caption).foregroundStyle(.secondary)
      permissionRow("Mikrofon", granted: mic == .granted) {
        _ = await service.requestMicrophone(); refresh()
      }
      permissionRow("Spracherkennung", granted: speech == .granted) {
        _ = await service.requestSpeech(); refresh()
      }
      permissionRow("Bedienungshilfen (Accessibility)", granted: ax) {
        service.promptAccessibility()
      }
      Text("Accessibility wird in den Systemeinstellungen aktiviert — der "
        + "Haken aktualisiert sich, sobald du zurückkommst.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .task { refresh() }
    .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
      refresh()
    }
  }

  private func refresh() {
    mic = service.microphone()
    speech = service.speech()
    ax = service.accessibility()
  }

  @ViewBuilder
  private func permissionRow(_ label: String, granted: Bool, action: @escaping () async -> Void) -> some View {
    HStack {
      Image(systemName: granted ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(granted ? .green : .secondary)
      Text(label)
      Spacer()
      if !granted {
        Button("Erlauben") { Task { await action() } }
          .controlSize(.small)
      }
    }
  }
}

// MARK: Hotkey

struct HotkeyStep: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Push-to-Talk öffnet das Panel und spricht mit Claude. Diktat fügt "
        + "Text direkt am Cursor der fokussierten App ein.")
        .font(.caption).foregroundStyle(.secondary)
      KeyboardShortcuts.Recorder("Push-to-Talk:", name: .pushToTalk)
      KeyboardShortcuts.Recorder("Diktieren (Roh):", name: .dictateRaw)
      Text("Weitere Diktat-Modi (Polished, Calmer, …) bindest du später unter "
        + "Einstellungen → Diktat → Hotkey.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}

// MARK: Voice / Recognizer

struct VoiceStep: View {
  let settings: AppSettings

  var body: some View {
    @Bindable var settings = settings
    VStack(alignment: .leading, spacing: 14) {
      Picker("Spracherkennung:", selection: Binding(
        get: { SpeechRecognizerChoice(rawValue: settings.speechRecognizer) ?? .default },
        set: { settings.speechRecognizer = $0.rawValue }
      )) {
        ForEach(SpeechRecognizerChoice.allCases, id: \.self) { c in
          Text(c.displayName).tag(c)
        }
      }

      Picker("Vorlese-Stimme:", selection: $settings.ttsProvider) {
        Text("Apple (System)").tag("apple")
        Text("ElevenLabs (Cloud)").tag("elevenLabs")
      }
      .pickerStyle(.segmented)

      Text("ElevenLabs- und lokale-Modell-Details richtest du in "
        + "Einstellungen → Sprache ein.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}

// MARK: Done

struct DoneStep: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Alles eingerichtet", systemImage: "checkmark.seal.fill")
        .font(.title3).bold()
        .foregroundStyle(.green)
      Text("Halte deinen Push-to-Talk-Hotkey und sprich mit Claude. Alle "
        + "Einstellungen findest du jederzeit über das Menubar-Icon → Zahnrad.")
        .foregroundStyle(.secondary)
    }
  }
}
