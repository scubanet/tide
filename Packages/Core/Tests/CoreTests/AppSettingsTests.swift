import XCTest
@testable import Core

final class AppSettingsTests: XCTestCase {
  @MainActor
  func testDefaultsAreSensible() {
    let s = AppSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    XCTAssertEqual(s.selectedModel, "claude-sonnet-4-6")
    XCTAssertTrue(s.voiceEnabled)
    XCTAssertEqual(s.voiceIdentifier, "com.apple.voice.compact.de-DE.Anna")
    XCTAssertFalse(s.replaceSelectionByDefault)
  }

  @MainActor
  func testRoundTrip() {
    let suite = "test.\(UUID().uuidString)"
    let defs = UserDefaults(suiteName: suite)!
    let s = AppSettings(defaults: defs)
    s.selectedModel = "claude-opus-4-6"
    s.voiceEnabled = false
    s.voiceIdentifier = "com.apple.voice.premium.de-DE.Petra"
    s.replaceSelectionByDefault = true

    let reloaded = AppSettings(defaults: defs)
    XCTAssertEqual(reloaded.selectedModel, "claude-opus-4-6")
    XCTAssertFalse(reloaded.voiceEnabled)
    XCTAssertEqual(reloaded.voiceIdentifier, "com.apple.voice.premium.de-DE.Petra")
    XCTAssertTrue(reloaded.replaceSelectionByDefault)
  }
}
