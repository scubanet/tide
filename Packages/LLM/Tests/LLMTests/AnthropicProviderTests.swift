import XCTest
@testable import LLM

final class AnthropicProviderTests: XCTestCase {
  private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
  }

  func testStreamsTextChunks() async throws {
    let sseBody = """
    event: content_block_delta
    data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hallo "}}

    event: content_block_delta
    data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Welt"}}

    event: message_stop
    data: {"type":"message_stop"}

    """
    MockURLProtocol.handler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, sseBody.data(using: .utf8)!)
    }

    let provider = AnthropicProvider(apiKey: "sk-test", session: makeSession())
    var collected: [LLMChunk] = []
    let stream = provider.streamChat(
      messages: [LLMMessage(role: .user, content: "Hi")],
      tools: [],
      model: "claude-sonnet-4-6",
      systemPrompt: nil
    )
    for try await chunk in stream {
      collected.append(chunk)
    }
    XCTAssertEqual(collected, [.text("Hallo "), .text("Welt"), .done])
  }

  func testReturnsUnauthorizedOn401() async throws {
    MockURLProtocol.handler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
      )!
      return (response, "{\"error\":\"invalid api key\"}".data(using: .utf8)!)
    }
    let provider = AnthropicProvider(apiKey: "sk-bad", session: makeSession())
    do {
      let stream = provider.streamChat(
        messages: [LLMMessage(role: .user, content: "Hi")],
        tools: [], model: "claude-sonnet-4-6", systemPrompt: nil
      )
      for try await _ in stream {}
      XCTFail("Expected to throw")
    } catch LLMError.unauthorized {
      // expected
    } catch {
      XCTFail("Expected LLMError.unauthorized but got \(error)")
    }
  }

  func testReturnsRateLimitOn429() async throws {
    MockURLProtocol.handler = { request in
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 429,
        httpVersion: nil,
        headerFields: ["retry-after": "30"]
      )!
      return (response, Data())
    }
    let provider = AnthropicProvider(apiKey: "sk-test", session: makeSession())
    do {
      let stream = provider.streamChat(
        messages: [LLMMessage(role: .user, content: "Hi")],
        tools: [], model: "claude-sonnet-4-6", systemPrompt: nil
      )
      for try await _ in stream {}
      XCTFail("Expected to throw")
    } catch let LLMError.rateLimit(retryAfter) {
      XCTAssertEqual(retryAfter, 30)
    } catch {
      XCTFail("Expected LLMError.rateLimit but got \(error)")
    }
  }
}
