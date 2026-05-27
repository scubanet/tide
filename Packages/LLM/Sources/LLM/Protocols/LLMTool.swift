import Foundation

/// A tool that the LLM may call. v1 leaves this list empty; future
/// phases (Mac-app integration) populate it with AppleScript/JXA/App-
/// Intents wrappers.
///
/// `inputSchemaJSON` is a JSON-Schema document as a string; we let the
/// provider impl decide how to embed it in its request format.
public struct LLMTool: Sendable, Codable, Equatable {
  public let name: String
  public let description: String
  public let inputSchemaJSON: String

  public init(name: String, description: String, inputSchemaJSON: String) {
    self.name = name
    self.description = description
    self.inputSchemaJSON = inputSchemaJSON
  }
}
