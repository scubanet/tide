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
      QuickActionsEditor()
        .tabItem { Label("Actions", systemImage: "bolt") }
    }
    .frame(width: 520, height: 380)
    .padding(20)
  }
}
