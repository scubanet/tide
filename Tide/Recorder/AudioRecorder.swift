import Foundation
import AVFoundation
import TideSpeech
import OSLog

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "audio")

/// Captures microphone audio via `AVAudioEngine` and forwards each PCM
/// buffer to an injected `SpeechRecognizer`. The recognizer drives the
/// transcription; this class is just the audio-capture half.
///
/// Lifecycle:
///   1. `start()` — install a tap on the engine's input node, kick off
///      the recognizer, start the engine.
///   2. (audio flows) — tap callbacks call `recognizer.feed(_:)`.
///      `recognizer.partialTranscript` yields partials to subscribers.
///   3. `stop()` — stop the engine, remove the tap, finalize the
///      recognizer, return the final transcript.
@MainActor
final class AudioRecorder {
  private let engine = AVAudioEngine()
  private let recognizer: any SpeechRecognizer
  private var isRunning = false

  /// Parallel PCM-buffer collector. The recognizer-tap pushes each
  /// AVAudioPCMBuffer here as well as into the recognizer, so the
  /// ElevenLabs / Hybrid recognizers can pull a WAV-encoded snapshot
  /// via `bufferAccumulator.exportWAV(...)` on `stop()`.
  ///
  /// Owned by the recorder (not the recognizer) because it's the
  /// recorder that has the tap. Recognizers reference it via a closure
  /// captured at init-time (see `ChatViewModel.makeRecognizer`).
  let bufferAccumulator = AudioBufferAccumulator()

  init(recognizer: any SpeechRecognizer) {
    self.recognizer = recognizer
  }

  /// Live transcript stream from the underlying recognizer. UI binds to
  /// this and shows partial results while the user is speaking.
  var partialTranscript: AsyncStream<String> {
    recognizer.partialTranscript
  }

  func start() async throws {
    guard !isRunning else { return }
    log.debug("AudioRecorder.start: begin")
    // Drop any audio left from a previous session so the next
    // ElevenLabs/Hybrid exportWAV only sees this session's audio.
    bufferAccumulator.reset()
    try await recognizer.start()
    log.debug("AudioRecorder.start: recognizer ready")

    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    log.debug("AudioRecorder.start: input format sampleRate=\(format.sampleRate) channels=\(format.channelCount)")
    guard format.sampleRate > 0, format.channelCount > 0 else {
      log.error("AudioRecorder.start: invalid input format — aborting")
      throw NSError(domain: "Tide.AudioRecorder", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Audio input not available (0 sample rate). Check mic permission."])
    }

    let capturedRecognizer = recognizer
    let capturedAccumulator = bufferAccumulator
    // The tap closure MUST be explicitly `@Sendable` to break the MainActor
    // inheritance from this method's enclosing context. Without it Swift
    // treats the closure as MainActor-isolated, and the audio render thread
    // (which is NOT a Swift task / cooperative-thread) fails the runtime
    // executor check with `_dispatch_assert_queue_fail` the first time a
    // buffer arrives. The closure body only touches Sendable references
    // (the recognizer and the lock-guarded accumulator), so it's safe to
    // run on the audio render thread.
    let block: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { [capturedRecognizer, capturedAccumulator] buffer, _ in
      capturedAccumulator.append(buffer)
      capturedRecognizer.feed(buffer)
    }
    input.installTap(onBus: 0, bufferSize: 1024, format: format, block: block)
    log.debug("AudioRecorder.start: tap installed")

    engine.prepare()
    log.debug("AudioRecorder.start: engine prepared")
    try engine.start()
    log.debug("AudioRecorder.start: engine running")
    isRunning = true
  }

  func stop() async throws -> String {
    guard isRunning else { return "" }
    engine.stop()
    engine.inputNode.removeTap(onBus: 0)
    isRunning = false
    return try await recognizer.stop()
  }
}
