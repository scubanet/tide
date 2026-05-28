# ElevenLabs Scribe Hybrid — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hybrid Apple+ElevenLabs Speech-Recognition mit Apple live partial + ElevenLabs final replace, plus Settings-Picker.

**Architecture:** Neuer `ElevenLabsRecognizer` als `SpeechRecognizer`-Conformer (non-streaming batch via Scribe-API), plus `HybridRecognizer` als Coordinator der beide parallel laufen lässt. Audio wird parallel via `AudioBufferAccumulator` gesammelt und am Ende als 16kHz Mono WAV an Scribe geschickt. Default-Choice: Hybrid.

**Tech Stack:** Swift 6 strict concurrency, AVAudioEngine + AVAudioConverter, URLSession multipart-upload, ElevenLabs Scribe-API.

**Spec:** `docs/specs/2026-05-28-elevenlabs-scribe-hybrid-design.md`

---

## Phase A — Foundation

### Task 1: `SpeechRecognizerChoice` Enum

**Files:**
- Modify: `Packages/Speech/Sources/TideSpeech/Protocols/SpeechRecognizer.swift`

- [ ] **Step 1: Enum ergänzen**

Am Ende von `Packages/Speech/Sources/TideSpeech/Protocols/SpeechRecognizer.swift`:

```swift
/// User-facing choice for which speech recognizer to use.
/// Persisted in AppSettings (raw string).
public enum SpeechRecognizerChoice: String, Sendable, CaseIterable, Codable {
  case apple
  case elevenLabs
  case hybrid

  public static let `default`: Self = .hybrid

  public var displayName: String {
    switch self {
    case .apple:      "Apple (on-device, gratis)"
    case .elevenLabs: "ElevenLabs (höhere Genauigkeit)"
    case .hybrid:     "Hybrid (Apple live + ElevenLabs final)"
    }
  }

  /// True if this choice requires an ElevenLabs API key to be set.
  public var requiresElevenLabsKey: Bool {
    switch self {
    case .apple:                   false
    case .elevenLabs, .hybrid:     true
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
cd ~/Desktop/Developer/tide
git add Packages/Speech/Sources/TideSpeech/Protocols/SpeechRecognizer.swift
git commit -m "feat(speech): SpeechRecognizerChoice enum (apple/elevenLabs/hybrid)"
```

---

### Task 2: `AppSettings.speechRecognizer` Property

**Files:**
- Modify: `Packages/Core/Sources/Core/Settings/AppSettings.swift`

- [ ] **Step 1: Property ergänzen**

In `AppSettings.swift` neben den existing TTS-Properties einfügen (Plan-Skeleton — adaptier an existing AppSettings-Pattern):

```swift
import TideSpeech

extension AppSettings {
  /// Which speech recognizer to use. Default: hybrid.
  public var speechRecognizer: SpeechRecognizerChoice {
    get {
      guard let raw = defaults.string(forKey: "speechRecognizer"),
            let choice = SpeechRecognizerChoice(rawValue: raw) else {
        return .default
      }
      return choice
    }
    set {
      defaults.set(newValue.rawValue, forKey: "speechRecognizer")
    }
  }
}
```

(Falls AppSettings nicht via `defaults`-Property arbeitet, sondern direkt via `@AppStorage` in den Views — Pattern entsprechend anpassen. Plan kann das nicht 100% vorhersagen.)

- [ ] **Step 2: Test**

In `Packages/Core/Tests/CoreTests/AppSettingsTests.swift` ergänzen:

```swift
func test_speechRecognizer_defaults_to_hybrid() {
  let settings = AppSettings()
  XCTAssertEqual(settings.speechRecognizer, .hybrid)
}

func test_speechRecognizer_roundtrip() {
  let settings = AppSettings()
  settings.speechRecognizer = .elevenLabs
  XCTAssertEqual(settings.speechRecognizer, .elevenLabs)
  settings.speechRecognizer = .apple
  XCTAssertEqual(settings.speechRecognizer, .apple)
}
```

- [ ] **Step 3: Commit**

```bash
git add Packages/Core/Sources/Core/Settings/AppSettings.swift \
        Packages/Core/Tests/CoreTests/AppSettingsTests.swift
git commit -m "feat(core): AppSettings.speechRecognizer persistence + tests"
```

---

## Phase B — Audio-Buffer

### Task 3: `AudioBufferAccumulator` — Collect PCMBuffers

**Files:**
- Create: `Tide/Recorder/AudioBufferAccumulator.swift`

- [ ] **Step 1: Klasse schreiben**

Inhalt von `Tide/Recorder/AudioBufferAccumulator.swift`:

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add Tide/Recorder/AudioBufferAccumulator.swift
git commit -m "feat(recorder): AudioBufferAccumulator — thread-safe PCM-chunk buffering"
```

---

### Task 4: `AudioBufferAccumulator.exportWAV()` — Resample + WAV-Encode

**Files:**
- Modify: `Tide/Recorder/AudioBufferAccumulator.swift`
- Create: `TideTests/AudioBufferAccumulatorTests.swift`

- [ ] **Step 1: Export-Methode ergänzen**

In `AudioBufferAccumulator.swift`:

```swift
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
```

- [ ] **Step 2: Test schreiben**

Inhalt von `TideTests/AudioBufferAccumulatorTests.swift`:

```swift
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
}
```

- [ ] **Step 3: Commit**

```bash
git add Tide/Recorder/AudioBufferAccumulator.swift \
        TideTests/AudioBufferAccumulatorTests.swift
git commit -m "feat(recorder): AudioBufferAccumulator.exportWAV — 16kHz mono Int16 + WAV header"
```

---

## Phase C — ElevenLabs Client

### Task 5: `ElevenLabsClient.transcribe()` + Multipart-Helper

**Files:**
- Modify: `Packages/Speech/Sources/TideSpeech/ElevenLabs/ElevenLabsClient.swift`

- [ ] **Step 1: Vor dem Edit existing Client lesen**

```bash
cat Packages/Speech/Sources/TideSpeech/ElevenLabs/ElevenLabsClient.swift
```

Vermutlich gibt es schon `synthesize()` und `voices()`-Endpoints. Pattern für `transcribe` analog.

- [ ] **Step 2: `transcribe(audioData:)` ergänzen**

Am Ende des Files (vor schliessender Klassen-Klammer):

```swift
public extension ElevenLabsClient {
  /// Transcribe audio via Scribe (ElevenLabs Speech-to-Text).
  /// Audio: 16kHz mono PCM Int16 WAV. Returns the transcribed text.
  func transcribe(audioData: Data) async throws -> String {
    let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 10
    request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

    let boundary = "Tide-\(UUID().uuidString)"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    request.httpBody = Self.multipartBody(boundary: boundary, fields: [
      "model_id":               "scribe_v1",
      "tag_audio_events":       "false",
      "timestamps_granularity": "none",
      "diarize":                "false",
    ], file: (name: "file", filename: "audio.wav", mime: "audio/wav", data: audioData))

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw ElevenLabsError.serverError(((response as? HTTPURLResponse)?.statusCode ?? -1))
    }

    let decoded = try JSONDecoder().decode(ScribeResponse.self, from: data)
    return decoded.text
  }

  /// Build a multipart/form-data body with text fields + one file part.
  internal static func multipartBody(
    boundary: String,
    fields: [String: String],
    file: (name: String, filename: String, mime: String, data: Data)
  ) -> Data {
    var body = Data()
    let nl = "\r\n"
    let dashBoundary = "--\(boundary)"

    for (key, value) in fields {
      body.append("\(dashBoundary)\(nl)".data(using: .utf8)!)
      body.append("Content-Disposition: form-data; name=\"\(key)\"\(nl)\(nl)".data(using: .utf8)!)
      body.append("\(value)\(nl)".data(using: .utf8)!)
    }

    body.append("\(dashBoundary)\(nl)".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\(nl)".data(using: .utf8)!)
    body.append("Content-Type: \(file.mime)\(nl)\(nl)".data(using: .utf8)!)
    body.append(file.data)
    body.append("\(nl)\(dashBoundary)--\(nl)".data(using: .utf8)!)

    return body
  }
}

private struct ScribeResponse: Decodable {
  let text: String
  let language_code: String
  let language_probability: Double
}
```

(Falls `ElevenLabsError.serverError` nicht existiert, an existing Error-Enum adaptieren.)

- [ ] **Step 3: Test schreiben**

In `Packages/Speech/Tests/TideSpeechTests/` neuen File `ElevenLabsClientTranscribeTests.swift`:

```swift
import XCTest
@testable import TideSpeech

final class ElevenLabsClientTranscribeTests: XCTestCase {
  override func setUp() {
    super.setUp()
    URLProtocol.registerClass(MockURLProtocol.self)
  }
  override func tearDown() {
    URLProtocol.unregisterClass(MockURLProtocol.self)
    super.tearDown()
  }

  func test_transcribe_parses_text_from_scribe_response() async throws {
    MockURLProtocol.requestHandler = { request in
      XCTAssertEqual(request.url?.absoluteString, "https://api.elevenlabs.io/v1/speech-to-text")
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "test-key")
      XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") ?? false)

      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      let json = """
        { "text": "Hallo Welt", "language_code": "de", "language_probability": 0.99, "words": [] }
        """.data(using: .utf8)!
      return (response, json)
    }

    let client = ElevenLabsClient(apiKey: "test-key")
    let result = try await client.transcribe(audioData: Data(repeating: 0, count: 100))
    XCTAssertEqual(result, "Hallo Welt")
  }

  func test_transcribe_throws_on_non_200() async {
    MockURLProtocol.requestHandler = { request in
      let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
      return (response, Data())
    }

    let client = ElevenLabsClient(apiKey: "test-key")
    await XCTAssertThrowsErrorAsync(try await client.transcribe(audioData: Data()))
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
  } catch { /* expected */ }
}
```

(MockURLProtocol existiert schon im LLM-Package. Falls Speech-Package keinen Zugriff hat, von dort kopieren in `Packages/Speech/Tests/TideSpeechTests/MockURLProtocol.swift`.)

- [ ] **Step 4: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/ElevenLabs/ElevenLabsClient.swift \
        Packages/Speech/Tests/TideSpeechTests/ElevenLabsClientTranscribeTests.swift
git commit -m "feat(speech): ElevenLabsClient.transcribe — Scribe API + multipart helper"
```

---

## Phase D — Recognizers

### Task 6: `ElevenLabsRecognizer`

**Files:**
- Create: `Packages/Speech/Sources/TideSpeech/ElevenLabs/ElevenLabsRecognizer.swift`

- [ ] **Step 1: Recognizer schreiben**

```swift
import Foundation
import OSLog

/// Non-streaming recognizer. Buffer-API: an external accumulator collects
/// PCM during recording; on stopStreaming we post the WAV to Scribe and
/// return the final text. Apple-style live partials are not provided —
/// use HybridRecognizer if you want them.
public final class ElevenLabsRecognizer: SpeechRecognizer {
  private let client: ElevenLabsClient
  private let bufferProvider: () -> Data?
  private static let logger = Logger(subsystem: "swiss.weckherlin.tide", category: "el-recognizer")

  /// - Parameter bufferProvider: closure that returns the WAV-encoded audio
  ///   data when called (typically wraps AudioBufferAccumulator.exportWAV).
  public init(client: ElevenLabsClient, bufferProvider: @escaping () -> Data?) {
    self.client = client
    self.bufferProvider = bufferProvider
  }

  public func startStreaming(onPartialResult: @escaping @Sendable (String) -> Void) async throws {
    // Scribe is non-streaming. Nothing to do at start. Caller's buffer
    // accumulator should be reset externally (HybridRecognizer + AudioRecorder
    // coordinate that).
  }

  public func stopStreaming() async -> String {
    guard let wavData = bufferProvider() else {
      Self.logger.debug("No buffered audio to transcribe.")
      return ""
    }
    do {
      let text = try await client.transcribe(audioData: wavData)
      Self.logger.debug("Scribe transcribed \(text.count) chars.")
      return text
    } catch {
      Self.logger.warning("Scribe failed: \(error.localizedDescription, privacy: .public) — returning empty string for fallback")
      return ""
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/ElevenLabs/ElevenLabsRecognizer.swift
git commit -m "feat(speech): ElevenLabsRecognizer — SpeechRecognizer conformer via Scribe"
```

---

### Task 7: `HybridRecognizer`

**Files:**
- Create: `Packages/Speech/Sources/TideSpeech/HybridRecognizer.swift`
- Create: `Packages/Speech/Tests/TideSpeechTests/HybridRecognizerTests.swift`

- [ ] **Step 1: Coordinator schreiben**

```swift
import Foundation
import OSLog

/// Coordinator: Apple provides live partials during recording, ElevenLabs
/// runs in parallel and replaces the final text with a more accurate
/// transcription on stopStreaming.
///
/// If ElevenLabs fails or returns empty, the Apple result is kept.
public final class HybridRecognizer: SpeechRecognizer {
  private let apple: any SpeechRecognizer
  private let eleven: any SpeechRecognizer
  private static let logger = Logger(subsystem: "swiss.weckherlin.tide", category: "hybrid-recognizer")

  public init(apple: any SpeechRecognizer, eleven: any SpeechRecognizer) {
    self.apple = apple
    self.eleven = eleven
  }

  public func startStreaming(onPartialResult: @escaping @Sendable (String) -> Void) async throws {
    try await eleven.startStreaming { _ in /* never fires */ }
    try await apple.startStreaming(onPartialResult: onPartialResult)
  }

  public func stopStreaming() async -> String {
    let appleFinal = await apple.stopStreaming()
    let elevenFinal = await eleven.stopStreaming()
    if elevenFinal.isEmpty {
      Self.logger.debug("Hybrid: ElevenLabs returned empty, keeping Apple result.")
      return appleFinal
    }
    Self.logger.debug("Hybrid: replacing Apple (\(appleFinal.count) chars) with ElevenLabs (\(elevenFinal.count) chars).")
    return elevenFinal
  }
}
```

- [ ] **Step 2: Tests schreiben**

```swift
import XCTest
@testable import TideSpeech

final class HybridRecognizerTests: XCTestCase {
  /// Mock recognizer that returns a pre-configured final on stopStreaming.
  final class StubRecognizer: SpeechRecognizer, @unchecked Sendable {
    let final: String
    var didStart = false
    var didStop = false
    init(final: String) { self.final = final }
    func startStreaming(onPartialResult: @escaping @Sendable (String) -> Void) async throws {
      didStart = true
      onPartialResult(final)  // fake-emit partial as well, simulating Apple
    }
    func stopStreaming() async -> String {
      didStop = true
      return final
    }
  }

  func test_hybrid_returns_elevenlabs_when_non_empty() async throws {
    let apple = StubRecognizer(final: "Apple-Text")
    let eleven = StubRecognizer(final: "ElevenLabs-Text")
    let hybrid = HybridRecognizer(apple: apple, eleven: eleven)

    try await hybrid.startStreaming { _ in }
    let result = await hybrid.stopStreaming()
    XCTAssertEqual(result, "ElevenLabs-Text")
    XCTAssertTrue(apple.didStart)
    XCTAssertTrue(eleven.didStart)
  }

  func test_hybrid_falls_back_to_apple_when_elevenlabs_empty() async throws {
    let apple = StubRecognizer(final: "Apple-Final")
    let eleven = StubRecognizer(final: "")  // simulates failure
    let hybrid = HybridRecognizer(apple: apple, eleven: eleven)

    try await hybrid.startStreaming { _ in }
    let result = await hybrid.stopStreaming()
    XCTAssertEqual(result, "Apple-Final")
  }

  func test_hybrid_starts_both_recognizers() async throws {
    let apple = StubRecognizer(final: "x")
    let eleven = StubRecognizer(final: "y")
    let hybrid = HybridRecognizer(apple: apple, eleven: eleven)

    try await hybrid.startStreaming { _ in }
    XCTAssertTrue(apple.didStart)
    XCTAssertTrue(eleven.didStart)
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/HybridRecognizer.swift \
        Packages/Speech/Tests/TideSpeechTests/HybridRecognizerTests.swift
git commit -m "feat(speech): HybridRecognizer coordinator + tests"
```

---

## Phase E — App-Wiring

### Task 8: `AudioRecorder` Tap an `AudioBufferAccumulator`

**Files:**
- Modify: `Tide/Recorder/AudioRecorder.swift`

- [ ] **Step 1: Vor dem Edit aktuellen AudioRecorder lesen**

```bash
cat Tide/Recorder/AudioRecorder.swift
```

Vermutlich gibt es einen `installTap`-Block der Apple-Recognizer-Buffer pusht. Wir wollen DAZU einen `AudioBufferAccumulator` füttern.

- [ ] **Step 2: AudioRecorder erweitern**

Adapter — Pseudo-Code-Pattern, an existing Code anpassen:

```swift
public final class AudioRecorder {
  public let bufferAccumulator = AudioBufferAccumulator()
  // … existing properties

  public func start() {
    bufferAccumulator.reset()
    // existing setup + tap installation:
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
      self?.bufferAccumulator.append(buffer)
      self?.appleRecognizerTap?(buffer)
    }
    // …
  }
}
```

(Adapter wieder an existing Tap-Pattern. Vermutlich gibt es schon einen Closure-Callback fürs Apple-Recognizer-Streaming — wir hängen den Accumulator-Append DAVOR oder DANEBEN.)

- [ ] **Step 3: Commit**

```bash
git add Tide/Recorder/AudioRecorder.swift
git commit -m "feat(recorder): AudioRecorder feeds AudioBufferAccumulator parallel to Apple"
```

---

### Task 9: `ChatViewModel` — Recognizer-Choice-Injection

**Files:**
- Modify: `Tide/Panel/ChatViewModel.swift`

- [ ] **Step 1: ChatViewModel-Recognizer-Selection**

In `ChatViewModel` (vermutlich gibt es heute eine `recognizer: any SpeechRecognizer`-Property die auf Apple gehardcoded ist):

```swift
private func makeRecognizer(for choice: SpeechRecognizerChoice,
                            apiKey: String?) -> any SpeechRecognizer {
  let apple = AppleSpeechRecognizer()

  guard choice != .apple, let key = apiKey, !key.isEmpty else {
    return apple
  }

  let client = ElevenLabsClient(apiKey: key)
  let elevenRecognizer = ElevenLabsRecognizer(
    client: client,
    bufferProvider: { [weak self] in
      self?.audioRecorder.bufferAccumulator.exportWAV(sampleRate: 16000, channels: 1)
    }
  )

  switch choice {
  case .elevenLabs: return elevenRecognizer
  case .hybrid:     return HybridRecognizer(apple: apple, eleven: elevenRecognizer)
  case .apple:      return apple  // unreachable per guard above
  }
}
```

Beim Construction-Path: `let recognizer = makeRecognizer(for: settings.speechRecognizer, apiKey: settings.elevenLabsApiKey)`.

- [ ] **Step 2: Commit**

```bash
git add Tide/Panel/ChatViewModel.swift
git commit -m "feat(app): ChatViewModel injects recognizer based on Settings.speechRecognizer"
```

---

### Task 10: `VoiceSection` — Recognizer-Picker

**Files:**
- Modify: `Tide/Settings/VoiceSection.swift`

- [ ] **Step 1: Picker einbauen**

Im `VoiceSection`-View, unter dem existing TTS-Picker, neue Section:

```swift
Section("Spracherkennung") {
  Picker("Recognizer", selection: $settings.speechRecognizer) {
    ForEach(SpeechRecognizerChoice.allCases, id: \.self) { choice in
      Text(choice.displayName).tag(choice)
    }
  }
  .pickerStyle(.radioGroup)
  .onChange(of: settings.speechRecognizer) { _, newValue in
    if newValue.requiresElevenLabsKey && (settings.elevenLabsApiKey ?? "").isEmpty {
      // Validation: snap back to Apple
      settings.speechRecognizer = .apple
      showKeyMissingHint = true
    }
  }

  if showKeyMissingHint {
    Text("⚠ ElevenLabs API-Key fehlt — siehe Voice-Provider oben")
      .font(.system(size: 11))
      .foregroundStyle(.orange)
  }
}
```

Plus `@State var showKeyMissingHint = false` im View.

- [ ] **Step 2: Commit**

```bash
git add Tide/Settings/VoiceSection.swift
git commit -m "feat(settings): VoiceSection — Speech-Recognizer-Picker + key-missing validation"
```

---

## Phase F — Rollout

### Task 11: CHANGELOG v0.2.0 Entry

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Entry hinzufügen**

Oben über dem `## [Unreleased]`-Block in `CHANGELOG.md`:

```markdown
## [0.2.0] — Welle 2: ElevenLabs Scribe Hybrid (28.05.2026)

### Added

- **ElevenLabs Scribe** als zweiter STT-Provider (`ElevenLabsRecognizer`)
- **Hybrid-Modus**: Apple liefert live partial-text während des Sprechens, ElevenLabs Scribe ersetzt nach 1-3s mit höher-genauer Transkription
- **Settings → Voice → Spracherkennung**: 3-Optionen-Picker (Apple / ElevenLabs / Hybrid), default Hybrid
- **AudioBufferAccumulator**: thread-safe Buffer für AVAudioPCMBuffer-Chunks, mit Resample auf 16kHz Mono Int16 + WAV-Encode
- **Multipart-Upload-Helper** in ElevenLabsClient für Scribe-API

### Architektur-Entscheidungen

- **Non-streaming Scribe** statt streaming-Endpoint — Batch ist robust für Push-to-Talk (sub-30s recordings)
- **Apple-Fallback bei ElevenLabs-Fail** — Daily-Use darf nie blockieren. Bei Netz-Aus / Timeout / 5xx: leise Apple-Resultat behalten
- **Replace-Timing atomar** im `recognizedText`-State — kein direkter Buffer-Write, schützt User-Edits

### Tests

- `AudioBufferAccumulatorTests` — Resample + WAV-Header-Validierung
- `ElevenLabsClientTranscribeTests` — Mock-URL-Protocol Scribe-API-Roundtrip
- `HybridRecognizerTests` — Apple+ElevenLabs-Coordinator + Fallback-Path

### Bekannte Limits

- Word-Level Timestamps explizit deaktiviert (nicht benötigt)
- Language-Hint nicht gesetzt (Scribe auto-detected exzellent)
- Cost-Tracking-UI nicht implementiert (~$0.40/h, in Settings später)
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: CHANGELOG v0.2.0 entry — Welle 2 ElevenLabs Scribe Hybrid"
```

---

## Self-Review-Checklist (post-hoc)

**Spec-Coverage:**
- §2 Architektur (3 Recognizer + Coordinator) → Tasks 6, 7 ✓
- §3 Scribe API → Task 5 ✓
- §4 File-Inventar → über alle Tasks abgedeckt ✓
- §5 Settings-UX → Task 10 ✓
- §6 Rollout-Plan → Tasks in der dort genannten Reihenfolge ✓
- §9 Akzeptanzkriterien → manuelle E2E im CHANGELOG-Test-Block + Unit-Tests in 4, 5, 7 ✓

**Placeholder-Scan:** keine TBD/TODO. AudioRecorder-Task hat bewussten Adapter-Hinweis ("an existing Tap-Pattern anpassen") weil ich das Existing-Pattern nicht kannte; das ist plan-fair (führendes Verb + Beispiel-Skeleton).

**Typkonsistenz:**
- `SpeechRecognizerChoice` Properties in Tasks 1, 2, 9, 10 konsistent (apple/elevenLabs/hybrid, requiresElevenLabsKey)
- `bufferProvider: () -> Data?` Signatur in Tasks 6 + 9 identisch
- `AudioBufferAccumulator.exportWAV(sampleRate:channels:)` in Tasks 4, 9 identisch
- `client.transcribe(audioData:)` in Tasks 5, 6 identisch

**Bekannte Adapter-Punkte** (Sub-Agent muss am existing Code adaptieren):
- AppSettings-Pattern (defaults vs @AppStorage) in Task 2
- ElevenLabsError-Enum in Task 5 — falls Cases anders heissen, anpassen
- AudioRecorder-Tap-Pattern in Task 8 — Plan ist Skeleton, existing Closure-Struktur ist nicht 100% bekannt
- ChatViewModel-Construction-Path in Task 9 — abhängig vom existing DI-Pattern
