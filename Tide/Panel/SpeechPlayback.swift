import Foundation
import Core
import TideSpeech

/// Owns everything text-to-speech for the panel: the synthesizer stack
/// (Apple + optional ElevenLabs behind a `CompositeSynthesizer`) and the
/// sentence-buffering of streamed LLM tokens. Extracted from
/// `ChatViewModel` so chat orchestration and speech playback can evolve
/// and be tested separately.
@MainActor
final class SpeechPlayback {
  private let settings: AppSettings
  private let synthesizer: CompositeSynthesizer
  /// Streamed tokens not yet spoken — flushed sentence-by-sentence.
  private var pending = ""

  init(settings: AppSettings) {
    self.settings = settings
    let apple = AppleSynthesizer()
    let elevenLabsKey = KeychainHelper.get(key: KeychainKey.elevenLabs)
    let elevenLabs: ElevenLabsSynthesizer?
    if let key = elevenLabsKey, !key.isEmpty {
      elevenLabs = ElevenLabsSynthesizer(
        client: ElevenLabsClient(apiKey: key),
        defaultVoiceID: settings.elevenLabsVoiceID
      )
    } else {
      elevenLabs = nil
    }
    let ttsProvider: CompositeSynthesizer.Provider =
      (settings.ttsProvider == "elevenLabs") ? .elevenLabs : .apple
    self.synthesizer = CompositeSynthesizer(
      apple: apple,
      elevenLabs: elevenLabs,
      provider: ttsProvider
    )
  }

  /// Feed one streamed token. Speaks each completed sentence as soon as
  /// its terminator (. ! ? followed by whitespace) arrives. No-op when
  /// voice output is disabled.
  func ingest(_ token: String) {
    guard settings.voiceEnabled else { return }
    pending += token
    while let range = pending.range(
      of: #"[\.!\?][\s\n]"#, options: .regularExpression
    ) {
      let sentence = String(pending[..<range.upperBound])
      speakSentence(sentence)
      pending.removeSubrange(..<range.upperBound)
    }
  }

  /// Speak whatever is left in the buffer (stream ended without a
  /// sentence terminator), then clear it.
  func flush() {
    if settings.voiceEnabled, !pending.isEmpty { speakSentence(pending) }
    pending = ""
  }

  /// Drop buffered text without speaking it (error/cancel paths — the
  /// text still lands in the chat, only the audio is muted).
  func discardPending() {
    pending = ""
  }

  /// Stop playback and drop any buffered text. Safe to call when idle.
  func stop() {
    synthesizer.stop()
    pending = ""
  }

  private func speakSentence(_ sentence: String) {
    // Pick up the latest user-chosen provider + voice each sentence.
    let prov: CompositeSynthesizer.Provider =
      (settings.ttsProvider == "elevenLabs") ? .elevenLabs : .apple
    synthesizer.setProvider(prov)
    let voiceID = (prov == .elevenLabs)
      ? settings.elevenLabsVoiceID
      : settings.voiceIdentifier
    synthesizer.setVoice(identifier: voiceID)
    synthesizer.speak(sentence)
  }
}
