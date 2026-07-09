import AppIntents
import Foundation

// MARK: - Intent targets (dependency bridge)

/// Bridge between the App-Intents layer and the app's live controllers.
/// Registered with `AppDependencyManager` in `TideApp.init()` (which runs
/// even for background intent invocations) and populated by
/// `TideAppDelegate` once the controllers exist. Intents that fire during
/// the launch gap see `nil` and answer with a "starting up" dialog
/// instead of crashing.
@MainActor
final class TideIntentTargets {
  static let shared = TideIntentTargets()
  weak var menubarController: MenubarController?
  weak var dictationCoordinator: DictationCoordinator?
  private init() {}
}

/// Thrown when an intent runs before the app finished launching.
struct TideNotReadyError: Error, CustomLocalizedStringResourceConvertible {
  var localizedStringResource: LocalizedStringResource {
    "Tide startet noch — bitte versuche es gleich nochmal."
  }
}

// MARK: - DictationMode as AppEnum

extension DictationMode: AppEnum {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Diktat-Modus"
  static let caseDisplayRepresentations: [DictationMode: DisplayRepresentation] = [
    .raw:          "Roh",
    .polished:     "Poliert",
    .calmer:       "Ruhiger",
    .emoji:        "Emoji",
    .bullets:      "Stichpunkte",
    .professional: "Professionell",
  ]
}

// MARK: - Intents

struct StartDictationIntent: AppIntent {
  static let title: LocalizedStringResource = "Diktat starten"
  static let description = IntentDescription(
    "Startet eine Diktat-Sitzung. Der erkannte Text wird nach dem Stoppen an der Cursor-Position der aktiven App eingefügt."
  )
  /// The app must be running for the audio engine and injection to work;
  /// as an LSUIElement menubar app this never opens a window.
  static let openAppWhenRun: Bool = true

  @Parameter(title: "Modus", default: .raw)
  var mode: DictationMode

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let coordinator = TideIntentTargets.shared.dictationCoordinator else {
      throw TideNotReadyError()
    }
    guard !coordinator.isActive else {
      return .result(dialog: "Es läuft bereits ein Diktat.")
    }
    await coordinator.start(mode: mode)
    return .result(dialog: "Diktat läuft — beenden mit „Diktat stoppen“.")
  }
}

struct StopDictationIntent: AppIntent {
  static let title: LocalizedStringResource = "Diktat stoppen"
  static let description = IntentDescription(
    "Beendet die laufende Diktat-Sitzung und fügt den erkannten Text an der Cursor-Position ein."
  )
  static let openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let coordinator = TideIntentTargets.shared.dictationCoordinator else {
      throw TideNotReadyError()
    }
    guard coordinator.isActive else {
      return .result(dialog: "Kein Diktat aktiv.")
    }
    await coordinator.stop()
    return .result(dialog: "Diktat beendet.")
  }
}

struct OpenPanelIntent: AppIntent {
  static let title: LocalizedStringResource = "Panel öffnen"
  static let description = IntentDescription("Öffnet das Tide-Chat-Panel.")
  static let openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult {
    guard let controller = TideIntentTargets.shared.menubarController else {
      throw TideNotReadyError()
    }
    controller.openPanel()
    return .result()
  }
}

// MARK: - App Shortcuts (Siri / Spotlight / Shortcuts discoverability)

struct TideShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartDictationIntent(),
      phrases: [
        "Starte Diktat in \(.applicationName)",
        "Diktat mit \(.applicationName) starten",
        "Starte \(\.$mode) Diktat in \(.applicationName)",
      ],
      shortTitle: "Diktat starten",
      systemImageName: "mic.fill"
    )
    AppShortcut(
      intent: StopDictationIntent(),
      phrases: [
        "Stoppe Diktat in \(.applicationName)",
        "Diktat in \(.applicationName) beenden",
      ],
      shortTitle: "Diktat stoppen",
      systemImageName: "stop.fill"
    )
    AppShortcut(
      intent: OpenPanelIntent(),
      phrases: [
        "Öffne das \(.applicationName) Panel",
        "Zeige \(.applicationName)",
      ],
      shortTitle: "Panel öffnen",
      systemImageName: "bubble.left.and.text.bubble.right"
    )
  }
}
