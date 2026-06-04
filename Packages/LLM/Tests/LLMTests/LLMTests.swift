import XCTest
@testable import LLM

final class LLMTests: XCTestCase {
  func testProtocolTypesAreReachable() {
    // Compile-only smoke: the types from this task must be present.
    let msg = LLMMessage(role: .user, content: "Hi")
    let chunk: LLMChunk = .text("ok")
    let tool = LLMTool(name: "noop", description: "test", inputSchemaJSON: "{}")
    XCTAssertEqual(msg.role, .user)
    XCTAssertEqual(chunk, .text("ok"))
    XCTAssertEqual(tool.name, "noop")
  }

  func test_llmError_errorDescription_nonEmptyForEveryCase() {
    let cases: [LLMError] = [
      .network("x"),
      .unauthorized,
      .rateLimit(retryAfterSeconds: 5),
      .serverError(code: 500, message: "boom"),
      .serverError(code: 0, message: "overloaded_error: Overloaded"),
      .decoding("y"),
    ]
    for e in cases {
      XCTAssertFalse((e.errorDescription ?? "").isEmpty, "\(e) has empty errorDescription")
    }
    // The real message must surface.
    XCTAssertTrue(LLMError.serverError(code: 500, message: "boom").errorDescription!.contains("boom"))
  }
}
