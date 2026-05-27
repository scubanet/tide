import XCTest
@testable import Hotkeys

final class HotkeysTests: XCTestCase {
  @MainActor
  func testHandlerCompiles() {
    // Compile-only smoke. Real PTT testing requires user interaction.
    _ = PushToTalkHandler(onPress: {}, onRelease: {})
  }
}
