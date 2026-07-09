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

        KeyboardShortcuts.Recorder("Diktieren (Poliert):", name: .dictatePolished)
        Text("Wie oben, aber der Text geht vor dem Einfügen durch Claude "
          + "(Grammatik + Punktuation, Inhalt 1:1). +1-2s Latenz.")
          .font(.caption)
          .foregroundStyle(.secondary)

        KeyboardShortcuts.Recorder("Diktieren (Ruhiger):", name: .dictateCalmer)
        KeyboardShortcuts.Recorder("Diktieren (Emoji):", name: .dictateEmoji)
        KeyboardShortcuts.Recorder("Diktieren (Stichpunkte):", name: .dictateBullets)
        KeyboardShortcuts.Recorder("Diktieren (Professionell):", name: .dictateProfessional)
        Text("Transform-Modi: der Text geht vor dem Einfügen durch Claude mit "
          + "dem jeweiligen Prompt (editierbar in Settings → Diktat). Alle opt-in.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("Diktat in andere Apps")
      }
    }
    .formStyle(.grouped)
  }
}
