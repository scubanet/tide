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

  @MainActor
  func testSpeechRecognizerDefaultsToHybrid() {
    let s = AppSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    XCTAssertEqual(s.speechRecognizer, "hybrid")
  }

  @MainActor
  func testSpeechRecognizerRoundTrip() {
    let suite = "test.\(UUID().uuidString)"
    let defs = UserDefaults(suiteName: suite)!
    let s = AppSettings(defaults: defs)
    s.speechRecognizer = "elevenLabs"
    XCTAssertEqual(s.speechRecognizer, "elevenLabs")

    let reloaded = AppSettings(defaults: defs)
    XCTAssertEqual(reloaded.speechRecognizer, "elevenLabs")

    s.speechRecognizer = "apple"
    XCTAssertEqual(s.speechRecognizer, "apple")
  }

  @MainActor
  func testDictationPolishPromptDefaultIsLanguageAgnostic() {
    let s = AppSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    XCTAssertEqual(
      s.dictationPolishPrompt,
      "You are a text editor. Fix grammar and punctuation in the user's text. Reply in the SAME language as the input. Keep the meaning 1:1, do not shorten, do not add anything, do not explain. Output ONLY the corrected text."
    )
  }

  @MainActor
  func testDictationPolishPromptRoundTrip() {
    let suite = "test.\(UUID().uuidString)"
    let defs = UserDefaults(suiteName: suite)!
    let s = AppSettings(defaults: defs)
    s.dictationPolishPrompt = "x"

    let reloaded = AppSettings(defaults: defs)
    XCTAssertEqual(reloaded.dictationPolishPrompt, "x")
  }

  @MainActor
  func testDictationPillPositionDefaultsToTopCenter() {
    let s = AppSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    XCTAssertEqual(s.dictationPillPosition, "topCenter")
  }

  @MainActor
  func testDictationPillPositionRoundTrip() {
    let suite = "test.\(UUID().uuidString)"
    let defs = UserDefaults(suiteName: suite)!
    let s = AppSettings(defaults: defs)
    s.dictationPillPosition = "bottomRight"

    let reloaded = AppSettings(defaults: defs)
    XCTAssertEqual(reloaded.dictationPillPosition, "bottomRight")
  }

  @MainActor
  func testCustomVocabularyDefaultsEmpty() {
    let s = AppSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    XCTAssertEqual(s.customVocabulary, [])
  }

  @MainActor
  func testCustomVocabularyRoundTrip() {
    let suite = "test.\(UUID().uuidString)"
    let defs = UserDefaults(suiteName: suite)!
    let s = AppSettings(defaults: defs)
    s.customVocabulary = ["PADI", "Nitrox"]
    let reloaded = AppSettings(defaults: defs)
    XCTAssertEqual(reloaded.customVocabulary, ["PADI", "Nitrox"])
  }

  @MainActor
  func testCustomVocabularyTrimsAndDropsBlankLines() {
    let suite = "test.\(UUID().uuidString)"
    let defs = UserDefaults(suiteName: suite)!
    // Simulate a raw multiline string with blank lines and padding.
    defs.set("PADI\n\n  Nitrox  \n\n", forKey: "tide.customVocabulary")
    let s = AppSettings(defaults: defs)
    XCTAssertEqual(s.customVocabulary, ["PADI", "Nitrox"])
  }
}
