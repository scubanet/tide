import XCTest
@testable import TideSpeech

final class SpeechTests: XCTestCase {
  func testProtocolShapeIsStable() {
    // Compile-only check: AppleSpeechRecognizer conforms.
    let _: any SpeechRecognizer.Type = AppleSpeechRecognizer.self
  }
}
