import Foundation

/// Internal helper that translates our LLM domain types into an
/// Anthropic-shaped JSON request. Kept separate from `AnthropicProvider`
/// so it stays testable in isolation if we ever need to.
enum AnthropicRequestBuilder {
  static func makeRequest(
    apiKey: String,
    messages: [LLMMessage],
    tools: [LLMTool],
    model: String,
    systemPrompt: String?
  ) throws -> URLRequest {
    var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

    var body: [String: Any] = [
      "model": model,
      "max_tokens": 4096,
      "stream": true,
      "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
    ]
    if let systemPrompt {
      body["system"] = systemPrompt
    }
    if !tools.isEmpty {
      body["tools"] = tools.map { tool -> [String: Any] in
        var dict: [String: Any] = [
          "name": tool.name,
          "description": tool.description,
        ]
        if let schemaData = tool.inputSchemaJSON.data(using: .utf8),
           let schemaObj = try? JSONSerialization.jsonObject(with: schemaData) {
          dict["input_schema"] = schemaObj
        }
        return dict
      }
    }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    return req
  }
}
