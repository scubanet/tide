import Foundation
import AVFoundation
import OSLog

/// Non-streaming `SpeechRecognizer` backed by a local WhisperKit model.
/// Mirrors `ElevenLabsRecognizer`: an external `AudioBufferAccumulator`
/// collects PCM during recording; on `stop()` we hand the WAV snapshot to
/// the shared `Transcribing` engine. No live partials.
///
/// On any failure we log and return "" so the caller's empty/reject
/// handling kicks in (never crash a dictation over a model error).
public final class WhisperKitRecognizer: SpeechRecognizer, @unchecked Sendable {
  private let transcriber: any Transcribing
  private let modelName: String
  private let bufferProvider: @Sendable () -> Data?
  private let language: String?
  private let partialContinuation: AsyncStream<String>.Continuation
  public let partialTranscript: AsyncStream<String>

  private static let logger = Logger(subsystem: "swiss.weckherlin.tide", category: "whisper-recognizer")

  public init(
    transcriber: any Transcribing,
    modelName: String,
    bufferProvider: @escaping @Sendable () -> Data?,
    language: String?
  ) {
    self.transcriber = transcriber
    self.modelName = modelName
    self.bufferProvider = bufferProvider
    self.language = language
    var continuation: AsyncStream<String>.Continuation!
    self.partialTranscript = AsyncStream<String> { continuation = $0 }
    self.partialContinuation = continuation
  }

  public func start() async throws {
    // Non-streaming: nothing to do. Audio is collected app-side by the
    // AudioBufferAccumulator and handed back via bufferProvider on stop().
  }

  public func feed(_ buffer: AVAudioPCMBuffer) {
    // No-op (see start()).
  }

  public func stop() async throws -> String {
    partialContinuation.finish()
    guard let wav = bufferProvider() else {
      Self.logger.debug("No buffered audio to transcribe.")
      return ""
    }
    do {
      return try await transcriber.transcribe(wav: wav, language: language, modelName: modelName)
    } catch {
      Self.logger.warning("WhisperKit transcribe failed: \(error.localizedDescription, privacy: .public) — returning empty")
      return ""
    }
  }
}
