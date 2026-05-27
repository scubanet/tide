import KeyboardShortcuts

public extension KeyboardShortcuts.Name {
  /// Push-to-talk hotkey. Default: right Option + Return.
  /// User-configurable later via Settings (Phase 7).
  static let pushToTalk = Self("pushToTalk", default: .init(.return, modifiers: [.option]))
}
