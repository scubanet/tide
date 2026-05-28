import Foundation
import TideSpeech

/// Builds the `SpeechRecognizer` matching the user's Settings choice.
///
/// Lifted out of `ChatViewModel.makeRecognizer` so both the panel-side
/// push-to-talk path and the standalone `DictationCoordinator` produce
/// recognizers the exact same way. Behavior is byte-identical to the
/// original private method.
///
/// - Apple: pure `AppleSpeechRecognizer`.
/// - ElevenLabs: `ElevenLabsRecognizer` with a bufferProvider that
///   captures the caller-supplied `AudioBufferAccumulator` directly.
///   The same accumulator must also be handed to `AudioRecorder` so
///   its tap pushes PCM into it. No `self`, no MainActor-hop —
///   `AudioBufferAccumulator` is `@unchecked Sendable` (internal NSLock),
///   safe to read from any thread.
/// - Hybrid: composes Apple (live partials) + ElevenLabs (final replace).
///
/// Fallback: if a non-Apple choice is selected but no API key is set,
/// silently fall back to Apple. The Settings-Picker enforces the key
/// constraint with a visible warning; this is the runtime safety-net.
@MainActor
enum RecognizerFactory {
  /// Builds the SpeechRecognizer matching the user's Settings choice.
  ///
  /// - Parameters:
  ///   - choice: which recognizer the user selected
  ///   - apiKey: ElevenLabs API key (nil/empty → falls back to Apple)
  ///   - accumulator: shared PCM buffer collector; must be the same
  ///     instance the AudioRecorder taps into
  static func make(
    for choice: SpeechRecognizerChoice,
    apiKey: String?,
    accumulator: AudioBufferAccumulator
  ) -> any SpeechRecognizer {
    let apple = AppleSpeechRecognizer()

    guard choice != .apple, let key = apiKey, !key.isEmpty else {
      return apple
    }

    let client = ElevenLabsClient(apiKey: key)
    let elevenRecognizer = ElevenLabsRecognizer(
      client: client,
      bufferProvider: {
        // Pure value-capture of the accumulator (Sendable).
        // No `self`, no MainActor — safe from any executor.
        accumulator.exportWAV(sampleRate: 16000, channels: 1)
      }
    )

    switch choice {
    case .elevenLabs:
      return elevenRecognizer
    case .hybrid:
      return HybridRecognizer(apple: apple, eleven: elevenRecognizer)
    case .apple:
      // Unreachable per the guard above, but the switch needs to be
      // exhaustive over the enum.
      return apple
    }
  }
}
