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
}
