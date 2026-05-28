import Foundation
import AVFoundation
import OSLog

/// Coordinator: Apple provides live partials during recording, ElevenLabs
/// runs in parallel (collecting audio via its bufferProvider) and replaces
/// the final text with a more accurate transcription on `stop()`.
///
/// Partials are forwarded from the Apple recognizer's `partialTranscript`
/// stream. `feed(_:)` is fanned out to both recognizers (Apple consumes it
/// directly; ElevenLabs ignores it but the call is cheap and keeps the
/// contract clean).
///
/// On `stop()`:
///   - Apple is stopped first (drains its final transcript).
///   - ElevenLabs is stopped second (triggers the Scribe upload).
///   - If Scribe returns a non-empty string, that replaces Apple's result.
///   - If Scribe returns empty (network fail, timeout, no audio), Apple's
///     result is kept. Daily-Use must never block.
public final class HybridRecognizer: SpeechRecognizer, @unchecked Sendable {
  private let apple: any SpeechRecognizer
  private let eleven: any SpeechRecognizer
  private let partialContinuation: AsyncStream<String>.Continuation
  public let partialTranscript: AsyncStream<String>

  private var forwardTask: Task<Void, Never>?

  private static let logger = Logger(
    subsystem: "swiss.weckherlin.tide",
    category: "hybrid-recognizer"
  )

  public init(apple: any SpeechRecognizer, eleven: any SpeechRecognizer) {
    self.apple = apple
    self.eleven = eleven
    var continuation: AsyncStream<String>.Continuation!
    self.partialTranscript = AsyncStream<String> { continuation = $0 }
    self.partialContinuation = continuation
  }

  public func start() async throws {
    // Start ElevenLabs first (no-op at start time, but ensures any future
    // setup work happens before we begin draining Apple partials).
    try await eleven.start()
    try await apple.start()

    // Forward Apple's live partials to our own stream.
    let appleStream = apple.partialTranscript
    let cont = partialContinuation
    forwardTask = Task {
      for await text in appleStream {
        cont.yield(text)
      }
    }
  }

  public func feed(_ buffer: AVAudioPCMBuffer) {
    apple.feed(buffer)
    eleven.feed(buffer)
  }

  public func stop() async throws -> String {
    let appleFinal = (try? await apple.stop()) ?? ""
    let elevenFinal = (try? await eleven.stop()) ?? ""

    forwardTask?.cancel()
    forwardTask = nil
    partialContinuation.finish()

    if elevenFinal.isEmpty {
      Self.logger.debug("Hybrid: ElevenLabs returned empty, keeping Apple result.")
      return appleFinal
    }
    Self.logger.debug(
      "Hybrid: replacing Apple (\(appleFinal.count) chars) with ElevenLabs (\(elevenFinal.count) chars)."
    )
    return elevenFinal
  }
}
