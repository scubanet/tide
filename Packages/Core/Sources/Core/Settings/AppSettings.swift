import Foundation
import Observation

/// Observable `UserDefaults` wrapper for app-wide preferences. Settings
/// that are sensitive (API keys) go through `KeychainHelper` instead.
///
/// The defaults chosen here are the "first-run sensible" ones documented
/// in the design spec: Claude Sonnet 4.6, voice on with German voice,
/// replace-selection off (opt-in, not opt-out).
@Observable
@MainActor
public final class AppSettings {
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  private enum Key {
    static let selectedModel = "tide.selectedModel"
    static let voiceEnabled = "tide.voiceEnabled"
    static let voiceIdentifier = "tide.voiceIdentifier"
    static let replaceSelectionByDefault = "tide.replaceSelectionByDefault"
    static let ttsProvider = "tide.ttsProvider"
    static let elevenLabsVoiceID = "tide.elevenLabsVoiceID"
    static let speechRecognizer = "tide.speechRecognizer"
    static let autoSendAfterPushToTalk = "tide.autoSendAfterPushToTalk"
    static let dictationPolishPrompt = "tide.dictationPolishPrompt"
    static let dictationPillPosition = "tide.dictationPillPosition"
    static let customVocabulary = "tide.customVocabulary"
  }

  public var selectedModel: String {
    get { defaults.string(forKey: Key.selectedModel) ?? "claude-sonnet-4-6" }
    set { defaults.set(newValue, forKey: Key.selectedModel) }
  }

  /// `nil` (never set) collapses to `true` so first-launch users hear the
  /// response read aloud. Explicit `false` is respected.
  public var voiceEnabled: Bool {
    get { defaults.object(forKey: Key.voiceEnabled) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.voiceEnabled) }
  }

  public var voiceIdentifier: String {
    get { defaults.string(forKey: Key.voiceIdentifier) ?? "com.apple.voice.compact.de-DE.Anna" }
    set { defaults.set(newValue, forKey: Key.voiceIdentifier) }
  }

  public var replaceSelectionByDefault: Bool {
    get { defaults.bool(forKey: Key.replaceSelectionByDefault) }
    set { defaults.set(newValue, forKey: Key.replaceSelectionByDefault) }
  }

  public var ttsProvider: String {
    get { defaults.string(forKey: Key.ttsProvider) ?? "apple" }
    set { defaults.set(newValue, forKey: Key.ttsProvider) }
  }

  public var elevenLabsVoiceID: String {
    get { defaults.string(forKey: Key.elevenLabsVoiceID) ?? "21m00Tcm4TlvDq8ikWAM" }  // Rachel
    set { defaults.set(newValue, forKey: Key.elevenLabsVoiceID) }
  }

  /// Which speech recognizer to use. Stored as the raw-string of
  /// `TideSpeech.SpeechRecognizerChoice`. Default: `"hybrid"`.
  ///
  /// Stored as `String` (rather than the typed enum) to keep the `Core`
  /// package free of any dependency on `TideSpeech`, mirroring the
  /// existing `ttsProvider` pattern above. Call sites in the app layer
  /// (`ChatViewModel`, `VoiceSection`) bridge to/from the typed enum
  /// via `SpeechRecognizerChoice(rawValue:)`.
  public var speechRecognizer: String {
    get { defaults.string(forKey: Key.speechRecognizer) ?? "hybrid" }
    set { defaults.set(newValue, forKey: Key.speechRecognizer) }
  }

  /// Whether `stopRecording()` should auto-send the transcribed text or
  /// leave it in the input field for the user to edit/extend. `nil`
  /// (first launch) collapses to `true` — that's the existing behavior,
  /// no surprises for upgrading users.
  ///
  /// Set this to `false` to use Tide as a pure dictation tool: speak,
  /// release the hotkey, edit the text, press Enter to send.
  public var autoSendAfterPushToTalk: Bool {
    get { defaults.object(forKey: Key.autoSendAfterPushToTalk) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.autoSendAfterPushToTalk) }
  }

  /// System prompt used by the polished-dictation hotkey (Tide v0.3.0,
  /// Welle 4 — see `docs/specs/2026-05-28-standalone-dictation-design.md`).
  /// Sent to Claude before the raw transcript to clean up grammar +
  /// punctuation. The default is intentionally language-agnostic so
  /// it works for DE/EN/FR inputs without per-language tuning; the
  /// model is instructed to reply in the same language as the input.
  public var dictationPolishPrompt: String {
    get {
      defaults.string(forKey: Key.dictationPolishPrompt)
        ?? "You are a text editor. Fix grammar and punctuation in the user's text. Reply in the SAME language as the input. Keep the meaning 1:1, do not shorten, do not add anything, do not explain. Output ONLY the corrected text."
    }
    set { defaults.set(newValue, forKey: Key.dictationPolishPrompt) }
  }

  /// Screen-corner placement of the floating dictation pill that shows
  /// the live Apple-partial transcript during a dictation session
  /// (Tide v0.3.0, Welle 4 — see
  /// `docs/specs/2026-05-28-standalone-dictation-design.md`). Stored
  /// as a raw `String` to keep the `Core` package free of any AppKit
  /// dependency. Valid values: `"topRight"`, `"topCenter"`,
  /// `"bottomRight"`. Default `"topCenter"` — sits just under the
  /// menubar without covering app-window content on either side.
  public var dictationPillPosition: String {
    get { defaults.string(forKey: Key.dictationPillPosition) ?? "topCenter" }
    set { defaults.set(newValue, forKey: Key.dictationPillPosition) }
  }

  /// User-maintained domain terms (e.g. "PADI", "SeaExplorers") that bias
  /// the Apple speech recognizer and are injected into the polish prompt.
  /// Persisted as a newline-joined string; the getter normalises it into a
  /// trimmed, blank-free list so consumers never see empty entries.
  public var customVocabulary: [String] {
    get {
      (defaults.string(forKey: Key.customVocabulary) ?? "")
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    }
    set {
      defaults.set(newValue.joined(separator: "\n"), forKey: Key.customVocabulary)
    }
  }
}
