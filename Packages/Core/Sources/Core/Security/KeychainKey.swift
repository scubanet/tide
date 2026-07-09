import Foundation

/// Central registry of Tide's keychain account names. Always reference
/// these constants — a typo in a hand-typed literal fails silently
/// (`KeychainHelper.get` returns `nil`, indistinguishable from "no key").
public enum KeychainKey {
  public static let anthropic = "anthropic.api_key"
  public static let elevenLabs = "elevenlabs.api_key"
}
