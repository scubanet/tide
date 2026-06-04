import Foundation

/// One settings pane. Drives the grouped sidebar in `SettingsWindow`.
/// `groups` is the single source for both the sidebar layout and the
/// `SettingsTabTests` invariants — no drift between UI and test.
enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
  case api
  case model
  case voice
  case vocabulary
  case local
  case hotkey
  case dictation
  case actions

  var id: String { rawValue }

  var label: String {
    switch self {
    case .api:        "API"
    case .model:      "Modell"
    case .voice:      "Stimme"
    case .vocabulary: "Vokabular"
    case .local:      "Lokal"
    case .hotkey:     "Hotkey"
    case .dictation:  "Diktat"
    case .actions:    "Actions"
    }
  }

  var systemImage: String {
    switch self {
    case .api:        "key"
    case .model:      "cpu"
    case .voice:      "waveform"
    case .vocabulary: "character.book.closed"
    case .local:      "internaldrive"
    case .hotkey:     "keyboard"
    case .dictation:  "mic.fill"
    case .actions:    "bolt"
    }
  }

  /// Sidebar groups in display order. Union must equal `allCases` with no
  /// duplication (enforced by `SettingsTabTests`).
  static let groups: [(title: String, tabs: [SettingsTab])] = [
    ("Allgemein", [.api, .model]),
    ("Sprache",   [.voice, .vocabulary, .local]),
    ("Diktat",    [.hotkey, .dictation]),
    ("Erweitert", [.actions]),
  ]
}
