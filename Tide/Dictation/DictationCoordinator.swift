import Foundation
import OSLog
import AppKit
import UserNotifications
import Core
import LLM
import TideSpeech
import Selection

/// Which post-processing path a dictation session should take after the
/// recognizer returns its final text.
///
/// - `.raw`: insert the transcript verbatim (Phase D).
/// - `.polished`: route through Claude for grammar/punctuation cleanup
///   first, then insert (Phase E).
enum DictationMode {
  case raw
  case polished
}

/// Orchestrates a single standalone-dictation session start-to-finish.
///
/// Mirrors the shape of `ChatViewModel.startRecording` + `stopRecording`
/// but bypasses the Tide panel entirely — the user stays in whichever
/// app they were typing in, and the final transcript is delivered into
/// that app's text cursor (Phase D) without Tide stealing focus.
///
/// **Phase B scope (this file's current state):**
///   - Owns its own `AudioRecorder` + recognizer via `RecognizerFactory`.
///   - `start(mode:)` begins recording; `stop()` ends it and logs the
///     final transcript.
///   - No indicator UI yet (Phase C), no text injection (Phase D),
///     no polish step (Phase E). The `provider` is wired in early so
///     Phase E only has to use it.
///
/// Concurrency: a second `start(mode:)` while `isActive` is dropped
/// (logged, ignored). Single source of truth: `recorder != nil`.
@MainActor
final class DictationCoordinator {
  private let settings: AppSettings
  /// Wired now, used in Phase E for the polished-mode Claude call.
  private let provider: any LLMProvider
  /// Phase E: runs the raw transcript through Claude with the user's
  /// editable polish prompt. Constructed up-front so `stop()` can call
  /// it synchronously on the .polished branch.
  private let polisher: DictationPolisher
  private var recorder: AudioRecorder?
  private var currentMode: DictationMode = .raw
  /// Visual feedback (menubar tint + floating pill). Optional because
  /// `MenubarController` (which owns the `NSStatusItem`) is built before
  /// the coordinator in `AppEntry`, so the indicator gets attached
  /// after-the-fact via `attachIndicator(_:)`.
  private var indicator: DictationIndicator?
  /// Background task that drains the recorder's `partialTranscript`
  /// stream into the indicator's pill. Cancelled on `stop()`.
  private var partialTask: Task<Void, Never>?

  /// One-at-a-time lock. A second `start()` while non-idle is dropped.
  var isActive: Bool { recorder != nil }

  private static let logger = Logger(
    subsystem: "swiss.weckherlin.tide",
    category: "dictation"
  )

  init(settings: AppSettings, provider: any LLMProvider) {
    self.settings = settings
    self.provider = provider
    self.polisher = DictationPolisher(provider: provider, settings: settings)
  }

  /// Inject the visual indicator after construction. AppEntry calls this
  /// once the `MenubarController` (which owns the `NSStatusItem`) is
  /// ready.
  func attachIndicator(_ indicator: DictationIndicator) {
    self.indicator = indicator
  }

  /// Begin a dictation session. If one is already in flight the call is
  /// silently ignored (logged at debug level).
  func start(mode: DictationMode) async {
    guard !isActive else {
      Self.logger.debug("start(\(String(describing: mode), privacy: .public)) ignored — already active")
      return
    }
    currentMode = mode
    // Build the recognizer + recorder via the shared factory so we use
    // the exact same code path as the panel-side push-to-talk flow.
    let choice = SpeechRecognizerChoice(rawValue: settings.speechRecognizer) ?? .default
    let apiKey = KeychainHelper.get(key: "elevenlabs.api_key")
    let accumulator = AudioBufferAccumulator()
    let recognizer = RecognizerFactory.make(
      for: choice,
      apiKey: apiKey,
      accumulator: accumulator
    )
    let rec = AudioRecorder(
      recognizer: recognizer,
      bufferAccumulator: accumulator
    )
    self.recorder = rec
    do {
      try await rec.start()
      Self.logger.debug("recording started (mode: \(String(describing: mode), privacy: .public))")
      // Phase C: show visual feedback and start draining live partials
      // into the floating pill. The pill is non-activating so this never
      // steals focus from the source app.
      indicator?.show()
      let partials = rec.partialTranscript
      partialTask = Task { [weak self] in
        for await partial in partials {
          guard !Task.isCancelled else { return }
          await MainActor.run { self?.indicator?.update(partial: partial) }
        }
      }
    } catch {
      Self.logger.error("AudioRecorder.start failed: \(error.localizedDescription, privacy: .public)")
      self.recorder = nil
    }
  }

  /// End the in-flight dictation session. No-op if idle.
  ///
  /// Phase B: logs the final transcript to OSLog and stops. Phases D/E
  /// will route the trimmed text through `TextInjector` (and, for
  /// `.polished`, through `DictationPolisher` first).
  func stop() async {
    guard let rec = recorder else { return }
    self.recorder = nil
    // Tear down the visual feedback *before* awaiting the final
    // recognizer flush. The user already lifted the hotkey — the icon
    // reverting + the pill fading out is immediate confirmation that
    // recording stopped. The async transcript / future injection runs
    // in the background and shouldn't block the user-visible "done"
    // signal.
    partialTask?.cancel()
    partialTask = nil
    indicator?.hide()
    do {
      let finalText = try await rec.stop()
      let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
      let duration = rec.bufferAccumulator.duration
      Self.logger.debug("final transcript (mode \(String(describing: self.currentMode), privacy: .public)): '\(trimmed, privacy: .public)' (\(duration, privacy: .public)s)")
      let isReject = trimmed.isEmpty
        || TranscriptionQuality.shouldRejectRecording(duration: duration)
        || TranscriptionQuality.isLikelyArtifact(trimmed, recordingDuration: duration)
      guard !isReject else {
        // Too short / likely a hallucination. Flash a hint on the pill
        // (it was already hidden before the await) instead of inserting
        // garbage at the user's cursor.
        Self.logger.debug("rejected transcript — flashing pill hint")
        indicator?.flash("Nichts erkannt")
        return
      }
      switch self.currentMode {
      case .raw:
        let result = await TextInjector.insert(trimmed)
        Self.logger.debug("text-injector result: \(String(describing: result), privacy: .public)")
      case .polished:
        // Phase E: route through Claude first. Any failure mode
        // (no API key, network/5xx, timeout, empty response) is caught
        // and degrades to the raw transcript + a notification so the
        // user always lands their dictation somewhere.
        do {
          let polished = try await polisher.polish(trimmed)
          let result = await TextInjector.insert(polished)
          Self.logger.debug("polish result: \(String(describing: result), privacy: .public)")
        } catch {
          Self.logger.warning(
            "polish failed: \(String(describing: error), privacy: .public) — injecting raw"
          )
          let result = await TextInjector.insert(trimmed)
          Self.logger.debug(
            "polish-fallback (raw) result: \(String(describing: result), privacy: .public)"
          )
          await notifyPolishFailed()
        }
      }
    } catch {
      Self.logger.error("recognizer.stop failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Post a "polish failed, raw text inserted" user notification. Lazy
  /// authorization on first use, denial degrades silently (the raw text
  /// was already injected, so a missing toast is not user-blocking).
  ///
  /// `UNUserNotificationCenter.requestAuthorization` is idempotent, so
  /// calling it here as well as inside `TextInjector` is fine — the
  /// system collapses repeat requests to the cached grant/deny answer
  /// without prompting twice.
  private func notifyPolishFailed() async {
    let center = UNUserNotificationCenter.current()
    let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
    guard granted else {
      Self.logger.warning(
        "notification permission denied — polish-failed notice skipped"
      )
      return
    }
    let content = UNMutableNotificationContent()
    content.title = "Tide — Diktat"
    content.body = "Polish-Modus fehlgeschlagen, Rohtext eingefügt"
    let request = UNNotificationRequest(
      identifier: "tide.dictation.polishfailed.\(UUID().uuidString)",
      content: content,
      trigger: nil
    )
    do {
      try await center.add(request)
    } catch {
      Self.logger.warning(
        "posting polish-failed notification failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}
