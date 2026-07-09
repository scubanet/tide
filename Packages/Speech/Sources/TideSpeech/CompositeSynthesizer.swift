import Foundation

/// Routes `Synthesizer` calls to the currently-selected backend. The
/// app keeps a single `CompositeSynthesizer` and updates its `provider`
/// via `setProvider(_:)` when the user changes the setting. Switching
/// providers stops the previously-active one.
public final class CompositeSynthesizer: Synthesizer {
  public enum Provider: String, Sendable {
    case apple
    case elevenLabs
  }

  private let apple: any Synthesizer
  private let elevenLabs: (any Synthesizer)?
  private var provider: Provider

  public init(
    apple: any Synthesizer,
    elevenLabs: (any Synthesizer)? = nil,
    provider: Provider = .apple
  ) {
    self.apple = apple
    self.elevenLabs = elevenLabs
    self.provider = provider
  }

  public func setProvider(_ provider: Provider) {
    let previousProvider = self.provider
    self.provider = provider
    if previousProvider != provider {
      resolve(previousProvider).stop()
    }
  }

  public var currentProvider: Provider { provider }

  private func resolve(_ provider: Provider) -> any Synthesizer {
    switch provider {
    case .apple: return apple
    case .elevenLabs: return elevenLabs ?? apple
    }
  }

  private var active: any Synthesizer { resolve(provider) }

  public var isSpeaking: Bool { active.isSpeaking }
  public func speak(_ text: String) { active.speak(text) }
  public func stop() { active.stop() }
  public func setVoice(identifier: String) { active.setVoice(identifier: identifier) }
}
