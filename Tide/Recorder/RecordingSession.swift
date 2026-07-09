import Foundation
import Core
import TideSpeech

/// Builds the `AudioRecorder` (with its recognizer + shared
/// `AudioBufferAccumulator`) for one recording session from the current
/// settings. The single code path shared by the panel's push-to-talk
/// flow (`ChatViewModel`) and the standalone `DictationCoordinator` —
/// a change to the session wiring or the recognizer choice logic only
/// has to happen here.
@MainActor
enum RecordingSession {
  static func makeRecorder(settings: AppSettings) -> AudioRecorder {
    let choice = SpeechRecognizerChoice(rawValue: settings.speechRecognizer) ?? .default
    let apiKey = KeychainHelper.get(key: KeychainKey.elevenLabs)
    // The *same* accumulator instance goes to both the recognizer (its
    // bufferProvider pulls WAV data on stop()) and the AudioRecorder
    // (its tap pushes PCM into it).
    let accumulator = AudioBufferAccumulator()
    let localStore = WhisperModelStore()
    let recognizer = RecognizerFactory.make(
      for: choice,
      apiKey: apiKey,
      accumulator: accumulator,
      vocabulary: settings.customVocabulary,
      localModelName: settings.localModelName,
      localModelInstalled: localStore.isInstalled(settings.localModelName),
      transcriber: LocalTranscriberHolder.shared.transcriber
    )
    return AudioRecorder(recognizer: recognizer, bufferAccumulator: accumulator)
  }
}
