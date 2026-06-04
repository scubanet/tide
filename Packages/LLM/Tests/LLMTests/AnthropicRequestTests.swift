import XCTest
@testable import LLM

final class AnthropicRequestTests: XCTestCase {
  func test_messagesArray_onlyUserAndAssistant() throws {
    let req = try AnthropicRequestBuilder.makeRequest(
      apiKey: "k",
      messages: [
        LLMMessage(role: .system, content: "SYS"),
        LLMMessage(role: .user, content: "U"),
        LLMMessage(role: .assistant, content: "A"),
        LLMMessage(role: .tool, content: "T"),
      ],
      tools: [], model: "m", systemPrompt: nil
    )
    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    let messages = body["messages"] as! [[String: Any]]
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(messages.map { $0["role"] as! String }, ["user", "assistant"])
    XCTAssertEqual(messages.map { $0["content"] as! String }, ["U", "A"])
  }
}
