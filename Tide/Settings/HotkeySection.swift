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
        Text("Claude (Panel)")
      }

      Section {
        KeyboardShortcuts.Recorder("Diktieren (Roh):", name: .dictateRaw)
        Text("Halten zum Aufnehmen, loslassen fügt den transkribierten Text "
          + "1:1 an der Cursor-Position der gerade fokussierten App ein. "
          + "Tide-Panel öffnet sich nicht. Kein Default — bitte setzen.")
          .font(.caption)
          .foregroundStyle(.secondary)

        KeyboardShortcuts.Recorder("Diktieren (Polished):", name: .dictatePolished)
        Text("Wie oben, aber der Text geht vor dem Einfügen durch Claude "
          + "(Grammatik + Punktuation, Inhalt 1:1). +1-2s Latenz.")
          .font(.caption)
          .foregroundStyle(.secondary)

        KeyboardShortcuts.Recorder("Diktieren (Calmer):", name: .dictateCalmer)
        KeyboardShortcuts.Recorder("Diktieren (Emoji):", name: .dictateEmoji)
        KeyboardShortcuts.Recorder("Diktieren (Bullets):", name: .dictateBullets)
        KeyboardShortcuts.Recorder("Diktieren (Professional):", name: .dictateProfessional)
        Text("Transform-Modi: der Text geht vor dem Einfügen durch Claude mit "
          + "dem jeweiligen Prompt (editierbar in Settings → Diktat). Alle opt-in.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("Standalone Dictation (Welle 4)")
      }
    }
    .formStyle(.grouped)
  }
}
