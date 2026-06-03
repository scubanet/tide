# WhisperKit Local Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fully-local offline WhisperKit/CoreML transcription as a new recognizer choice, with in-app model download, a 3-model picker, and prewarm.

**Architecture:** New WhisperKit dependency in `TideSpeech`. `WhisperModelStore` (catalog/paths/download), `WhisperKitTranscriber` (one shared actor instance, owns the loaded pipeline), `WhisperKitRecognizer` (non-streaming, mirrors `ElevenLabsRecognizer`). New `.whisperKit` recognizer choice; `RecognizerFactory` builds it when the model is installed, else falls back to Apple. Shared instance reached via `LocalTranscriberHolder.shared` (set in `AppEntry`). New Settings tab for model download.

**Tech Stack:** Swift 6, XCTest, WhisperKit (CoreML), SwiftUI. Package tests via `swift test`; app-target tests/build via `xcodebuild … CODE_SIGNING_ALLOWED=NO`.

> **WhisperKit API note:** Signatures below follow the proven Blitztext usage on `argmax-oss-swift` 0.18.0 (`WhisperKit.download(variant:downloadBase:from:){progress}`, `WhisperKit(modelFolder:verbose:prewarm:load:download:)`, `pipeline.transcribe(audioPath:decodeOptions:) -> [TranscriptionResult]`, `DecodingOptions(task:language:)`). If 0.18.0's actual signatures differ at build time, adjust the call to match — the structure (download → install → load → transcribe-from-path) stays the same. Report BLOCKED if the API diverges significantly.

---

## File Structure

| Datei | Verantwortung |
|---|---|
| `Packages/Speech/Package.swift` | + WhisperKit dependency |
| `Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperModelStore.swift` | **neu** — catalog, paths, isInstalled, download |
| `Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperKitTranscriber.swift` | **neu** — `Transcribing` protocol + actor |
| `Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperKitRecognizer.swift` | **neu** — non-streaming recognizer |
| `Packages/Speech/Sources/TideSpeech/WhisperKit/LocalTranscriberHolder.swift` | **neu** — `@MainActor` shared-instance holder |
| `Packages/Speech/Sources/TideSpeech/Protocols/SpeechRecognizer.swift` | `.whisperKit` case + `requiresLocalModel` |
| `Packages/Speech/Tests/TideSpeechTests/WhisperModelStoreTests.swift` | **neu** |
| `Packages/Speech/Tests/TideSpeechTests/WhisperKitRecognizerTests.swift` | **neu** |
| `Packages/Speech/Tests/TideSpeechTests/SpeechRecognizerChoiceTests.swift` | **neu** |
| `Packages/Core/Sources/Core/Settings/AppSettings.swift` | + `localModelName` |
| `Packages/Core/Tests/CoreTests/AppSettingsTests.swift` | localModelName test |
| `Tide/Dictation/RecognizerFactory.swift` | `.whisperKit` branch + params |
| `Tide/Dictation/DictationCoordinator.swift` | pass model/installed/holder to factory |
| `Tide/Panel/ChatViewModel.swift` | pass model/installed/holder to factory |
| `Tide/Settings/LocalModelSection.swift` | **neu** — download/picker tab |
| `Tide/Settings/VoiceSection.swift` | `.whisperKit` no-model hint |
| `Tide/Settings/SettingsWindow.swift` | tab |
| `Tide/AppEntry.swift` | set holder + prewarm |
| `README.md`, `CHANGELOG.md` | docs |

**Branch:** Vor Task 1: `git checkout -b feat/whisperkit-local`

---

## Task 1: WhisperKit dependency + resolve spike

**Files:** `Packages/Speech/Package.swift`

- [ ] **Step 1: Add the dependency**

Replace the `Package(...)` in `Packages/Speech/Package.swift` with:

```swift
let package = Package(
  name: "TideSpeech",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TideSpeech", targets: ["TideSpeech"]),
  ],
  dependencies: [
    .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "0.18.0"),
  ],
  targets: [
    .target(
      name: "TideSpeech",
      dependencies: [.product(name: "WhisperKit", package: "argmax-oss-swift")]
    ),
    .testTarget(name: "TideSpeechTests", dependencies: ["TideSpeech"]),
  ]
)
```

- [ ] **Step 2: Resolve + build (spike)**

Run: `cd Packages/Speech && swift build 2>&1 | tail -15`
Expected: dependency resolves and `Build complete!`. (First resolve downloads the package — may take a minute.)

If the `package:` identity is rejected, run `swift package describe --type json 2>/dev/null | head` or read the resolved `Package.resolved` to find the correct package identity and fix `.product(name:package:)`. If WhisperKit ≥0.18.0 fails to build on this toolchain, report BLOCKED with the error.

- [ ] **Step 3: Commit**

```bash
git add Packages/Speech/Package.swift Packages/Speech/Package.resolved
git commit -m "build(speech): add WhisperKit dependency

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `SpeechRecognizerChoice.whisperKit`

**Files:**
- Modify: `Packages/Speech/Sources/TideSpeech/Protocols/SpeechRecognizer.swift`
- Test: `Packages/Speech/Tests/TideSpeechTests/SpeechRecognizerChoiceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Packages/Speech/Tests/TideSpeechTests/SpeechRecognizerChoiceTests.swift`:

```swift
import XCTest
@testable import TideSpeech

final class SpeechRecognizerChoiceTests: XCTestCase {
  func test_whisperKit_isInAllCases() {
    XCTAssertTrue(SpeechRecognizerChoice.allCases.contains(.whisperKit))
  }

  func test_whisperKit_flags() {
    XCTAssertTrue(SpeechRecognizerChoice.whisperKit.requiresLocalModel)
    XCTAssertFalse(SpeechRecognizerChoice.whisperKit.requiresElevenLabsKey)
  }

  func test_nonLocalChoices_doNotRequireLocalModel() {
    XCTAssertFalse(SpeechRecognizerChoice.apple.requiresLocalModel)
    XCTAssertFalse(SpeechRecognizerChoice.elevenLabs.requiresLocalModel)
    XCTAssertFalse(SpeechRecognizerChoice.hybrid.requiresLocalModel)
  }

  func test_whisperKit_displayName() {
    XCTAssertFalse(SpeechRecognizerChoice.whisperKit.displayName.isEmpty)
  }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Packages/Speech && swift test --filter SpeechRecognizerChoiceTests 2>&1 | tail -12`
Expected: FAIL — `type 'SpeechRecognizerChoice' has no member 'whisperKit'`

- [ ] **Step 3: Implement**

In `Packages/Speech/Sources/TideSpeech/Protocols/SpeechRecognizer.swift`, edit the enum. Add the case:

```swift
public enum SpeechRecognizerChoice: String, Sendable, CaseIterable, Codable {
  case apple
  case elevenLabs
  case hybrid
  case whisperKit
```

Add `whisperKit` to `displayName`:

```swift
  public var displayName: String {
    switch self {
    case .apple:      "Apple (on-device, gratis)"
    case .elevenLabs: "ElevenLabs (höhere Genauigkeit)"
    case .hybrid:     "Hybrid (Apple live + ElevenLabs final)"
    case .whisperKit: "Lokal (WhisperKit, offline)"
    }
  }
```

Add `whisperKit` to `requiresElevenLabsKey` (false) and add a new flag:

```swift
  public var requiresElevenLabsKey: Bool {
    switch self {
    case .apple, .whisperKit:      false
    case .elevenLabs, .hybrid:     true
    }
  }

  /// True if this choice needs a local WhisperKit model installed.
  public var requiresLocalModel: Bool {
    self == .whisperKit
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Packages/Speech && swift test --filter SpeechRecognizerChoiceTests 2>&1 | tail -8`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/Protocols/SpeechRecognizer.swift \
        Packages/Speech/Tests/TideSpeechTests/SpeechRecognizerChoiceTests.swift
git commit -m "feat(speech): add .whisperKit recognizer choice

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `WhisperModelStore`

**Files:**
- Create: `Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperModelStore.swift`
- Test: `Packages/Speech/Tests/TideSpeechTests/WhisperModelStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Packages/Speech/Tests/TideSpeechTests/WhisperModelStoreTests.swift`:

```swift
import XCTest
@testable import TideSpeech

final class WhisperModelStoreTests: XCTestCase {
  private func tempBase() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("whisper-test-\(UUID().uuidString)", isDirectory: true)
  }

  func test_catalog_hasThreeModels_smallFirst() {
    let store = WhisperModelStore(baseDirectory: tempBase())
    let catalog = store.catalog()
    XCTAssertEqual(catalog.count, 3)
    XCTAssertEqual(catalog.first?.id, WhisperModelStore.smallModelID)
  }

  func test_modelURL_isUnderBaseDirectory() {
    let base = tempBase()
    let store = WhisperModelStore(baseDirectory: base)
    let url = store.modelURL(id: WhisperModelStore.smallModelID)
    XCTAssertTrue(url.path.hasPrefix(base.path))
    XCTAssertEqual(url.lastPathComponent, WhisperModelStore.smallModelID)
  }

  func test_isInstalled_falseForEmptyDir() {
    let store = WhisperModelStore(baseDirectory: tempBase())
    XCTAssertFalse(store.isInstalled(WhisperModelStore.smallModelID))
  }

  func test_isInstalled_trueWhenMarkersPresent() throws {
    let base = tempBase()
    let store = WhisperModelStore(baseDirectory: base)
    let id = WhisperModelStore.smallModelID
    let dir = store.modelURL(id: id)
    let fm = FileManager.default
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for marker in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
      try fm.createDirectory(at: dir.appendingPathComponent(marker), withIntermediateDirectories: true)
    }
    XCTAssertTrue(store.isInstalled(id))
    addTeardownBlock { try? fm.removeItem(at: base) }
  }

  func test_installedCatalog_flagsInstalledModel() throws {
    let base = tempBase()
    let store = WhisperModelStore(baseDirectory: base)
    let id = WhisperModelStore.smallModelID
    let dir = store.modelURL(id: id)
    let fm = FileManager.default
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for marker in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
      try fm.createDirectory(at: dir.appendingPathComponent(marker), withIntermediateDirectories: true)
    }
    let catalog = store.catalog()
    XCTAssertTrue(catalog.first { $0.id == id }?.isInstalled ?? false)
    XCTAssertFalse(catalog.first { $0.id == WhisperModelStore.largeV3ModelID }?.isInstalled ?? true)
    addTeardownBlock { try? fm.removeItem(at: base) }
  }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Packages/Speech && swift test --filter WhisperModelStoreTests 2>&1 | tail -12`
Expected: FAIL — `cannot find 'WhisperModelStore' in scope`

- [ ] **Step 3: Implement**

Create `Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperModelStore.swift`:

```swift
import Foundation
import OSLog
import WhisperKit

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "whisper-store")

/// Metadata for a WhisperKit CoreML model in the curated catalog.
public struct WhisperModelInfo: Identifiable, Sendable, Hashable {
  public let id: String
  public let displayName: String
  public let approxSizeMB: Int
  public let isInstalled: Bool
}

public enum WhisperModelError: LocalizedError {
  case modelMissing(String)
  case downloadIncomplete(String)

  public var errorDescription: String? {
    switch self {
    case .modelMissing(let id):     "Lokales Modell fehlt: \(id)"
    case .downloadIncomplete(let id): "Modell-Download unvollständig: \(id)"
    }
  }
}

/// Manages on-disk WhisperKit models: catalog, install detection, download.
/// Stateless aside from the injected base directory, so it is cheap to
/// construct anywhere (tests inject a temp directory).
public struct WhisperModelStore: Sendable {
  public static let smallModelID   = "openai_whisper-small_216MB"
  public static let turboModelID   = "openai_whisper-large-v3-v20240930_turbo_632MB"
  public static let largeV3ModelID = "openai_whisper-large-v3-v20240930_626MB"
  public static let modelRepo      = "argmaxinc/whisperkit-coreml"

  /// Catalog order = UI order. Small first (default, fastest).
  private static let entries: [(id: String, name: String, mb: Int)] = [
    (smallModelID,   "Whisper Small",          216),
    (turboModelID,   "Whisper Large v3 Turbo", 632),
    (largeV3ModelID, "Whisper Large v3",       626),
  ]

  public let baseDirectory: URL

  /// - Parameter baseDirectory: where models live. Defaults to
  ///   `~/Library/Application Support/Tide/models/whisperkit`.
  public init(baseDirectory: URL? = nil) {
    if let baseDirectory {
      self.baseDirectory = baseDirectory
    } else {
      let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first!
      self.baseDirectory = appSupport
        .appendingPathComponent("Tide", isDirectory: true)
        .appendingPathComponent("models", isDirectory: true)
        .appendingPathComponent("whisperkit", isDirectory: true)
    }
  }

  public func modelURL(id: String) -> URL {
    baseDirectory.appendingPathComponent(id, isDirectory: true)
  }

  public func isInstalled(_ id: String) -> Bool {
    let dir = modelURL(id: id)
    let fm = FileManager.default
    return ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"]
      .allSatisfy { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }
  }

  /// The curated catalog with per-entry install state.
  public func catalog() -> [WhisperModelInfo] {
    Self.entries.map {
      WhisperModelInfo(id: $0.id, displayName: $0.name, approxSizeMB: $0.mb, isInstalled: isInstalled($0.id))
    }
  }

  /// Download + install `id` from HuggingFace into `baseDirectory`. Reports
  /// fractional progress (0…1). No-op (progress 1) if already installed.
  /// Not unit-tested (network + CoreML); exercised by manual smoke test.
  public func download(
    id: String,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    if isInstalled(id) { progress(1); return }
    let fm = FileManager.default
    try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

    let downloadRoot = baseDirectory
      .appendingPathComponent("downloads", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: downloadRoot, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: downloadRoot) }

    let downloaded = try await WhisperKit.download(
      variant: id,
      downloadBase: downloadRoot,
      from: Self.modelRepo
    ) { p in
      let f = p.fractionCompleted
      progress(f.isFinite ? f : 0)
    }

    let destination = modelURL(id: id)
    if fm.fileExists(atPath: destination.path) {
      try fm.removeItem(at: destination)
    }
    try fm.moveItem(at: downloaded, to: destination)

    guard isInstalled(id) else {
      throw WhisperModelError.downloadIncomplete(id)
    }
    progress(1)
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Packages/Speech && swift test --filter WhisperModelStoreTests 2>&1 | tail -8`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperModelStore.swift \
        Packages/Speech/Tests/TideSpeechTests/WhisperModelStoreTests.swift
git commit -m "feat(speech): WhisperModelStore catalog + download

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `Transcribing` protocol + `WhisperKitTranscriber`

**Files:** Create `Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperKitTranscriber.swift`

No unit test — wraps WhisperKit (CoreML). Build-only; behaviour exercised via the recognizer's mock in Task 5 and the manual smoke test.

- [ ] **Step 1: Implement**

Create `Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperKitTranscriber.swift`:

```swift
import Foundation
import OSLog
import WhisperKit

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "whisper-transcriber")

/// Abstraction over a local transcription engine so `WhisperKitRecognizer`
/// can be unit-tested with a mock.
public protocol Transcribing: Sendable {
  func transcribe(wav: Data, language: String?, modelName: String) async throws -> String
}

/// One shared actor instance (built in AppEntry, reached via
/// `LocalTranscriberHolder`). Owns the loaded WhisperKit pipeline; the
/// pipeline never crosses the actor boundary (Swift-6 non-Sendable safe).
/// Reloads when a different `modelName` is requested.
public actor WhisperKitTranscriber: Transcribing {
  private let store: WhisperModelStore
  private var pipeline: WhisperKit?
  private var loadedModelName: String?

  public init(store: WhisperModelStore) {
    self.store = store
  }

  /// Load (and cache) the pipeline for `modelName` so the first dictation
  /// has no cold-start spike. Safe to call repeatedly.
  public func prewarm(modelName: String) async throws {
    _ = try await loadedPipeline(modelName: modelName)
  }

  public func transcribe(wav: Data, language: String?, modelName: String) async throws -> String {
    let pipeline = try await loadedPipeline(modelName: modelName)

    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
    try wav.write(to: tmp)
    defer { try? fm.removeItem(at: tmp) }

    let options = DecodingOptions(task: .transcribe, language: language)
    let results = try await pipeline.transcribe(audioPath: tmp.path, decodeOptions: options)
    return results
      .map(\.text)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func loadedPipeline(modelName: String) async throws -> WhisperKit {
    if let pipeline, loadedModelName == modelName { return pipeline }
    let url = store.modelURL(id: modelName)
    guard store.isInstalled(modelName) else {
      throw WhisperModelError.modelMissing(modelName)
    }
    log.debug("loading WhisperKit model \(modelName, privacy: .public)")
    let loaded = try await WhisperKit(
      modelFolder: url.path,
      verbose: false,
      prewarm: true,
      load: true,
      download: false
    )
    pipeline = loaded
    loadedModelName = modelName
    return loaded
  }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/Speech && swift build 2>&1 | tail -8`
Expected: `Build complete!`

If `WhisperKit.transcribe`'s return element doesn't expose `.text`, or `DecodingOptions`/init labels differ in 0.18.0, adjust to the real API (keep the write-temp → transcribe-path → join shape). Report BLOCKED only if no path-based transcribe exists.

- [ ] **Step 3: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperKitTranscriber.swift
git commit -m "feat(speech): WhisperKitTranscriber + Transcribing protocol

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `WhisperKitRecognizer`

**Files:**
- Create: `Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperKitRecognizer.swift`
- Test: `Packages/Speech/Tests/TideSpeechTests/WhisperKitRecognizerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Packages/Speech/Tests/TideSpeechTests/WhisperKitRecognizerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Packages/Speech && swift test --filter WhisperKitRecognizerTests 2>&1 | tail -12`
Expected: FAIL — `cannot find 'WhisperKitRecognizer' in scope`

- [ ] **Step 3: Implement**

Create `Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperKitRecognizer.swift`:

```swift
import Foundation
import AVFoundation
import OSLog

/// Non-streaming `SpeechRecognizer` backed by a local WhisperKit model.
/// Mirrors `ElevenLabsRecognizer`: an external `AudioBufferAccumulator`
/// collects PCM during recording; on `stop()` we hand the WAV snapshot to
/// the shared `Transcribing` engine. No live partials.
///
/// On any failure we log and return "" so the caller's empty/reject
/// handling kicks in (never crash a dictation over a model error).
public final class WhisperKitRecognizer: SpeechRecognizer, @unchecked Sendable {
  private let transcriber: any Transcribing
  private let modelName: String
  private let bufferProvider: @Sendable () -> Data?
  private let language: String?
  private let partialContinuation: AsyncStream<String>.Continuation
  public let partialTranscript: AsyncStream<String>

  private static let logger = Logger(subsystem: "swiss.weckherlin.tide", category: "whisper-recognizer")

  public init(
    transcriber: any Transcribing,
    modelName: String,
    bufferProvider: @escaping @Sendable () -> Data?,
    language: String?
  ) {
    self.transcriber = transcriber
    self.modelName = modelName
    self.bufferProvider = bufferProvider
    self.language = language
    var continuation: AsyncStream<String>.Continuation!
    self.partialTranscript = AsyncStream<String> { continuation = $0 }
    self.partialContinuation = continuation
  }

  public func start() async throws {
    // Non-streaming: nothing to do. Audio is collected app-side by the
    // AudioBufferAccumulator and handed back via bufferProvider on stop().
  }

  public func feed(_ buffer: AVAudioPCMBuffer) {
    // No-op (see start()).
  }

  public func stop() async throws -> String {
    partialContinuation.finish()
    guard let wav = bufferProvider() else {
      Self.logger.debug("No buffered audio to transcribe.")
      return ""
    }
    do {
      return try await transcriber.transcribe(wav: wav, language: language, modelName: modelName)
    } catch {
      Self.logger.warning("WhisperKit transcribe failed: \(error.localizedDescription, privacy: .public) — returning empty")
      return ""
    }
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Packages/Speech && swift test --filter WhisperKitRecognizerTests 2>&1 | tail -8`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperKitRecognizer.swift \
        Packages/Speech/Tests/TideSpeechTests/WhisperKitRecognizerTests.swift
git commit -m "feat(speech): WhisperKitRecognizer (non-streaming, local)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: `LocalTranscriberHolder` + `AppSettings.localModelName`

**Files:**
- Create: `Packages/Speech/Sources/TideSpeech/WhisperKit/LocalTranscriberHolder.swift`
- Modify: `Packages/Core/Sources/Core/Settings/AppSettings.swift`
- Test: `Packages/Core/Tests/CoreTests/AppSettingsTests.swift`

- [ ] **Step 1: Create the holder**

Create `Packages/Speech/Sources/TideSpeech/WhisperKit/LocalTranscriberHolder.swift`:

```swift
import Foundation

/// Single access point for the process-wide shared `Transcribing` instance.
///
/// SwiftUI Settings views can't receive constructor-injected dependencies,
/// and `RecognizerFactory` is a static enum — so AppEntry sets the shared
/// `WhisperKitTranscriber` here once at launch and every consumer reads it.
@MainActor
public final class LocalTranscriberHolder {
  public static let shared = LocalTranscriberHolder()
  public var transcriber: (any Transcribing)?
  private init() {}
}
```

- [ ] **Step 2: Write the failing AppSettings test**

Append to `Packages/Core/Tests/CoreTests/AppSettingsTests.swift` inside the class:

```swift
  @MainActor
  func testLocalModelNameDefaultsToSmall() {
    let s = AppSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    XCTAssertEqual(s.localModelName, "openai_whisper-small_216MB")
  }

  @MainActor
  func testLocalModelNameRoundTrip() {
    let suite = "test.\(UUID().uuidString)"
    let defs = UserDefaults(suiteName: suite)!
    let s = AppSettings(defaults: defs)
    s.localModelName = "openai_whisper-large-v3-v20240930_626MB"
    let reloaded = AppSettings(defaults: defs)
    XCTAssertEqual(reloaded.localModelName, "openai_whisper-large-v3-v20240930_626MB")
  }
```

- [ ] **Step 3: Run AppSettings test to verify it fails**

Run: `cd Packages/Core && swift test --filter AppSettingsTests 2>&1 | tail -12`
Expected: FAIL — no member `localModelName`

- [ ] **Step 4: Implement localModelName**

In `Packages/Core/Sources/Core/Settings/AppSettings.swift`, add to `Key` enum:

```swift
    static let localModelName = "tide.localModelName"
```

Add the property (after `customVocabulary` or at class end):

```swift
  /// Which WhisperKit model the local recognizer uses. Stored as the
  /// model's catalog id. Default: Whisper Small (fastest, 216 MB).
  public var localModelName: String {
    get { defaults.string(forKey: Key.localModelName) ?? "openai_whisper-small_216MB" }
    set { defaults.set(newValue, forKey: Key.localModelName) }
  }
```

- [ ] **Step 5: Build the package + run tests**

Run: `cd Packages/Speech && swift build 2>&1 | tail -3`
Expected: `Build complete!` (LocalTranscriberHolder compiles)

Run: `cd Packages/Core && swift test --filter AppSettingsTests 2>&1 | tail -6`
Expected: PASS (incl. 2 new)

- [ ] **Step 6: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/WhisperKit/LocalTranscriberHolder.swift \
        Packages/Core/Sources/Core/Settings/AppSettings.swift \
        Packages/Core/Tests/CoreTests/AppSettingsTests.swift
git commit -m "feat: LocalTranscriberHolder + AppSettings.localModelName

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: `RecognizerFactory` `.whisperKit` branch + call sites

**Files:**
- Modify: `Tide/Dictation/RecognizerFactory.swift`
- Modify: `Tide/Dictation/DictationCoordinator.swift`
- Modify: `Tide/Panel/ChatViewModel.swift`

- [ ] **Step 1: Extend the factory**

In `Tide/Dictation/RecognizerFactory.swift`, change the `make` signature and add the branch. Replace the whole `make` body. Current signature ends `accumulator: AudioBufferAccumulator, vocabulary: [String] = []` and starts `let apple = AppleSpeechRecognizer(contextualStrings: vocabulary)`. New version:

```swift
  static func make(
    for choice: SpeechRecognizerChoice,
    apiKey: String?,
    accumulator: AudioBufferAccumulator,
    vocabulary: [String] = [],
    localModelName: String = "",
    localModelInstalled: Bool = false,
    transcriber: (any Transcribing)? = nil
  ) -> any SpeechRecognizer {
    let apple = AppleSpeechRecognizer(contextualStrings: vocabulary)

    // Local WhisperKit: only when a model is installed AND the shared
    // transcriber exists. Otherwise fall back to Apple (logged), so a
    // user who picked Local but hasn't downloaded a model still dictates.
    if choice == .whisperKit {
      if localModelInstalled, let transcriber {
        return WhisperKitRecognizer(
          transcriber: transcriber,
          modelName: localModelName,
          bufferProvider: { accumulator.exportWAV(sampleRate: 16000, channels: 1) },
          language: nil
        )
      }
      return apple
    }

    guard choice != .apple, let key = apiKey, !key.isEmpty else {
      return apple
    }

    let client = ElevenLabsClient(apiKey: key)
    let elevenRecognizer = ElevenLabsRecognizer(
      client: client,
      bufferProvider: {
        accumulator.exportWAV(sampleRate: 16000, channels: 1)
      }
    )

    switch choice {
    case .elevenLabs:
      return elevenRecognizer
    case .hybrid:
      return HybridRecognizer(apple: apple, eleven: elevenRecognizer)
    case .apple, .whisperKit:
      return apple
    }
  }
```

- [ ] **Step 2: Pass the new args from `DictationCoordinator.start`**

In `Tide/Dictation/DictationCoordinator.swift`, find the `RecognizerFactory.make` call in `start()` (currently passes `for/apiKey/accumulator/vocabulary`). Add this line just before the call:

```swift
    let localStore = WhisperModelStore()
```

Change the call to:

```swift
    let recognizer = RecognizerFactory.make(
      for: choice,
      apiKey: apiKey,
      accumulator: accumulator,
      vocabulary: settings.customVocabulary,
      localModelName: settings.localModelName,
      localModelInstalled: localStore.isInstalled(settings.localModelName),
      transcriber: LocalTranscriberHolder.shared.transcriber
    )
```

Ensure `import TideSpeech` is present at the top of the file (it already is).

- [ ] **Step 3: Pass the new args from `ChatViewModel.startRecording`**

In `Tide/Panel/ChatViewModel.swift`, find the `RecognizerFactory.make` call in `startRecording()`. Add before it:

```swift
    let localStore = WhisperModelStore()
```

Change the call to:

```swift
    let recognizer = RecognizerFactory.make(
      for: choice,
      apiKey: apiKey,
      accumulator: accumulator,
      vocabulary: settings.customVocabulary,
      localModelName: settings.localModelName,
      localModelInstalled: localStore.isInstalled(settings.localModelName),
      transcriber: LocalTranscriberHolder.shared.transcriber
    )
```

(`ChatViewModel` already `import TideSpeech`.)

- [ ] **Step 4: Build**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add Tide/Dictation/RecognizerFactory.swift Tide/Dictation/DictationCoordinator.swift Tide/Panel/ChatViewModel.swift
git commit -m "feat(dictation): RecognizerFactory .whisperKit branch + wiring

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: `AppEntry` — build holder + prewarm

**Files:** Modify `Tide/AppEntry.swift`

- [ ] **Step 1: Build the shared transcriber, set the holder, prewarm**

In `Tide/AppEntry.swift`, add `import TideSpeech` at the top (alongside the other imports).

Inside `applicationDidFinishLaunching`'s `Task { @MainActor in … }`, after `let settings = AppSettings()` and before/around the controller setup, add:

```swift
        // WhisperKit local transcription: build the one shared transcriber
        // and publish it via the holder so the recognizer factory + the
        // Local settings tab can reach it. Prewarm the model in the
        // background if the user already runs Local — avoids a cold-start
        // spike on the first dictation. No CoreML cost when Local is off.
        let localStore = WhisperModelStore()
        let transcriber = WhisperKitTranscriber(store: localStore)
        LocalTranscriberHolder.shared.transcriber = transcriber
        if settings.speechRecognizer == SpeechRecognizerChoice.whisperKit.rawValue,
           localStore.isInstalled(settings.localModelName) {
          let modelName = settings.localModelName
          Task.detached { try? await transcriber.prewarm(modelName: modelName) }
        }
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add Tide/AppEntry.swift
git commit -m "feat(app): build shared WhisperKitTranscriber + prewarm on launch

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: `LocalModelSection` UI + tab + VoiceSection hint

**Files:**
- Create: `Tide/Settings/LocalModelSection.swift`
- Modify: `Tide/Settings/SettingsWindow.swift`
- Modify: `Tide/Settings/VoiceSection.swift`

No unit test — SwiftUI glue, verified by build + manual smoke.

- [ ] **Step 1: Create LocalModelSection**

Create `Tide/Settings/LocalModelSection.swift`:

```swift
import SwiftUI
import Core
import TideSpeech

/// Settings tab for the local WhisperKit models: pick a model, download it
/// (with progress), see install state. Fully offline & free after download.
struct LocalModelSection: View {
  @State private var settings = AppSettings()
  @State private var store = WhisperModelStore()
  @State private var catalog: [WhisperModelInfo] = []
  @State private var selectedModel: String = ""
  @State private var downloading = false
  @State private var downloadProgress: Double = 0
  @State private var downloadError: String?

  var body: some View {
    Form {
      Section {
        Text("Vollständig offline & gratis nach dem Download. Wähle danach "
          + "‚Lokal (WhisperKit, offline)' als Recognizer unter Stimme.")
          .font(.caption)
          .foregroundStyle(.secondary)

        Picker("Modell:", selection: $selectedModel) {
          ForEach(catalog) { model in
            Text("\(model.displayName) · \(model.approxSizeMB) MB"
              + (model.isInstalled ? " ✓" : ""))
              .tag(model.id)
          }
        }
        .onChange(of: selectedModel) { _, newValue in
          settings.localModelName = newValue
          prewarmIfInstalled(newValue)
        }

        if let selected = catalog.first(where: { $0.id == selectedModel }) {
          if selected.isInstalled {
            Label("Installiert", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
              .font(.caption)
          } else if downloading {
            ProgressView(value: downloadProgress) {
              Text("Lädt … \(Int(downloadProgress * 100)) %").font(.caption)
            }
          } else {
            Button("Modell laden (\(selected.approxSizeMB) MB)") {
              download(selected.id)
            }
          }
        }

        if let downloadError {
          Text(downloadError).foregroundStyle(.red).font(.caption)
        }
      } header: { Text("Lokales Modell (WhisperKit)") }
    }
    .formStyle(.grouped)
    .task {
      catalog = store.catalog()
      selectedModel = settings.localModelName
      prewarmIfInstalled(selectedModel)
    }
  }

  private func refreshCatalog() {
    catalog = store.catalog()
  }

  private func prewarmIfInstalled(_ id: String) {
    guard store.isInstalled(id),
          let transcriber = LocalTranscriberHolder.shared.transcriber else { return }
    Task.detached { try? await transcriber.prewarm(modelName: id) }
  }

  private func download(_ id: String) {
    downloading = true
    downloadProgress = 0
    downloadError = nil
    let store = self.store
    Task {
      do {
        try await store.download(id: id) { p in
          Task { @MainActor in downloadProgress = p }
        }
        await MainActor.run {
          downloading = false
          refreshCatalog()
          prewarmIfInstalled(id)
        }
      } catch {
        await MainActor.run {
          downloading = false
          downloadError = "Download fehlgeschlagen: \(error.localizedDescription)"
        }
      }
    }
  }
}
```

- [ ] **Step 2: Hook the tab into SettingsWindow**

In `Tide/Settings/SettingsWindow.swift`, add after the `VocabularySection` tab:

```swift
      VocabularySection()
        .tabItem { Label("Vokabular", systemImage: "character.book.closed") }
      LocalModelSection()
        .tabItem { Label("Lokal", systemImage: "internaldrive") }
      QuickActionsEditor()
        .tabItem { Label("Actions", systemImage: "bolt") }
```

- [ ] **Step 3: VoiceSection no-model hint**

In `Tide/Settings/VoiceSection.swift`, the recognizer picker's `.onChange(of: recognizerChoice)` currently snaps back to Apple when `newChoice.requiresElevenLabsKey && elevenLabsKey.isEmpty`. Add a parallel guard for the local model. Replace the `.onChange` closure body with:

```swift
        .onChange(of: recognizerChoice) { _, newChoice in
          if newChoice.requiresElevenLabsKey, elevenLabsKey.isEmpty {
            recognizerChoice = .apple
            settings.speechRecognizer = SpeechRecognizerChoice.apple.rawValue
            showRecognizerKeyMissingHint = true
            showLocalModelMissingHint = false
          } else if newChoice.requiresLocalModel,
                    !WhisperModelStore().isInstalled(settings.localModelName) {
            recognizerChoice = .apple
            settings.speechRecognizer = SpeechRecognizerChoice.apple.rawValue
            showLocalModelMissingHint = true
            showRecognizerKeyMissingHint = false
          } else {
            settings.speechRecognizer = newChoice.rawValue
            showRecognizerKeyMissingHint = false
            showLocalModelMissingHint = false
          }
        }
```

Add the new `@State` near `showRecognizerKeyMissingHint`:

```swift
  @State private var showLocalModelMissingHint = false
```

And add a hint view after the existing `showRecognizerKeyMissingHint` block:

```swift
        if showLocalModelMissingHint {
          Text("Kein lokales Modell installiert — lade erst eines im "
            + "‚Lokal'-Tab, dann erneut wählen.")
            .font(.caption)
            .foregroundStyle(.orange)
        }
```

- [ ] **Step 4: Build**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Manual smoke test**

`xcodegen generate` then build + run in Xcode (Cmd+R). Settings → Lokal:
1. Pick "Whisper Small" → "Modell laden (216 MB)" → progress bar advances → ✓ Installiert.
2. Settings → Stimme → pick "Lokal (WhisperKit, offline)" → stays selected (model installed).
3. Disconnect network. Dictate (raw hotkey) → text appears at cursor (offline).
4. Settings → Stimme with no model installed → picking Local snaps back to Apple + hint.

- [ ] **Step 6: Commit**

```bash
git add Tide/Settings/LocalModelSection.swift Tide/Settings/SettingsWindow.swift Tide/Settings/VoiceSection.swift
git commit -m "feat(settings): local model download tab + recognizer hint

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: Docs (README + CHANGELOG)

**Files:** `README.md`, `CHANGELOG.md`

- [ ] **Step 1: CHANGELOG**

Under `## [Unreleased]` → `### Added`, add:

```markdown
- **Lokale Transkription (WhisperKit)** — vollständig offline & gratis via
  WhisperKit/CoreML. Neuer Recognizer „Lokal (WhisperKit, offline)", In-App
  Modell-Download (Whisper Small / Large v3 Turbo / Large v3) im neuen
  Settings-Tab ‚Lokal', Prewarm beim Start. Kein Audio verlässt den Mac.
  Portiert aus Blitztext.
```

- [ ] **Step 2: README dependency note**

In `README.md`, find the architecture/dependency note that says external deps are only `KeyboardShortcuts` und `Sparkle`. Update it to mention WhisperKit, e.g. change that sentence to:

```markdown
Geteilte Pakete sind alle local. Externe Dependencies: `KeyboardShortcuts`, `Sparkle` und `WhisperKit` (argmax-oss-swift, für lokale On-Device-Transkription).
```

Also add a bullet to the "Was Tide kann" list:

```markdown
- **Lokale Transkription** via WhisperKit/CoreML — offline, gratis, kein Audio verlässt den Mac (Modell-Download in Settings → Lokal)
```

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: WhisperKit local transcription

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** dependency (T1), choice (T2), store (T3), transcriber (T4), recognizer (T5), holder + settings (T6), factory + call sites (T7), prewarm/AppEntry (T8), UI tab + hint (T9), docs (T10). All spec sections covered.
- **Type consistency:** `WhisperModelStore` (`smallModelID`/`turboModelID`/`largeV3ModelID`, `catalog()`, `isInstalled`, `modelURL(id:)`, `download(id:progress:)`), `Transcribing.transcribe(wav:language:modelName:)`, `WhisperKitTranscriber.prewarm(modelName:)`, `WhisperKitRecognizer(transcriber:modelName:bufferProvider:language:)`, `RecognizerFactory.make(…, localModelName:, localModelInstalled:, transcriber:)`, `LocalTranscriberHolder.shared.transcriber`, `AppSettings.localModelName`, `SpeechRecognizerChoice.whisperKit`/`requiresLocalModel` — consistent across tasks.
- **Backward-compat:** all new `make` params default, so existing `RecognizerFactoryTests` compile unchanged; `AppleSpeechRecognizer`/others untouched.
- **Test command:** app target needs `CODE_SIGNING_ALLOWED=NO`.
- **API risk:** WhisperKit signatures (T1/T3/T4) follow Blitztext 0.18.0; the plan instructs adjusting to the real API at build time and reporting BLOCKED only if the path-based transcribe model is absent.
```
