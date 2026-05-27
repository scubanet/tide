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
}
