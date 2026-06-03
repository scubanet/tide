import XCTest
@testable import TideSpeech

private actor MockTranscriber: Transcribing {
  enum Mode { case returns(String); case throws_ }
  let mode: Mode
  private(set) var callCount = 0
  init(_ mode: Mode) { self.mode = mode }
  func transcribe(wav: Data, language: String?, modelName: String) async throws -> String {
    callCount += 1
    switch mode {
    case .returns(let s): return s
    case .throws_: throw WhisperModelError.modelMissing(modelName)
    }
  }
  func calls() -> Int { callCount }
}

final class WhisperKitRecognizerTests: XCTestCase {
  func test_stop_returnsTranscriberText_whenBufferPresent() async throws {
    let mock = MockTranscriber(.returns("hallo welt"))
    let rec = WhisperKitRecognizer(
      transcriber: mock,
      modelName: "m",
      bufferProvider: { Data([1, 2, 3]) },
      language: nil
    )
    let out = try await rec.stop()
    XCTAssertEqual(out, "hallo welt")
  }

  func test_stop_returnsEmpty_andSkipsTranscriber_whenNoBuffer() async throws {
    let mock = MockTranscriber(.returns("unused"))
    let rec = WhisperKitRecognizer(
      transcriber: mock,
      modelName: "m",
      bufferProvider: { nil },
      language: nil
    )
    let out = try await rec.stop()
    XCTAssertEqual(out, "")
    let calls = await mock.calls()
    XCTAssertEqual(calls, 0)
  }

  func test_stop_returnsEmpty_whenTranscriberThrows() async throws {
    let mock = MockTranscriber(.throws_)
    let rec = WhisperKitRecognizer(
      transcriber: mock,
      modelName: "m",
      bufferProvider: { Data([1]) },
      language: nil
    )
    let out = try await rec.stop()
    XCTAssertEqual(out, "")
  }
}
