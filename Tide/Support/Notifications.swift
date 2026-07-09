import Foundation

extension Notification.Name {
  /// Posted by the Settings "Onboarding erneut starten" button; observed by
  /// MenubarController to (re)open the onboarding wizard.
  static let tideOpenOnboarding = Notification.Name("tide.openOnboarding")

  /// Posted whenever the Anthropic API key is saved or deleted (panel
  /// prompt, onboarding, Settings), so views gating on "has key" can
  /// re-check the keychain without an app relaunch.
  static let tideApiKeyChanged = Notification.Name("tide.apiKeyChanged")
}
