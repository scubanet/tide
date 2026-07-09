import XCTest
@testable import TideSpeech

/// Records every call so tests can assert routing behaviour.
@MainActor
private final class SpySynthesizer: Synthesizer {
  var spoken: [String] = []
  var stopCount = 0
  var voices: [String] = []
  var speaking = false

  func speak(_ text: String) { spoken.append(text) }
  func stop() { stopCount += 1 }
  func setVoice(identifier: String) { voices.append(identifier) }
  var isSpeaking: Bool { speaking }
}

@MainActor
final class CompositeSynthesizerTests: XCTestCase {

  func test_routesToApple_byDefault() {
    let apple = SpySynthesizer()
    let eleven = SpySynthesizer()
    let sut = CompositeSynthesizer(apple: apple, elevenLabs: eleven)

    sut.speak("hallo")

    XCTAssertEqual(apple.spoken, ["hallo"])
    XCTAssertTrue(eleven.spoken.isEmpty)
  }

  func test_routesToElevenLabs_whenSelected() {
    let apple = SpySynthesizer()
    let eleven = SpySynthesizer()
    let sut = CompositeSynthesizer(apple: apple, elevenLabs: eleven, provider: .elevenLabs)

    sut.speak("hallo")
    sut.setVoice(identifier: "voice-1")

    XCTAssertEqual(eleven.spoken, ["hallo"])
    XCTAssertEqual(eleven.voices, ["voice-1"])
    XCTAssertTrue(apple.spoken.isEmpty)
  }

  func test_switchingProvider_stopsPreviousOne() {
    let apple = SpySynthesizer()
    let eleven = SpySynthesizer()
    let sut = CompositeSynthesizer(apple: apple, elevenLabs: eleven, provider: .apple)

    sut.setProvider(.elevenLabs)

    XCTAssertEqual(apple.stopCount, 1)
    XCTAssertEqual(eleven.stopCount, 0)
    XCTAssertEqual(sut.currentProvider, .elevenLabs)

    sut.speak("nach dem Wechsel")
    XCTAssertEqual(eleven.spoken, ["nach dem Wechsel"])
  }

  func test_settingSameProvider_doesNotStop() {
    let apple = SpySynthesizer()
    let sut = CompositeSynthesizer(apple: apple, provider: .apple)

    sut.setProvider(.apple)

    XCTAssertEqual(apple.stopCount, 0)
  }

  func test_missingElevenLabs_fallsBackToApple() {
    let apple = SpySynthesizer()
    let sut = CompositeSynthesizer(apple: apple, elevenLabs: nil, provider: .elevenLabs)

    sut.speak("fallback")
    sut.stop()

    XCTAssertEqual(apple.spoken, ["fallback"])
    XCTAssertEqual(apple.stopCount, 1)
  }

  func test_isSpeaking_reflectsActiveProvider() {
    let apple = SpySynthesizer()
    let eleven = SpySynthesizer()
    let sut = CompositeSynthesizer(apple: apple, elevenLabs: eleven, provider: .elevenLabs)

    eleven.speaking = true
    XCTAssertTrue(sut.isSpeaking)

    sut.setProvider(.apple)
    XCTAssertFalse(sut.isSpeaking)
  }
}
