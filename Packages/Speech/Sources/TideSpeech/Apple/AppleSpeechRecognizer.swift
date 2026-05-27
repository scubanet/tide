import Foundation
import Speech
import AVFoundation
import OSLog

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "speech")

/// `SpeechRecognizer` backed by `SFSpeechRecognizer`. Prefers on-device
/// recognition when supported (no audio leaves the Mac). Locale defaults
/// to `de-DE`; instantiate with another locale for English-first users.
public final class AppleSpeechRecognizer: SpeechRecognizer, @unchecked Sendable {
  private let recognizer: SFSpeechRecognizer
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var lastFinalTranscript: String = ""
  private let partialContinuation: AsyncStream<String>.Continuation
  public let partialTranscript: AsyncStream<String>

  public init(locale: Locale = Locale(identifier: "de-DE")) {
    guard let recognizer = SFSpeechRecognizer(locale: locale) else {
      fatalError("SFSpeechRecognizer unavailable for locale \(locale.identifier)")
    }
    self.recognizer = recognizer
    var continuation: AsyncStream<String>.Continuation!
    self.partialTranscript = AsyncStream<String> { continuation = $0 }
    self.partialContinuation = continuation
  }

  public func start() async throws {
    log.debug("requesting speech authorization")
    let status = await Self.requestAuthorization()
    log.debug("speech authorization status: \(status.rawValue)")
    guard status == .authorized else { throw SpeechRecognizerError.unauthorized }
    guard recognizer.isAvailable else {
      log.error("SFSpeechRecognizer not available")
      throw SpeechRecognizerError.unavailable
    }

    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    // Do NOT force on-device — forcing it can hang while the model loads
    // and silently fails on machines where the de-DE on-device model isn't
    // installed. Let Apple pick the best path (cloud-fallback or on-device).
    self.request = req
    self.lastFinalTranscript = ""

    log.debug("creating recognitionTask")
    self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
      if let error {
        log.error("recognitionTask error: \(error.localizedDescription)")
      }
      guard let self = self, let result = result else { return }
      let text = result.bestTranscription.formattedString
      self.lastFinalTranscript = text
      self.partialContinuation.yield(text)
    }
    log.debug("speech recognizer ready")
  }

  public func feed(_ buffer: AVAudioPCMBuffer) {
    request?.append(buffer)
  }

  public func stop() async throws -> String {
    request?.endAudio()
    task?.finish()
    // Small grace period for the final partial result to settle.
    try? await Task.sleep(nanoseconds: 200_000_000)
    let final = lastFinalTranscript
    task = nil
    request = nil
    return final
  }

  private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { cont in
      SFSpeechRecognizer.requestAuthorization { status in
        cont.resume(returning: status)
      }
    }
  }
}
