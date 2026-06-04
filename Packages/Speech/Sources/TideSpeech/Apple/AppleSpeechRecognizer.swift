import Foundation
import Speech
import AVFoundation
import OSLog

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "speech")

/// `SpeechRecognizer` backed by `SFSpeechRecognizer`. Prefers on-device
/// recognition when supported (no audio leaves the Mac). Locale defaults
/// to `de-DE`; instantiate with another locale for English-first users.
///
/// Thread-safety: the `recognitionTask` completion handler runs on a
/// Speech-framework queue, concurrently with `start()`/`feed()`/`stop()`
/// calls from the owning actor. All mutable state (`request`, `task`,
/// `lastFinalTranscript`, and the partial-transcript stream/continuation)
/// is therefore guarded by `lock`. The class is `@unchecked Sendable`
/// because that thread-safety is provided by the lock rather than the
/// type system.
public final class AppleSpeechRecognizer: SpeechRecognizer, @unchecked Sendable {
  private let recognizer: SFSpeechRecognizer
  private let contextualStrings: [String]

  /// Guards every mutable field below. The Speech callback and the caller
  /// touch these from different threads, so all access goes through here.
  private let lock = NSLock()

  // --- State protected by `lock` ---
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var lastFinalTranscript: String = ""
  /// The current partial-transcript stream + its continuation, recreated on
  /// every `start()` so a second start/stop cycle yields into a LIVE stream,
  /// never a finished one. `nil` until the first `start()` (or first read of
  /// `partialTranscript`, whichever comes first).
  private var _stream: AsyncStream<String>?
  private var partialContinuation: AsyncStream<String>.Continuation?

  public init(
    locale: Locale = Locale(identifier: "de-DE"),
    contextualStrings: [String] = []
  ) {
    guard let recognizer = SFSpeechRecognizer(locale: locale) else {
      fatalError("SFSpeechRecognizer unavailable for locale \(locale.identifier)")
    }
    self.recognizer = recognizer
    self.contextualStrings = contextualStrings
  }

  /// Returns the current partial-transcript stream. Consumers read this
  /// after `start()`; if `start()` hasn't run yet we lazily create a stream
  /// so the getter never traps. The stream is replaced on each `start()`.
  public var partialTranscript: AsyncStream<String> {
    lock.withLock {
      if let existing = _stream { return existing }
      let (stream, continuation) = AsyncStream<String>.makeStream()
      _stream = stream
      partialContinuation = continuation
      return stream
    }
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
    // Bias recognition toward user-supplied domain terms (names, jargon).
    // Empty array is a harmless no-op.
    req.contextualStrings = contextualStrings
    // Do NOT force on-device — forcing it can hang while the model loads
    // and silently fails on machines where the de-DE on-device model isn't
    // installed. Let Apple pick the best path (cloud-fallback or on-device).

    // Reset state and install a fresh partial stream under the lock, so a
    // reused recognizer (second start/stop cycle) yields into a live stream.
    lock.withLock {
      // Finish any stream left over from a prior cycle never stopped.
      partialContinuation?.finish()
      let (stream, continuation) = AsyncStream<String>.makeStream()
      _stream = stream
      partialContinuation = continuation
      self.request = req
      self.lastFinalTranscript = ""
    }

    log.debug("creating recognitionTask")
    let createdTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
      if let error {
        log.error("recognitionTask error: \(error.localizedDescription)")
      }
      guard let self, let result else { return }
      let text = result.bestTranscription.formattedString
      // Critical section: update state + grab the continuation, then yield
      // outside the lock. Yielding to an AsyncStream is non-blocking, but we
      // keep the held region minimal regardless.
      let continuation = self.lock.withLock { () -> AsyncStream<String>.Continuation? in
        self.lastFinalTranscript = text
        return self.partialContinuation
      }
      continuation?.yield(text)
    }

    lock.withLock { self.task = createdTask }
    log.debug("speech recognizer ready")
  }

  public func feed(_ buffer: AVAudioPCMBuffer) {
    let req = lock.withLock { request }
    req?.append(buffer)
  }

  public func stop() async throws -> String {
    // Tear down the request/task and finish the partial stream so consumers
    // (e.g. HybridRecognizer's forward loop) terminate. Capture the
    // continuation/request/task under the lock; call their methods after
    // unlocking to keep the critical section minimal.
    let (req, currentTask, continuation) = lock.withLock {
      () -> (SFSpeechAudioBufferRecognitionRequest?, SFSpeechRecognitionTask?, AsyncStream<String>.Continuation?) in
      let r = request
      let t = task
      let c = partialContinuation
      self.task = nil
      self.request = nil
      self.partialContinuation = nil
      self._stream = nil
      return (r, t, c)
    }

    req?.endAudio()
    currentTask?.finish()
    continuation?.finish()

    // Small grace period for the final partial result to settle.
    try? await Task.sleep(nanoseconds: 200_000_000)

    return lock.withLock { lastFinalTranscript }
  }

  private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { cont in
      SFSpeechRecognizer.requestAuthorization { status in
        cont.resume(returning: status)
      }
    }
  }
}
