import Foundation

extension Notification.Name {
  /// Posted by the Settings "Onboarding erneut starten" button; observed by
  /// MenubarController to (re)open the onboarding wizard.
  static let tideOpenOnboarding = Notification.Name("tide.openOnboarding")
}
