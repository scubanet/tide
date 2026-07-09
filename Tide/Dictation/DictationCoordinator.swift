import Foundation
import OSLog
import AppKit
import UserNotifications
import Core
import LLM
import TideSpeech
import Selection

/// Which post-processing path a dictation session takes after the
/// recognizer returns its final text. `raw` inserts verbatim; every other
/// case routes the transcript through `DictationPolisher` with that mode's
/// editable base prompt.
enum DictationMode: String, CaseIterable, Sendable {
  case raw
  case polished
  case calmer
  case emoji
  case bullets
  case professional

  var isRaw: Bool { self == .raw }

  /// The editable base prompt for this transform mode, or `nil` for `.raw`.
  @MainActor
  func basePrompt(from settings: AppSettings) -> String? {
    switch self {
    case .raw:          nil
    case .polished:     settings.dictationPolishPrompt
    case .calmer:       settings.dictationCalmerPrompt
    case .emoji:        settings.dictationEmojiPrompt
    case .bullets:      settings.dictationBulletsPrompt
    case .professional: settings.dictationProfessionalPrompt
    }
  }
}

/// Orchestrates a single standalone-dictation session start-to-finish.
///
/// Mirrors the shape of `ChatViewModel.startRecording` + `stopRecording`
/// but bypasses the Tide panel entirely — the user stays in whichever
/// app they were typing in, and the final transcript is delivered into
/// that app's text cursor (Phase D) without Tide stealing focus.
///
/// Owns its own `AudioRecorder` + recognizer via `RecognizerFactory`.
/// `start(mode:)` begins recording and shows the floating pill;
/// `stop()` finalizes the transcript, optionally runs it through the
/// transform prompt (`DictationPolisher`, with raw-text fallback on
/// failure), and inserts the result at the frontmost app's cursor via
/// `TextInjector`.
///
/// Concurrency: a second `start(mode:)` while `isActive` is dropped
/// (logged, ignored). Single source of truth: `recorder != nil`.
@MainActor
final class DictationCoordinator {
  private let settings: AppSettings
  /// Used for the transform-mode Claude call.
  private let provider: any LLMProvider
  /// Runs the raw transcript through Claude with the user's editable
  /// polish prompt. Constructed up-front so `stop()` can call it
  /// synchronously on the transform branches.
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
    let rec = RecordingSession.makeRecorder(settings: settings)
    self.recorder = rec
    do {
      try await rec.start()
      // A stop() may have fired during the await (fast tap), nilling
      // `recorder`. If so, this session is stale — tear it down instead of
      // leaving a running engine with no way to stop it.
      guard self.recorder === rec else {
        Self.logger.debug("start: session superseded during await — tearing down")
        _ = try? await rec.stop()
        return
      }
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

  /// End the in-flight dictation session. No-op if idle. Finalizes the
  /// transcript, applies the transform prompt when the mode asks for one
  /// (raw fallback on failure), and inserts the result at the frontmost
  /// app's cursor.
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
      Self.logger.debug("final transcript (mode \(String(describing: self.currentMode), privacy: .public)): \(trimmed.count) chars (\(duration, privacy: .public)s)")
      guard !TranscriptionQuality.isReject(trimmed, duration: duration) else {
        // Too short / likely a hallucination. Flash a hint on the pill
        // (it was already hidden before the await) instead of inserting
        // garbage at the user's cursor.
        Self.logger.debug("rejected transcript — flashing pill hint")
        indicator?.flash("Nichts erkannt")
        return
      }
      if self.currentMode.isRaw {
        let result = await TextInjector.insert(trimmed)
        Self.logger.debug("text-injector result: \(String(describing: result), privacy: .public)")
      } else {
        let base = self.currentMode.basePrompt(from: settings) ?? ""
        do {
          let transformed = try await polisher.polish(trimmed, basePrompt: base)
          let result = await TextInjector.insert(transformed)
          Self.logger.debug("transform (\(self.currentMode.rawValue, privacy: .public)) result: \(String(describing: result), privacy: .public)")
        } catch {
          Self.logger.warning(
            "transform failed: \(String(describing: error), privacy: .public) — injecting raw"
          )
          let result = await TextInjector.insert(trimmed)
          Self.logger.debug(
            "transform-fallback (raw) result: \(String(describing: result), privacy: .public)"
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
  private func notifyPolishFailed() async {
    await TideNotification.post(
      body: "Polish-Modus fehlgeschlagen, Rohtext eingefügt",
      idPrefix: "tide.dictation.polishfailed"
    )
  }
}
