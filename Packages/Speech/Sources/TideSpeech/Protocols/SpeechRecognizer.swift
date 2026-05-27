import Foundation
import AVFoundation

/// Push-to-talk speech recognition. The caller drives the lifecycle:
///
/// 1. `start()` — request permission, begin a fresh recognition task.
///    Throws `SpeechRecognizerError.unauthorized` if the user has denied
///    speech-recognition or microphone access.
/// 2. `feed(_:)` — push PCM audio buffers (typically from an
///    `AVAudioEngine` tap). Idempotent and re-entrant; just appends to
///    the in-flight recognition request.
/// 3. `partialTranscript` — an `AsyncStream<String>` that yields the
///    best-so-far transcription as the user speaks. UIs subscribe to
///    this to show live text in the input field.
/// 4. `stop()` — finalize the recognition task and return the final
///    transcript. After this returns, `start()` may be called again.
public protocol SpeechRecognizer: Sendable {
  func start() async throws
  func feed(_ buffer: AVAudioPCMBuffer)
  func stop() async throws -> String
  var partialTranscript: AsyncStream<String> { get }
}

public enum SpeechRecognizerError: Error, Sendable {
  case unauthorized
  case unavailable
  case generic(String)
}
