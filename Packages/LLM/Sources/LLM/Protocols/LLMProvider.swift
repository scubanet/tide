import Foundation

/// The single abstraction every chat backend implements. v1 ships only
/// `AnthropicProvider`; OpenAI/Gemini/Ollama/Whisper-via-... are designed
/// to plug in here.
public protocol LLMProvider: Sendable {
  /// Stream a completion for the given chat history. Yields `LLMChunk`
  /// events as they arrive over the wire, throws `LLMError` (mapped from
  /// the provider's native error shape) on failure.
  ///
  /// `tools` may be empty (v1 default — no tool use). When non-empty, the
  /// stream may emit `.toolUse` chunks the caller must service before the
  /// conversation can continue.
  func streamChat(
    messages: [LLMMessage],
    tools: [LLMTool],
    model: String,
    systemPrompt: String?
  ) -> AsyncThrowingStream<LLMChunk, Error>
}
