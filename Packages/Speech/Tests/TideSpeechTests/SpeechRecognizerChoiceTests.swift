import XCTest
@testable import TideSpeech

final class SpeechRecognizerChoiceTests: XCTestCase {
  func test_whisperKit_isInAllCases() {
    XCTAssertTrue(SpeechRecognizerChoice.allCases.contains(.whisperKit))
  }

  func test_whisperKit_flags() {
    XCTAssertTrue(SpeechRecognizerChoice.whisperKit.requiresLocalModel)
    XCTAssertFalse(SpeechRecognizerChoice.whisperKit.requiresElevenLabsKey)
  }

  func test_nonLocalChoices_doNotRequireLocalModel() {
    XCTAssertFalse(SpeechRecognizerChoice.apple.requiresLocalModel)
    XCTAssertFalse(SpeechRecognizerChoice.elevenLabs.requiresLocalModel)
    XCTAssertFalse(SpeechRecognizerChoice.hybrid.requiresLocalModel)
  }

  func test_whisperKit_displayName() {
    XCTAssertFalse(SpeechRecognizerChoice.whisperKit.displayName.isEmpty)
  }

  func test_hybridLocal_isInAllCases() {
    XCTAssertTrue(SpeechRecognizerChoice.allCases.contains(.hybridLocal))
  }

  func test_hybridLocal_flags() {
    XCTAssertTrue(SpeechRecognizerChoice.hybridLocal.requiresLocalModel)
    XCTAssertFalse(SpeechRecognizerChoice.hybridLocal.requiresElevenLabsKey)
  }

  func test_hybridLocal_displayName() {
    XCTAssertFalse(SpeechRecognizerChoice.hybridLocal.displayName.isEmpty)
  }
}
