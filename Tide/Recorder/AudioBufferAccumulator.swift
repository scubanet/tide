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

extension AudioBufferAccumulator {
  /// Resample buffered chunks to `sampleRate` Hz mono Int16, prepend a
  /// WAV header, return as Data. Returns nil if no audio buffered or
  /// the resample fails.
  public func exportWAV(sampleRate: Double, channels: AVAudioChannelCount) -> Data? {
    let (format, chunks) = snapshot()
    guard let inputFormat = format, !chunks.isEmpty else { return nil }

    // Build the target format: PCM Int16, given sample rate + channels
    guard let outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate:   sampleRate,
      channels:     channels,
      interleaved:  true
    ) else { return nil }

    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      Self.logger.error("Failed to create AVAudioConverter from \(inputFormat) to \(outputFormat)")
      return nil
    }

    // Concatenate input buffers into one big buffer
    let totalInputFrames = chunks.reduce(0) { $0 + $1.frameLength }
    guard let inputBuffer = AVAudioPCMBuffer(
      pcmFormat: inputFormat,
      frameCapacity: totalInputFrames
    ) else { return nil }
    inputBuffer.frameLength = totalInputFrames

    var writeOffset: AVAudioFrameCount = 0
    let channelCount = Int(inputFormat.channelCount)
    for chunk in chunks {
      let frames = Int(chunk.frameLength)
      if let src = chunk.floatChannelData, let dst = inputBuffer.floatChannelData {
        for ch in 0..<channelCount {
          memcpy(dst[ch] + Int(writeOffset),
                 src[ch],
                 frames * MemoryLayout<Float>.size)
        }
      }
      writeOffset += chunk.frameLength
    }

    // Allocate output buffer with appropriate size (ratio sampleRate)
    let ratio = sampleRate / inputFormat.sampleRate
    let outputCapacity = AVAudioFrameCount(Double(totalInputFrames) * ratio + 1024)
    guard let outputBuffer = AVAudioPCMBuffer(
      pcmFormat: outputFormat,
      frameCapacity: outputCapacity
    ) else { return nil }

    var error: NSError?
    var didConsume = false
    let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
      if didConsume {
        outStatus.pointee = .endOfStream
        return nil
      }
      didConsume = true
      outStatus.pointee = .haveData
      return inputBuffer
    }

    guard status != .error, error == nil else {
      Self.logger.error("AVAudioConverter failed: \(error?.localizedDescription ?? "unknown")")
      return nil
    }

    // Extract Int16 bytes from output buffer
    guard let int16Channel = outputBuffer.int16ChannelData?[0] else { return nil }
    let outputFrames = Int(outputBuffer.frameLength)
    let pcmBytes = Data(bytes: int16Channel, count: outputFrames * Int(channels) * MemoryLayout<Int16>.size)

    return wavHeader(
      dataSize: UInt32(pcmBytes.count),
      sampleRate: UInt32(sampleRate),
      channels: UInt16(channels),
      bitsPerSample: 16
    ) + pcmBytes
  }

  /// Generate a 44-byte RIFF/WAV header for raw PCM data.
  private func wavHeader(dataSize: UInt32, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
    var header = Data()
    let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
    let blockAlign = channels * bitsPerSample / 8
    let chunkSize = 36 + dataSize

    header.append("RIFF".data(using: .ascii)!)
    header.append(withUnsafeBytes(of: chunkSize.littleEndian) { Data($0) })
    header.append("WAVE".data(using: .ascii)!)
    header.append("fmt ".data(using: .ascii)!)
    header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })       // Subchunk1Size
    header.append(withUnsafeBytes(of: UInt16(1).littleEndian)  { Data($0) })       // AudioFormat = PCM
    header.append(withUnsafeBytes(of: channels.littleEndian)   { Data($0) })
    header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
    header.append(withUnsafeBytes(of: byteRate.littleEndian)   { Data($0) })
    header.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
    header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
    header.append("data".data(using: .ascii)!)
    header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
    return header
  }
}
