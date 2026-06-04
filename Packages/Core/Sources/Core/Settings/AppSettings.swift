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
  @ObservationIgnored private let defaults: UserDefaults

  // Default transform-mode prompts. Single source of truth: the property
  // getters fall back to these, and DictationSection's "restore default"
  // reads the same constants. All language-agnostic ("SAME language").
  public static let defaultPolishPrompt =
    "You are a text editor. Fix grammar and punctuation in the user's text. "
    + "Reply in the SAME language as the input. Keep the meaning 1:1, do not "
    + "shorten, do not add anything, do not explain. Output ONLY the corrected text."
  public static let defaultCalmerPrompt =
    "You are an editor. Rewrite the user's text as a calm, factual, professional "
    + "message. Keep the core point but remove anger, insults and venting. Reply "
    + "in the SAME language as the input. Output ONLY the rewritten message."
  public static let defaultEmojiPrompt =
    "Add a few fitting emojis to the user's text to match its tone. Do not "
    + "otherwise change the wording. Reply in the SAME language. Output ONLY the "
    + "text with emojis."
  public static let defaultBulletsPrompt =
    "Convert the user's spoken thoughts into a clean bullet-point list. Keep all "
    + "key points, add nothing. Reply in the SAME language. Output ONLY the bullet list."
  public static let defaultProfessionalPrompt =
    "Rewrite the user's text in a more formal, professional business tone. Keep "
    + "the meaning, do not add or remove content. Reply in the SAME language. "
    + "Output ONLY the rewritten text."

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
    static let dictationCalmerPrompt = "tide.dictationCalmerPrompt"
    static let dictationEmojiPrompt = "tide.dictationEmojiPrompt"
    static let dictationBulletsPrompt = "tide.dictationBulletsPrompt"
    static let dictationProfessionalPrompt = "tide.dictationProfessionalPrompt"
    static let customVocabulary = "tide.customVocabulary"
    static let localModelName = "tide.localModelName"
  }

  public var selectedModel: String {
    didSet { defaults.set(selectedModel, forKey: Key.selectedModel) }
  }

  /// `nil` (never set) collapses to `true` so first-launch users hear the
  /// response read aloud. Explicit `false` is respected.
  public var voiceEnabled: Bool {
    didSet { defaults.set(voiceEnabled, forKey: Key.voiceEnabled) }
  }

  public var voiceIdentifier: String {
    didSet { defaults.set(voiceIdentifier, forKey: Key.voiceIdentifier) }
  }

  public var replaceSelectionByDefault: Bool {
    didSet { defaults.set(replaceSelectionByDefault, forKey: Key.replaceSelectionByDefault) }
  }

  public var ttsProvider: String {
    didSet { defaults.set(ttsProvider, forKey: Key.ttsProvider) }
  }

  public var elevenLabsVoiceID: String {
    didSet { defaults.set(elevenLabsVoiceID, forKey: Key.elevenLabsVoiceID) }
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
    didSet { defaults.set(speechRecognizer, forKey: Key.speechRecognizer) }
  }

  /// Whether `stopRecording()` should auto-send the transcribed text or
  /// leave it in the input field for the user to edit/extend. `nil`
  /// (first launch) collapses to `true` — that's the existing behavior,
  /// no surprises for upgrading users.
  ///
  /// Set this to `false` to use Tide as a pure dictation tool: speak,
  /// release the hotkey, edit the text, press Enter to send.
  public var autoSendAfterPushToTalk: Bool {
    didSet { defaults.set(autoSendAfterPushToTalk, forKey: Key.autoSendAfterPushToTalk) }
  }

  /// System prompt used by the polished-dictation hotkey (Tide v0.3.0,
  /// Welle 4 — see `docs/specs/2026-05-28-standalone-dictation-design.md`).
  /// Sent to Claude before the raw transcript to clean up grammar +
  /// punctuation. The default is intentionally language-agnostic so
  /// it works for DE/EN/FR inputs without per-language tuning; the
  /// model is instructed to reply in the same language as the input.
  public var dictationPolishPrompt: String {
    didSet { defaults.set(dictationPolishPrompt, forKey: Key.dictationPolishPrompt) }
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
    didSet { defaults.set(dictationPillPosition, forKey: Key.dictationPillPosition) }
  }

  public var dictationCalmerPrompt: String {
    didSet { defaults.set(dictationCalmerPrompt, forKey: Key.dictationCalmerPrompt) }
  }
  public var dictationEmojiPrompt: String {
    didSet { defaults.set(dictationEmojiPrompt, forKey: Key.dictationEmojiPrompt) }
  }
  public var dictationBulletsPrompt: String {
    didSet { defaults.set(dictationBulletsPrompt, forKey: Key.dictationBulletsPrompt) }
  }
  public var dictationProfessionalPrompt: String {
    didSet { defaults.set(dictationProfessionalPrompt, forKey: Key.dictationProfessionalPrompt) }
  }

  /// User-maintained domain terms (e.g. "PADI", "SeaExplorers") that bias
  /// the Apple speech recognizer and are injected into the polish prompt.
  /// Stored normalised (trimmed, blank-free); `didSet` persists it as a
  /// newline-joined string so consumers never see empty entries.
  public var customVocabulary: [String] {
    didSet { defaults.set(customVocabulary.joined(separator: "\n"), forKey: Key.customVocabulary) }
  }

  /// Which WhisperKit model the local recognizer uses. Stored as the
  /// model's catalog id. Default: Whisper Small (fastest, 216 MB).
  public var localModelName: String {
    didSet { defaults.set(localModelName, forKey: Key.localModelName) }
  }

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    // Assigning in init does NOT fire didSet → no redundant write-back.
    self.selectedModel = defaults.string(forKey: Key.selectedModel) ?? "claude-sonnet-4-6"
    self.voiceEnabled = defaults.object(forKey: Key.voiceEnabled) as? Bool ?? true
    self.voiceIdentifier = defaults.string(forKey: Key.voiceIdentifier) ?? "com.apple.voice.compact.de-DE.Anna"
    self.replaceSelectionByDefault = defaults.bool(forKey: Key.replaceSelectionByDefault)
    self.ttsProvider = defaults.string(forKey: Key.ttsProvider) ?? "apple"
    self.elevenLabsVoiceID = defaults.string(forKey: Key.elevenLabsVoiceID) ?? "21m00Tcm4TlvDq8ikWAM"
    self.speechRecognizer = defaults.string(forKey: Key.speechRecognizer) ?? "hybrid"
    self.autoSendAfterPushToTalk = defaults.object(forKey: Key.autoSendAfterPushToTalk) as? Bool ?? true
    self.dictationPolishPrompt = defaults.string(forKey: Key.dictationPolishPrompt) ?? Self.defaultPolishPrompt
    self.dictationPillPosition = defaults.string(forKey: Key.dictationPillPosition) ?? "topCenter"
    self.dictationCalmerPrompt = defaults.string(forKey: Key.dictationCalmerPrompt) ?? Self.defaultCalmerPrompt
    self.dictationEmojiPrompt = defaults.string(forKey: Key.dictationEmojiPrompt) ?? Self.defaultEmojiPrompt
    self.dictationBulletsPrompt = defaults.string(forKey: Key.dictationBulletsPrompt) ?? Self.defaultBulletsPrompt
    self.dictationProfessionalPrompt = defaults.string(forKey: Key.dictationProfessionalPrompt) ?? Self.defaultProfessionalPrompt
    self.customVocabulary = Self.parseVocabulary(defaults.string(forKey: Key.customVocabulary) ?? "")
    self.localModelName = defaults.string(forKey: Key.localModelName) ?? "openai_whisper-small_216MB"
  }

  private static func parseVocabulary(_ raw: String) -> [String] {
    raw.split(separator: "\n", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }
}
