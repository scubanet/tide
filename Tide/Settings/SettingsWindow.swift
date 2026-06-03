import SwiftUI
import Core

struct SettingsWindow: View {
  var body: some View {
    TabView {
      ApiKeySection()
        .tabItem { Label("API", systemImage: "key") }
      HotkeySection()
        .tabItem { Label("Hotkey", systemImage: "keyboard") }
      ModelSection()
        .tabItem { Label("Modell", systemImage: "cpu") }
      VoiceSection()
        .tabItem { Label("Stimme", systemImage: "waveform") }
      DictationSection()
        .tabItem { Label("Diktat", systemImage: "mic.fill") }
      VocabularySection()
        .tabItem { Label("Vokabular", systemImage: "character.book.closed") }
      LocalModelSection()
        .tabItem { Label("Lokal", systemImage: "internaldrive") }
      QuickActionsEditor()
        .tabItem { Label("Actions", systemImage: "bolt") }
    }
    .frame(width: 520, height: 380)
    .padding(20)
  }
}
