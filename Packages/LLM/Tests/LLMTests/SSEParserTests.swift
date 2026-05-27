import XCTest
@testable import LLM

final class SSEParserTests: XCTestCase {
  func testParsesMultipleEvents() {
    let raw = """
    event: message_start
    data: {"type":"message_start"}

    event: content_block_delta
    data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hallo"}}

    event: message_stop
    data: {"type":"message_stop"}

    """
    let events = SSEParser.parse(raw)
    XCTAssertEqual(events.count, 3)
    XCTAssertEqual(events[0].event, "message_start")
    XCTAssertEqual(events[1].event, "content_block_delta")
    XCTAssertTrue(events[1].data.contains("Hallo"))
    XCTAssertEqual(events[2].event, "message_stop")
  }

  func testEmptyInputProducesNoEvents() {
    XCTAssertEqual(SSEParser.parse("").count, 0)
  }

  func testIncompleteJsonStillEmitsEvent() {
    // Permissive contract: the parser extracts what it can. Truncated
    // JSON in the data field is the decoder's problem, not the parser's.
    let raw = "event: content_block_delta\ndata: {\"partial\":\"true\""
    let events = SSEParser.parse(raw)
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0].event, "content_block_delta")
    XCTAssertTrue(events[0].data.hasPrefix("{\"partial\""))
  }

  func testHandlesMultilineDataField() {
    let raw = """
    event: content_block_delta
    data: line one
    data: line two

    """
    let events = SSEParser.parse(raw)
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0].data, "line one\nline two")
  }

  func testIgnoresBlocksWithoutEventLine() {
    let raw = """
    data: {"just":"data"}

    event: real
    data: real-payload

    """
    let events = SSEParser.parse(raw)
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0].event, "real")
  }
}
