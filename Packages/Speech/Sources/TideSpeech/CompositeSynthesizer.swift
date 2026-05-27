import Foundation

/// Routes `Synthesizer` calls to the currently-selected backend. The
/// app keeps a single `CompositeSynthesizer` and updates its `provider`
/// via `setProvider(_:)` when the user changes the setting. Switching
/// providers stops the previously-active one.
public final class CompositeSynthesizer: Synthesizer, @unchecked Sendable {
  public enum Provider: String, Sendable {
    case apple
    case elevenLabs
  }

  private let apple: any Synthesizer
  private let elevenLabs: (any Synthesizer)?
  private let lock = NSLock()
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
    lock.lock()
    let previousProvider = self.provider
    let changed = previousProvider != provider
    let prev: any Synthesizer = {
      switch previousProvider {
      case .apple: return apple
      case .elevenLabs: return elevenLabs ?? apple
      }
    }()
    self.provider = provider
    lock.unlock()
    if changed { prev.stop() }
  }

  public var currentProvider: Provider {
    lock.lock(); defer { lock.unlock() }
    return provider
  }

  private var active: any Synthesizer {
    lock.lock(); defer { lock.unlock() }
    switch provider {
    case .apple: return apple
    case .elevenLabs: return elevenLabs ?? apple
    }
  }

  public var isSpeaking: Bool { active.isSpeaking }
  public func speak(_ text: String) { active.speak(text) }
  public func stop() { active.stop() }
  public func setVoice(identifier: String) { active.setVoice(identifier: identifier) }
}
