import Foundation

/// Text-to-speech abstraction. Main-actor isolated: playback state
/// (players, queues, the underlying AV objects) lives in a single
/// isolation domain, so implementations need no locks and the type
/// system enforces what convention used to. Callers (the streaming-LLM
/// token loop, Settings) already run on the main actor.
@MainActor
public protocol Synthesizer: Sendable {
  /// Queue `text` for playback. Returns immediately. Speech happens
  /// asynchronously on the audio output.
  func speak(_ text: String)

  /// Cancel any queued or in-flight utterances.
  func stop()

  /// Update which voice subsequent `speak(_:)` calls should use.
  /// Already-queued utterances keep their original voice.
  func setVoice(identifier: String)

  /// Whether playback is currently active. Useful for UI toggles.
  var isSpeaking: Bool { get }
}
