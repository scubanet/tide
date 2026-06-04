import XCTest
import TideSpeech
@testable import Tide

private actor MockHybridTranscriber: Transcribing {
  func transcribe(wav: Data, language: String?, modelName: String) async throws -> String { "x" }
  func prewarm(modelName: String) async throws {}
}

/// Verifies `RecognizerFactory.make(...)` produces the right concrete
/// recognizer for each combination of user choice + API-key presence.
/// Type-introspection only — the recognizers aren't exercised against
/// the audio path here.
@MainActor
final class RecognizerFactoryTests: XCTestCase {
  func test_appleChoice_returnsAppleRecognizer() {
    let acc = AudioBufferAccumulator()
    let r = RecognizerFactory.make(for: .apple, apiKey: nil, accumulator: acc)
    XCTAssertTrue(r is AppleSpeechRecognizer)
  }

  func test_appleChoice_ignoresPresentKey() {
    // Even with a key, .apple stays Apple — the choice wins.
    let acc = AudioBufferAccumulator()
    let r = RecognizerFactory.make(for: .apple, apiKey: "sk-test", accumulator: acc)
    XCTAssertTrue(r is AppleSpeechRecognizer)
  }

  func test_elevenLabsChoice_withKey_returnsElevenLabsRecognizer() {
    let acc = AudioBufferAccumulator()
    let r = RecognizerFactory.make(for: .elevenLabs, apiKey: "sk-test", accumulator: acc)
    XCTAssertTrue(r is ElevenLabsRecognizer)
  }

  func test_elevenLabsChoice_withoutKey_fallsBackToApple() {
    let acc = AudioBufferAccumulator()
    let r = RecognizerFactory.make(for: .elevenLabs, apiKey: nil, accumulator: acc)
    XCTAssertTrue(r is AppleSpeechRecognizer)
  }

  func test_elevenLabsChoice_emptyKey_fallsBackToApple() {
    let acc = AudioBufferAccumulator()
    let r = RecognizerFactory.make(for: .elevenLabs, apiKey: "", accumulator: acc)
    XCTAssertTrue(r is AppleSpeechRecognizer)
  }

  func test_hybridChoice_withKey_returnsHybridRecognizer() {
    let acc = AudioBufferAccumulator()
    let r = RecognizerFactory.make(for: .hybrid, apiKey: "sk-test", accumulator: acc)
    XCTAssertTrue(r is HybridRecognizer)
  }

  func test_hybridChoice_withoutKey_fallsBackToApple() {
    let acc = AudioBufferAccumulator()
    let r = RecognizerFactory.make(for: .hybrid, apiKey: nil, accumulator: acc)
    XCTAssertTrue(r is AppleSpeechRecognizer)
  }

  func test_hybridLocal_withModelAndTranscriber_returnsHybrid() {
    let acc = AudioBufferAccumulator()
    let r = RecognizerFactory.make(
      for: .hybridLocal, apiKey: nil, accumulator: acc,
      localModelName: "m", localModelInstalled: true,
      transcriber: MockHybridTranscriber()
    )
    XCTAssertTrue(r is HybridRecognizer)
  }

  func test_hybridLocal_withoutModel_fallsBackToApple() {
    let acc = AudioBufferAccumulator()
    let r = RecognizerFactory.make(
      for: .hybridLocal, apiKey: nil, accumulator: acc,
      localModelName: "m", localModelInstalled: false,
      transcriber: MockHybridTranscriber()
    )
    XCTAssertTrue(r is AppleSpeechRecognizer)
  }

  func test_hybridLocal_withoutTranscriber_fallsBackToApple() {
    let acc = AudioBufferAccumulator()
    let r = RecognizerFactory.make(
      for: .hybridLocal, apiKey: nil, accumulator: acc,
      localModelName: "m", localModelInstalled: true,
      transcriber: nil
    )
    XCTAssertTrue(r is AppleSpeechRecognizer)
  }
}
