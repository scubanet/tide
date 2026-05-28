import Foundation
import AVFoundation
import OSLog

/// Non-streaming recognizer. Buffer-API: an external accumulator collects
/// PCM during recording (driven by the app-side `AudioRecorder`); on
/// `stop()` we post the WAV to Scribe and return the final text.
///
/// Apple-style live partials are not provided — `partialTranscript` is
/// an empty stream. Use `HybridRecognizer` if you want live text while
/// recording.
///
/// On Scribe failure (network, 5xx, timeout) we log and return the empty
/// string so the caller can fall back to whatever else they have.
public final class ElevenLabsRecognizer: SpeechRecognizer, @unchecked Sendable {
  private let client: ElevenLabsClient
  private let bufferProvider: @Sendable () -> Data?
  private let partialContinuation: AsyncStream<String>.Continuation
  public let partialTranscript: AsyncStream<String>

  private static let logger = Logger(
    subsystem: "swiss.weckherlin.tide",
    category: "el-recognizer"
  )

  /// - Parameters:
  ///   - client: ElevenLabs API client (carries the API key).
  ///   - bufferProvider: closure that returns the WAV-encoded audio data
  ///     when called on `stop()` — typically wraps
  ///     `AudioBufferAccumulator.exportWAV(sampleRate: 16000, channels: 1)`.
  public init(
    client: ElevenLabsClient,
    bufferProvider: @escaping @Sendable () -> Data?
  ) {
    self.client = client
    self.bufferProvider = bufferProvider
    var continuation: AsyncStream<String>.Continuation!
    self.partialTranscript = AsyncStream<String> { continuation = $0 }
    self.partialContinuation = continuation
  }

  public func start() async throws {
    // Scribe is non-streaming. Nothing to do at start. The caller's
    // buffer accumulator is reset externally by the app-side
    // AudioRecorder (HybridRecognizer + AudioRecorder coordinate that).
  }

  public func feed(_ buffer: AVAudioPCMBuffer) {
    // No-op. Audio is collected by the app-side AudioBufferAccumulator
    // (via AudioRecorder's tap) and handed back to us via `bufferProvider`
    // on `stop()`.
  }

  public func stop() async throws -> String {
    guard let wavData = bufferProvider() else {
      Self.logger.debug("No buffered audio to transcribe.")
      partialContinuation.finish()
      return ""
    }
    do {
      let text = try await client.transcribe(audioData: wavData)
      Self.logger.debug("Scribe transcribed \(text.count) chars.")
      partialContinuation.finish()
      return text
    } catch {
      Self.logger.warning(
        "Scribe failed: \(error.localizedDescription, privacy: .public) — returning empty for fallback"
      )
      partialContinuation.finish()
      return ""
    }
  }
}
