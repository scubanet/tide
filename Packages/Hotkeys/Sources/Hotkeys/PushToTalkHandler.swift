import Foundation
import KeyboardShortcuts

/// Registers handlers for the named `pushToTalk` shortcut and bridges
/// the library's onKeyDown/onKeyUp callbacks to user-supplied closures.
/// Instantiate once at app launch and keep alive.
@MainActor
public final class PushToTalkHandler {
  private let onPress: () -> Void
  private let onRelease: () -> Void

  public init(
    onPress: @escaping () -> Void,
    onRelease: @escaping () -> Void
  ) {
    self.onPress = onPress
    self.onRelease = onRelease
    KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
      self?.onPress()
    }
    KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
      self?.onRelease()
    }
  }
}
