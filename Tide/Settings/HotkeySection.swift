import SwiftUI
import KeyboardShortcuts
import Hotkeys

struct HotkeySection: View {
  var body: some View {
    Form {
      Section {
        KeyboardShortcuts.Recorder("Push-to-Talk:", name: .pushToTalk)
        Text("Halten zum Aufnehmen, loslassen zum Senden. Default ist Option+Return.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("Globaler Hotkey")
      }
    }
    .formStyle(.grouped)
  }
}
