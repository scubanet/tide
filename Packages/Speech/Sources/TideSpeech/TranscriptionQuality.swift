import Foundation

/// Pure heuristics that decide whether an ASR result should be kept or
/// discarded. Ported from Blitztext's `TranscriptionQualityService`.
///
/// ASR engines (Apple Speech, ElevenLabs Scribe) occasionally emit
/// hallucinated text on very short or silent recordings — a stray
/// "Untertitel…", "Thank you", etc. These checks reject such results
/// before they reach the cursor (dictation) or a chat bubble (PTT).
///
/// Stateless by design: both checks are static and depend only on the
/// transcript text and the recording duration, so they're trivially
/// unit-testable and free of side effects.
public enum TranscriptionQuality {

  /// Recordings shorter than this almost certainly contain no real
  /// speech — a hotkey double-tap or an accidental brush.
  public static let minimumRecordingDuration: TimeInterval = 0.3

  /// True when the recording was too short to contain usable speech.
  public static func shouldRejectRecording(duration: TimeInterval) -> Bool {
    duration < minimumRecordingDuration
  }

  /// True when `text` is likely an ASR hallucination rather than real
  /// transcribed speech, judged against how long the user actually
  /// recorded. The thresholds are deliberately conservative: a short
  /// recording cannot plausibly produce many words or long text.
  public static func isLikelyArtifact(_ text: String, recordingDuration: TimeInterval) -> Bool {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return true }

    let words = cleaned.split { $0.isWhitespace || $0.isNewline }
    let letters = cleaned.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count

    if letters == 0 {
      return true
    }
    if recordingDuration < 0.55 && (words.count >= 5 || cleaned.count >= 32) {
      return true
    }
    if recordingDuration < 0.8 && cleaned.count >= 56 {
      return true
    }
    return false
  }

  /// Combined gate used after a recording session ends: reject when the
  /// (already-trimmed) transcript is empty, the recording was too short,
  /// or the text looks like an ASR hallucination. One call site each in
  /// the panel flow and the standalone dictation flow — keep the
  /// heuristic in sync by construction.
  public static func isReject(_ trimmedText: String, duration: TimeInterval) -> Bool {
    trimmedText.isEmpty
      || shouldRejectRecording(duration: duration)
      || isLikelyArtifact(trimmedText, recordingDuration: duration)
  }
}
