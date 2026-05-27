import Foundation

/// A chat turn passed to an LLM provider. Mirrors the Anthropic/OpenAI
/// shape: a role plus a content string. Multimodal content (images, etc.)
/// is not modeled in v1 — extend later if needed.
public struct LLMMessage: Sendable, Equatable {
  public let role: Role
  public let content: String

  public enum Role: String, Sendable, Codable {
    case user
    case assistant
    case system
    case tool
  }

  public init(role: Role, content: String) {
    self.role = role
    self.content = content
  }
}
