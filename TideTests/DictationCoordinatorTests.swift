import XCTest
import Core
import Selection
@testable import Tide

/// Tests for the standalone-dictation orchestration: the
/// stop()/reject/transform/transform-fail→raw paths, driven through the
/// coordinator's injection seams (fake recorder, spy injector, no-op
/// notification) — no microphone, key events or notification center.
///
/// **Keychain caveat**: the transform branches go through
/// `DictationPolisher`, which requires an Anthropic key in the keychain.
/// Same sentinel pattern as `DictationPolisherTests` — the value is
/// never sent anywhere because the provider is stubbed.
@MainActor
final class DictationCoordinatorTests: XCTestCase {

  private var defaults: UserDefaults!
  private var settings: AppSettings!
  private var originalAPIKey: String?
  private static let sentinelAPIKey = "tide-test-sentinel-key"

  override func setUp() async throws {
    let suite = "tide.tests.DictationCoordinator.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)
    settings = AppSettings(defaults: defaults)
    originalAPIKey = KeychainHelper.get(key: KeychainKey.anthropic)
    try KeychainHelper.set(key: KeychainKey.anthropic, value: Self.sentinelAPIKey)
  }

  override func tearDown() async throws {
    if let original = originalAPIKey {
      try KeychainHelper.set(key: KeychainKey.anthropic, value: original)
    } else {
      KeychainHelper.delete(key: KeychainKey.anthropic)
    }
    settings = nil
    defaults = nil
  }

  // MARK: - Harness

  /// Coordinator wired to a fake recording and a spy injector.
  private func makeSUT(
    recording: FakeRecording,
    provider: StubProvider = StubProvider(chunks: ["unused"])
  ) -> (DictationCoordinator, InsertSpy) {
    let spy = InsertSpy()
    let coordinator = DictationCoordinator(
      settings: settings,
      provider: provider,
      makeRecorder: { _ in recording },
      insertText: { text in
        spy.inserted.append(text)
        return .axInsert
      },
      notifyPolishFailed: { spy.polishFailedNotices += 1 }
    )
    return (coordinator, spy)
  }

  // MARK: - Reject path

  func test_stop_rejectsTooShortRecording_insertsNothing() async {
    let recording = FakeRecording(transcript: "Untertitel", duration: 0.1)
    let (sut, spy) = makeSUT(recording: recording)

    await sut.start(mode: .raw)
    XCTAssertTrue(sut.isActive)
    await sut.stop()

    XCTAssertEqual(spy.inserted, [])
    XCTAssertFalse(sut.isActive)
  }

  func test_stop_rejectsEmptyTranscript_insertsNothing() async {
    let recording = FakeRecording(transcript: "   \n ", duration: 3.0)
    let (sut, spy) = makeSUT(recording: recording)

    await sut.start(mode: .raw)
    await sut.stop()

    XCTAssertEqual(spy.inserted, [])
  }

  // MARK: - Raw mode

  func test_stop_rawMode_insertsTrimmedTranscript() async {
    let recording = FakeRecording(transcript: "  hallo welt \n", duration: 2.0)
    let (sut, spy) = makeSUT(recording: recording)

    await sut.start(mode: .raw)
    await sut.stop()

    XCTAssertEqual(spy.inserted, ["hallo welt"])
    XCTAssertEqual(spy.polishFailedNotices, 0)
  }

  // MARK: - Transform mode

  func test_stop_transformMode_insertsTransformedText() async {
    let recording = FakeRecording(transcript: "der rohe text", duration: 2.0)
    let provider = StubProvider(chunks: ["Der ", "polierte ", "Text."])
    let (sut, spy) = makeSUT(recording: recording, provider: provider)

    await sut.start(mode: .polished)
    await sut.stop()

    XCTAssertEqual(spy.inserted, ["Der polierte Text."])
    XCTAssertEqual(spy.polishFailedNotices, 0)
  }

  func test_stop_transformFailure_fallsBackToRawAndNotifies() async {
    let recording = FakeRecording(transcript: "der rohe text", duration: 2.0)
    let provider = StubProvider(behavior: .throwImmediately)
    let (sut, spy) = makeSUT(recording: recording, provider: provider)

    await sut.start(mode: .polished)
    await sut.stop()

    XCTAssertEqual(spy.inserted, ["der rohe text"])
    XCTAssertEqual(spy.polishFailedNotices, 1)
  }

  // MARK: - Lifecycle

  func test_secondStart_whileActive_isIgnored() async {
    let recording = FakeRecording(transcript: "x", duration: 2.0)
    let (sut, _) = makeSUT(recording: recording)

    await sut.start(mode: .raw)
    await sut.start(mode: .polished)

    XCTAssertEqual(recording.startCount, 1)
  }

  func test_stopDuringStartAwait_supersedesSession_noInsert() async {
    let recording = FakeRecording(transcript: "", duration: 0)
    recording.startDelayNanos = 50_000_000
    let (sut, spy) = makeSUT(recording: recording)

    async let starting: Void = sut.start(mode: .raw)
    // Give start() time to store the recorder and suspend in rec.start().
    try? await Task.sleep(nanoseconds: 10_000_000)
    await sut.stop()
    await starting

    // stop() finalized once; start()'s superseded-guard tore down again.
    XCTAssertEqual(recording.stopCount, 2)
    XCTAssertEqual(spy.inserted, [])
    XCTAssertFalse(sut.isActive)
  }

  func test_startFailure_resetsState() async {
    let recording = FakeRecording(transcript: "x", duration: 2.0)
    recording.startError = NSError(domain: "test", code: 1)
    let (sut, _) = makeSUT(recording: recording)

    await sut.start(mode: .raw)

    XCTAssertFalse(sut.isActive)
  }
}

// MARK: - Test doubles

/// Scripted `DictationRecording` — returns a fixed transcript/duration,
/// optionally fails or delays `start()`.
@MainActor
private final class FakeRecording: DictationRecording {
  var transcript: String
  var duration: TimeInterval
  var startError: Error?
  var startDelayNanos: UInt64 = 0
  private(set) var startCount = 0
  private(set) var stopCount = 0

  init(transcript: String, duration: TimeInterval) {
    self.transcript = transcript
    self.duration = duration
  }

  func start() async throws {
    startCount += 1
    if startDelayNanos > 0 {
      try? await Task.sleep(nanoseconds: startDelayNanos)
    }
    if let startError { throw startError }
  }

  func stop() async throws -> String {
    stopCount += 1
    return transcript
  }

  var partialTranscript: AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}

/// Records what the coordinator tried to insert / notify.
@MainActor
private final class InsertSpy {
  var inserted: [String] = []
  var polishFailedNotices = 0
}
