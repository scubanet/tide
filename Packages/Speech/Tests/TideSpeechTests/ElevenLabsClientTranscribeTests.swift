import XCTest
@testable import TideSpeech

final class ElevenLabsClientTranscribeTests: XCTestCase {
  private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
  }

  func test_transcribe_parses_text_from_scribe_response() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.absoluteString, "https://api.elevenlabs.io/v1/speech-to-text")
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "test-key")
      XCTAssertTrue(
        request.value(forHTTPHeaderField: "Content-Type")?
          .contains("multipart/form-data") ?? false
      )

      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      let json = """
        { "text": "Hallo Welt", "language_code": "de", "language_probability": 0.99, "words": [] }
        """.data(using: .utf8)!
      return (response, json)
    }

    let client = ElevenLabsClient(apiKey: "test-key", session: makeSession())
    let result = try await client.transcribe(audioData: Data(repeating: 0, count: 100))
    XCTAssertEqual(result, "Hallo Welt")
  }

  func test_transcribe_throws_on_non_200() async {
    MockURLProtocol.handler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
      )!
      return (response, Data())
    }

    let client = ElevenLabsClient(apiKey: "test-key", session: makeSession())
    await XCTAssertThrowsErrorAsync(
      try await client.transcribe(audioData: Data())
    )
  }

  func test_transcribe_throws_unauthorized_on_401() async {
    MockURLProtocol.handler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
      )!
      return (response, Data())
    }

    let client = ElevenLabsClient(apiKey: "bad-key", session: makeSession())
    do {
      _ = try await client.transcribe(audioData: Data())
      XCTFail("Expected unauthorized error")
    } catch ElevenLabsClient.Error.unauthorized {
      // expected
    } catch {
      XCTFail("Expected .unauthorized, got \(error)")
    }
  }

  func test_multipartBody_includes_fields_and_file() {
    let boundary = "TestBoundary123"
    let fileData = "FAKEWAV".data(using: .utf8)!
    let body = ElevenLabsClient.multipartBody(
      boundary: boundary,
      fields: ["model_id": "scribe_v1"],
      file: (name: "file", filename: "audio.wav", mime: "audio/wav", data: fileData)
    )

    let bodyString = String(data: body, encoding: .utf8) ?? ""
    XCTAssertTrue(bodyString.contains("--\(boundary)"))
    XCTAssertTrue(bodyString.contains("name=\"model_id\""))
    XCTAssertTrue(bodyString.contains("scribe_v1"))
    XCTAssertTrue(bodyString.contains("name=\"file\""))
    XCTAssertTrue(bodyString.contains("filename=\"audio.wav\""))
    XCTAssertTrue(bodyString.contains("Content-Type: audio/wav"))
    XCTAssertTrue(bodyString.contains("FAKEWAV"))
    XCTAssertTrue(bodyString.hasSuffix("--\(boundary)--\r\n"))
  }
}

// Helper for async throws assertion (Swift Testing has #expect, XCTest needs this)
func XCTAssertThrowsErrorAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  file: StaticString = #file, line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("Expected error to be thrown", file: file, line: line)
  } catch {
    // expected
  }
}
