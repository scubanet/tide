import Foundation

/// The ordered steps of the first-run onboarding wizard.
enum OnboardingStep: Int, CaseIterable, Hashable {
  case welcome
  case apiKey
  case permissions
  case hotkey
  case voice
  case done

  static var count: Int { allCases.count }

  /// Zero-based position, for the progress indicator.
  var index: Int { rawValue }

  /// Next step, clamped at `.done`.
  var next: OnboardingStep {
    OnboardingStep(rawValue: rawValue + 1) ?? .done
  }

  /// Previous step, clamped at `.welcome`.
  var previous: OnboardingStep {
    OnboardingStep(rawValue: rawValue - 1) ?? .welcome
  }

  var title: String {
    switch self {
    case .welcome:     "Willkommen bei Tide"
    case .apiKey:      "Anthropic API-Key"
    case .permissions: "Berechtigungen"
    case .hotkey:      "Hotkeys"
    case .voice:       "Sprache & Stimme"
    case .done:        "Fertig"
    }
  }
}
