import XCTest
@testable import TideSpeech

final class TranscriptionQualityTests: XCTestCase {

  // MARK: shouldRejectRecording

  func test_shouldReject_belowMinimumDuration() {
    XCTAssertTrue(TranscriptionQuality.shouldRejectRecording(duration: 0.2))
    XCTAssertTrue(TranscriptionQuality.shouldRejectRecording(duration: 0.29))
  }

  func test_shouldNotReject_atOrAboveMinimum() {
    XCTAssertFalse(TranscriptionQuality.shouldRejectRecording(duration: 0.3))
    XCTAssertFalse(TranscriptionQuality.shouldRejectRecording(duration: 1.0))
  }

  // MARK: isLikelyArtifact — empty / non-letter

  func test_artifact_emptyString() {
    XCTAssertTrue(TranscriptionQuality.isLikelyArtifact("", recordingDuration: 2.0))
  }

  func test_artifact_whitespaceOnly() {
    XCTAssertTrue(TranscriptionQuality.isLikelyArtifact("   \n  ", recordingDuration: 2.0))
  }

  func test_artifact_noLetters() {
    XCTAssertTrue(TranscriptionQuality.isLikelyArtifact("12 . , !", recordingDuration: 2.0))
  }

  // MARK: isLikelyArtifact — short recording, too much text

  func test_artifact_shortRecording_manyWords() {
    // 0.5s but 6 words → hallucination
    XCTAssertTrue(TranscriptionQuality.isLikelyArtifact(
      "one two three four five six", recordingDuration: 0.5))
  }

  func test_artifact_shortRecording_longText() {
    // 0.5s but >= 32 chars
    XCTAssertTrue(TranscriptionQuality.isLikelyArtifact(
      "abcdefghij abcdefghij abcdefghij x", recordingDuration: 0.5))
  }

  func test_ok_shortRecording_fewWords() {
    // 0.5s, 2 short words → plausible
    XCTAssertFalse(TranscriptionQuality.isLikelyArtifact(
      "ja klar", recordingDuration: 0.5))
  }

  // MARK: isLikelyArtifact — medium recording, long text

  func test_artifact_mediumRecording_veryLongText() {
    // 0.7s but >= 56 chars
    let text = String(repeating: "a ", count: 30) // 60 chars
    XCTAssertTrue(TranscriptionQuality.isLikelyArtifact(text, recordingDuration: 0.7))
  }

  func test_ok_longRecording_longText() {
    // 1.5s, long text → legit
    let text = String(repeating: "wort ", count: 40)
    XCTAssertFalse(TranscriptionQuality.isLikelyArtifact(text, recordingDuration: 1.5))
  }
}

// MARK: - isReject (combined gate)

extension TranscriptionQualityTests {
  func test_isReject_emptyText() {
    XCTAssertTrue(TranscriptionQuality.isReject("", duration: 2.0))
  }

  func test_isReject_tooShortRecording() {
    XCTAssertTrue(TranscriptionQuality.isReject("hallo welt", duration: 0.2))
  }

  func test_isReject_artifact() {
    let text = String(repeating: "a ", count: 30)
    XCTAssertTrue(TranscriptionQuality.isReject(text, duration: 0.7))
  }

  func test_isReject_acceptsRealSpeech() {
    XCTAssertFalse(TranscriptionQuality.isReject("Das ist ein normaler Satz.", duration: 2.0))
  }
}
