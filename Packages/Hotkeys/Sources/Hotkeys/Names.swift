import KeyboardShortcuts

public extension KeyboardShortcuts.Name {
  /// Push-to-talk hotkey. Default: right Option + Return.
  /// User-configurable later via Settings (Phase 7).
  static let pushToTalk = Self("pushToTalk", default: .init(.return, modifiers: [.option]))

  /// Hold to dictate raw text into the frontmost app's focused
  /// text-field. No default — user picks a binding in Settings →
  /// Dictation to opt in.
  static let dictateRaw = Self("dictateRaw", default: nil)

  /// Hold to dictate text, then polish it through Claude before
  /// inserting (grammar + punctuation). No default — opt-in.
  static let dictatePolished = Self("dictatePolished", default: nil)

  /// Hold to dictate, then rewrite as a calm/factual message. Opt-in.
  static let dictateCalmer = Self("dictateCalmer", default: nil)
  /// Hold to dictate, then add fitting emojis. Opt-in.
  static let dictateEmoji = Self("dictateEmoji", default: nil)
  /// Hold to dictate, then convert to a bullet-point list. Opt-in.
  static let dictateBullets = Self("dictateBullets", default: nil)
  /// Hold to dictate, then rewrite in a formal business tone. Opt-in.
  static let dictateProfessional = Self("dictateProfessional", default: nil)
}
