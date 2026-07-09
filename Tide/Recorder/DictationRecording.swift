import Foundation

/// The recording surface `DictationCoordinator` depends on — exactly
/// what it uses of `AudioRecorder`, nothing more. The seam exists so
/// coordinator tests can drive the stop()/reject/transform/fallback
/// paths with a fake instead of a live `AVAudioEngine` + microphone.
@MainActor
protocol DictationRecording: AnyObject {
  func start() async throws
  /// Finalize and return the transcript.
  func stop() async throws -> String
  /// Live partial-transcript stream for the floating pill.
  var partialTranscript: AsyncStream<String> { get }
  /// Total recorded duration in seconds (feeds the reject heuristics).
  var duration: TimeInterval { get }
}

extension AudioRecorder: DictationRecording {
  var duration: TimeInterval { bufferAccumulator.duration }
}
