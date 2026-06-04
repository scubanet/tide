import XCTest
import AVFoundation
@testable import TideSpeech

final class HybridRecognizerTests: XCTestCase {

  /// Stub recognizer: emits one partial on `start()` (simulating Apple's
  /// "live transcription" callback) and returns the pre-configured final
  /// on `stop()`.
  final class StubRecognizer: SpeechRecognizer, @unchecked Sendable {
    let finalText: String
    let partialContinuation: AsyncStream<String>.Continuation
    let partialTranscript: AsyncStream<String>

    var didStart = false
    var didStop = false
    var feedCount = 0

    init(final: String) {
      self.finalText = final
      var c: AsyncStream<String>.Continuation!
      self.partialTranscript = AsyncStream<String> { c = $0 }
      self.partialContinuation = c
    }

    func start() async throws {
      didStart = true
      partialContinuation.yield(finalText)  // simulate one live partial
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
      feedCount += 1
    }

    func stop() async throws -> String {
      didStop = true
      partialContinuation.finish()
      return finalText
    }
  }

  func test_hybrid_returns_elevenlabs_when_non_empty() async throws {
    let apple = StubRecognizer(final: "Apple-Text")
    let eleven = StubRecognizer(final: "ElevenLabs-Text")
    let hybrid = HybridRecognizer(apple: apple, secondary: eleven)

    try await hybrid.start()
    let result = try await hybrid.stop()

    XCTAssertEqual(result, "ElevenLabs-Text")
    XCTAssertTrue(apple.didStart)
    XCTAssertTrue(eleven.didStart)
    XCTAssertTrue(apple.didStop)
    XCTAssertTrue(eleven.didStop)
  }

  func test_hybrid_falls_back_to_apple_when_elevenlabs_empty() async throws {
    let apple = StubRecognizer(final: "Apple-Final")
    let eleven = StubRecognizer(final: "")  // simulates Scribe failure
    let hybrid = HybridRecognizer(apple: apple, secondary: eleven)

    try await hybrid.start()
    let result = try await hybrid.stop()

    XCTAssertEqual(result, "Apple-Final")
  }

  func test_hybrid_starts_both_recognizers() async throws {
    let apple = StubRecognizer(final: "x")
    let eleven = StubRecognizer(final: "y")
    let hybrid = HybridRecognizer(apple: apple, secondary: eleven)

    try await hybrid.start()
    defer { Task { _ = try? await hybrid.stop() } }

    XCTAssertTrue(apple.didStart)
    XCTAssertTrue(eleven.didStart)
  }

  func test_hybrid_fans_feed_to_both_recognizers() async throws {
    let apple = StubRecognizer(final: "a")
    let eleven = StubRecognizer(final: "b")
    let hybrid = HybridRecognizer(apple: apple, secondary: eleven)

    try await hybrid.start()
    let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 16000,
      channels: 1,
      interleaved: false
    )!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
    buffer.frameLength = 1024

    hybrid.feed(buffer)
    hybrid.feed(buffer)
    hybrid.feed(buffer)

    _ = try await hybrid.stop()

    XCTAssertEqual(apple.feedCount, 3)
    XCTAssertEqual(eleven.feedCount, 3)
  }

  func test_hybrid_forwards_apple_partials() async throws {
    let apple = StubRecognizer(final: "Live-Partial-Text")
    let eleven = StubRecognizer(final: "Final-Replace")
    let hybrid = HybridRecognizer(apple: apple, secondary: eleven)

    // Subscribe to the hybrid's partial stream BEFORE starting, so we
    // don't miss the yield from Apple's start().
    let collected: Task<[String], Never> = Task {
      var seen: [String] = []
      for await text in hybrid.partialTranscript {
        seen.append(text)
      }
      return seen
    }

    try await hybrid.start()
    // Give the forward task a tick to drain Apple's yield.
    try? await Task.sleep(nanoseconds: 50_000_000)
    _ = try await hybrid.stop()

    let partials = await collected.value
    XCTAssertTrue(partials.contains("Live-Partial-Text"),
                  "expected Apple's partial to be forwarded; got \(partials)")
  }
}
