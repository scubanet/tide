import Foundation
import AVFoundation
import OSLog

/// Accumulates AVAudioPCMBuffer chunks during a recording session.
/// Used by the ElevenLabs/Hybrid recognizers to assemble the full audio
/// for batch-upload to Scribe.
///
/// Thread-safe via internal NSLock — AudioRecorder taps may fire on the
/// audio render thread.
public final class AudioBufferAccumulator: @unchecked Sendable {
  private let lock = NSLock()
  private var chunks: [AVAudioPCMBuffer] = []
  private var inputFormat: AVAudioFormat?
  private static let logger = Logger(subsystem: "swiss.weckherlin.tide", category: "audio-buffer")

  public init() {}

  /// Drop all buffered audio and start fresh.
  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    chunks.removeAll(keepingCapacity: true)
    inputFormat = nil
  }

  /// Append a single tap-buffer.
  public func append(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    defer { lock.unlock() }
    if inputFormat == nil { inputFormat = buffer.format }
    chunks.append(buffer)
  }

  /// Total frame count across all buffered chunks.
  public var frameCount: AVAudioFrameCount {
    lock.lock()
    defer { lock.unlock() }
    return chunks.reduce(0) { $0 + $1.frameLength }
  }

  /// Returns a copy of the buffered chunks (for export).
  internal func snapshot() -> (format: AVAudioFormat?, chunks: [AVAudioPCMBuffer]) {
    lock.lock()
    defer { lock.unlock() }
    return (inputFormat, chunks)
  }
}
