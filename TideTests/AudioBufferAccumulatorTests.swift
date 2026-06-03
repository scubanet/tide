import XCTest
import AVFoundation
@testable import Tide

final class AudioBufferAccumulatorTests: XCTestCase {
  func makeSineBuffer(sampleRate: Double, durationMs: Int, frequencyHz: Double = 440) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                               sampleRate: sampleRate,
                               channels: 1,
                               interleaved: false)!
    let frames = AVAudioFrameCount(sampleRate * Double(durationMs) / 1000.0)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let data = buffer.floatChannelData![0]
    for i in 0..<Int(frames) {
      data[i] = Float(sin(2.0 * .pi * frequencyHz * Double(i) / sampleRate))
    }
    return buffer
  }

  func test_exportWAV_returns_nil_when_empty() {
    let acc = AudioBufferAccumulator()
    XCTAssertNil(acc.exportWAV(sampleRate: 16000, channels: 1))
  }

  func test_exportWAV_produces_valid_header() throws {
    let acc = AudioBufferAccumulator()
    acc.append(makeSineBuffer(sampleRate: 44100, durationMs: 500))

    let data = try XCTUnwrap(acc.exportWAV(sampleRate: 16000, channels: 1))
    XCTAssertGreaterThan(data.count, 44)

    // RIFF header check
    let riff = String(data: data[0..<4], encoding: .ascii)
    XCTAssertEqual(riff, "RIFF")
    let wave = String(data: data[8..<12], encoding: .ascii)
    XCTAssertEqual(wave, "WAVE")
    let fmt = String(data: data[12..<16], encoding: .ascii)
    XCTAssertEqual(fmt, "fmt ")
  }

  func test_reset_clears_chunks() {
    let acc = AudioBufferAccumulator()
    acc.append(makeSineBuffer(sampleRate: 44100, durationMs: 100))
    XCTAssertGreaterThan(acc.frameCount, 0)
    acc.reset()
    XCTAssertEqual(acc.frameCount, 0)
  }

  func test_duration_isZero_whenEmpty() {
    let acc = AudioBufferAccumulator()
    XCTAssertEqual(acc.duration, 0, accuracy: 0.0001)
  }

  func test_duration_matchesBufferedFrames() {
    let acc = AudioBufferAccumulator()
    // 500ms at 44100 Hz
    acc.append(makeSineBuffer(sampleRate: 44100, durationMs: 500))
    XCTAssertEqual(acc.duration, 0.5, accuracy: 0.01)
  }

  func test_duration_isZero_afterReset() {
    let acc = AudioBufferAccumulator()
    acc.append(makeSineBuffer(sampleRate: 44100, durationMs: 300))
    acc.reset()
    XCTAssertEqual(acc.duration, 0, accuracy: 0.0001)
  }
}
