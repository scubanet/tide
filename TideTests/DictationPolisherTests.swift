import XCTest
import LLM
import Core
@testable import Tide

/// Tests for the Phase E `DictationPolisher`.
///
/// **Keychain caveat**: `DictationPolisher.polish(_:)` checks
/// `KeychainHelper.get(key: "anthropic.api_key")` up-front and throws
/// `.missingAPIKey` if it's empty. These tests assume an API key has
/// been planted in the keychain by the user's normal Tide usage
/// (developer machine) — that's the same precondition the `.polished`
/// hotkey requires in practice. To keep CI happy / local runs
/// deterministic we plant a sentinel key in `setUp` and remove it in
/// `tearDown`. The sentinel is never sent to a real server because
/// every test injects a `StubProvider`.
///
/// The missing-API-key branch is covered by deleting the key for the
/// duration of that single test and restoring it afterwards.
@MainActor
final class DictationPolisherTests: XCTestCase {

  /// Distinct UserDefaults suite per test so `dictationPolishPrompt`
  /// edits don't bleed between tests.
  private var defaults: UserDefaults!
  private var settings: AppSettings!
  /// Sentinel key planted in the real keychain for the test's
  /// lifetime. The polisher only checks `!isEmpty`, so the value
  /// doesn't matter — it's never sent anywhere because the provider
  /// is stubbed.
  private static let sentinelAPIKey = "tide-test-sentinel-key"
  /// Whatever real key was already in the keychain when the test
  /// started, so we can restore it on tearDown.
  private var originalAPIKey: String?

  override func setUp() async throws {
    let suite = "tide.tests.DictationPolisher.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)
    settings = AppSettings(defaults: defaults)
    originalAPIKey = KeychainHelper.get(key: "anthropic.api_key")
    try KeychainHelper.set(key: "anthropic.api_key", value: Self.sentinelAPIKey)
  }

  override func tearDown() async throws {
    if let original = originalAPIKey {
      try KeychainHelper.set(key: "anthropic.api_key", value: original)
    } else {
      KeychainHelper.delete(key: "anthropic.api_key")
    }
    defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "")
    settings = nil
    defaults = nil
  }

  // MARK: - Happy path

  func test_polish_concatenatesTextChunks() async throws {
    let stub = StubProvider(chunks: ["The ", "polished ", "text."])
    let polisher = DictationPolisher(
      provider: stub,
      settings: settings,
      timeoutSeconds: 2
    )
    let out = try await polisher.polish("the raw text", basePrompt: settings.dictationPolishPrompt)
    XCTAssertEqual(out, "The polished text.")
  }

  func test_polish_trimsLeadingAndTrailingWhitespace() async throws {
    // Claude sometimes adds a trailing newline. Trim it.
    let stub = StubProvider(chunks: ["  Polished.\n"])
    let polisher = DictationPolisher(
      provider: stub,
      settings: settings,
      timeoutSeconds: 2
    )
    let out = try await polisher.polish("raw", basePrompt: settings.dictationPolishPrompt)
    XCTAssertEqual(out, "Polished.")
  }

  // MARK: - Wiring assertions

  func test_polish_forwardsBasePrompt() async throws {
    let stub = StubProvider(chunks: ["ok"])
    let polisher = DictationPolisher(provider: stub, settings: settings, timeoutSeconds: 2)
    _ = try await polisher.polish("raw", basePrompt: "MY CUSTOM PROMPT")
    XCTAssertEqual(stub.lastSystemPrompt, "MY CUSTOM PROMPT")
  }

  func test_polish_sendsRawTextAsSingleUserMessage() async throws {
    let stub = StubProvider(chunks: ["ok"])
    let polisher = DictationPolisher(
      provider: stub,
      settings: settings,
      timeoutSeconds: 2
    )
    _ = try await polisher.polish("the raw transcript", basePrompt: settings.dictationPolishPrompt)
    XCTAssertEqual(stub.lastMessages?.count, 1)
    XCTAssertEqual(stub.lastMessages?.first?.role, .user)
    XCTAssertEqual(stub.lastMessages?.first?.content, "the raw transcript")
  }

  func test_polish_forwardsSelectedModelFromSettings() async throws {
    settings.selectedModel = "claude-opus-test"
    let stub = StubProvider(chunks: ["ok"])
    let polisher = DictationPolisher(
      provider: stub,
      settings: settings,
      timeoutSeconds: 2
    )
    _ = try await polisher.polish("raw", basePrompt: settings.dictationPolishPrompt)
    XCTAssertEqual(stub.lastModel, "claude-opus-test")
  }

  // MARK: - Failure modes

  func test_polish_throwsMissingAPIKey_whenKeychainEmpty() async {
    // Temporarily wipe the sentinel — restore in defer so tearDown's
    // restore-original still has the right starting state.
    KeychainHelper.delete(key: "anthropic.api_key")
    defer {
      try? KeychainHelper.set(
        key: "anthropic.api_key",
        value: Self.sentinelAPIKey
      )
    }
    let stub = StubProvider(chunks: ["never-called"])
    let polisher = DictationPolisher(
      provider: stub,
      settings: settings,
      timeoutSeconds: 2
    )
    do {
      _ = try await polisher.polish("raw", basePrompt: settings.dictationPolishPrompt)
      XCTFail("expected missingAPIKey")
    } catch DictationPolisher.PolishError.missingAPIKey {
      // ok
    } catch {
      XCTFail("expected missingAPIKey, got \(error)")
    }
    XCTAssertNil(
      stub.lastMessages,
      "provider must not be called when key is missing"
    )
  }

  func test_polish_throwsEmpty_whenStreamHasNoText() async {
    let stub = StubProvider(chunks: [])  // empty stream
    let polisher = DictationPolisher(
      provider: stub,
      settings: settings,
      timeoutSeconds: 2
    )
    do {
      _ = try await polisher.polish("raw", basePrompt: settings.dictationPolishPrompt)
      XCTFail("expected empty")
    } catch DictationPolisher.PolishError.empty {
      // ok
    } catch {
      XCTFail("expected empty, got \(error)")
    }
  }

  func test_polish_throwsEmpty_whenStreamOnlyWhitespace() async {
    let stub = StubProvider(chunks: ["   ", "\n\n"])
    let polisher = DictationPolisher(
      provider: stub,
      settings: settings,
      timeoutSeconds: 2
    )
    do {
      _ = try await polisher.polish("raw", basePrompt: settings.dictationPolishPrompt)
      XCTFail("expected empty")
    } catch DictationPolisher.PolishError.empty {
      // ok
    } catch {
      XCTFail("expected empty, got \(error)")
    }
  }

  func test_polish_throwsTimeout_whenStreamBlocks() async {
    // Stub never emits and never completes. With a 200ms cap the
    // timeout task wins quickly.
    let stub = StubProvider(behavior: .blockForever)
    let polisher = DictationPolisher(
      provider: stub,
      settings: settings,
      timeoutSeconds: 0.2
    )
    let started = Date()
    do {
      _ = try await polisher.polish("raw", basePrompt: settings.dictationPolishPrompt)
      XCTFail("expected timeout")
    } catch DictationPolisher.PolishError.timeout {
      let elapsed = Date().timeIntervalSince(started)
      XCTAssertLessThan(elapsed, 2.0, "timeout took too long")
    } catch {
      XCTFail("expected timeout, got \(error)")
    }
  }

  func test_polish_throwsProvider_whenStreamErrors() async {
    let stub = StubProvider(behavior: .throwImmediately)
    let polisher = DictationPolisher(
      provider: stub,
      settings: settings,
      timeoutSeconds: 2
    )
    do {
      _ = try await polisher.polish("raw", basePrompt: settings.dictationPolishPrompt)
      XCTFail("expected provider error")
    } catch DictationPolisher.PolishError.provider {
      // ok
    } catch {
      XCTFail("expected provider error, got \(error)")
    }
  }

  // MARK: - Custom vocabulary injection

  func test_polish_appendsVocabularyToSystemPrompt() async throws {
    settings.customVocabulary = ["PADI", "SeaExplorers"]
    let stub = StubProvider(chunks: ["ok"])
    let polisher = DictationPolisher(
      provider: stub,
      settings: settings,
      timeoutSeconds: 2
    )
    _ = try await polisher.polish("raw", basePrompt: "BASE PROMPT")
    let prompt = try XCTUnwrap(stub.lastSystemPrompt)
    XCTAssertTrue(prompt.hasPrefix("BASE PROMPT"))
    XCTAssertTrue(prompt.contains("PADI"))
    XCTAssertTrue(prompt.contains("SeaExplorers"))
  }

  func test_polish_leavesSystemPromptUnchanged_whenNoVocabulary() async throws {
    // customVocabulary defaults to empty.
    let stub = StubProvider(chunks: ["ok"])
    let polisher = DictationPolisher(
      provider: stub,
      settings: settings,
      timeoutSeconds: 2
    )
    _ = try await polisher.polish("raw", basePrompt: "BASE PROMPT")
    XCTAssertEqual(stub.lastSystemPrompt, "BASE PROMPT")
  }
}

// MARK: - Stub LLMProvider

/// Minimal `LLMProvider` for unit-tests. Records the arguments it
/// was called with (last call wins — tests issue one polish call
/// each) and replays a pre-configured chunk sequence or behavior.
///
/// `Sendable` conformance is required by the protocol. Recording uses
/// a small lock so the protocol's `nonisolated` `streamChat` can write
/// without crashing Swift 6 strict-concurrency.
final class StubProvider: LLMProvider, @unchecked Sendable {
  enum Behavior {
    /// Emit each string as a `.text` chunk then `.done`.
    case emitChunks([String])
    /// Never emit anything, never complete (forces caller timeout).
    case blockForever
    /// Throw a synthetic URLError before yielding anything.
    case throwImmediately
  }

  private let behavior: Behavior
  private let lock = NSLock()
  private var _lastMessages: [LLMMessage]?
  private var _lastSystemPrompt: String?
  private var _lastModel: String?

  var lastMessages: [LLMMessage]? {
    lock.lock(); defer { lock.unlock() }
    return _lastMessages
  }
  var lastSystemPrompt: String? {
    lock.lock(); defer { lock.unlock() }
    return _lastSystemPrompt
  }
  var lastModel: String? {
    lock.lock(); defer { lock.unlock() }
    return _lastModel
  }

  init(chunks: [String]) {
    self.behavior = .emitChunks(chunks)
  }

  init(behavior: Behavior) {
    self.behavior = behavior
  }

  func streamChat(
    messages: [LLMMessage],
    tools: [LLMTool],
    model: String,
    systemPrompt: String?
  ) -> AsyncThrowingStream<LLMChunk, Error> {
    lock.lock()
    _lastMessages = messages
    _lastSystemPrompt = systemPrompt
    _lastModel = model
    lock.unlock()

    let behavior = self.behavior
    return AsyncThrowingStream { continuation in
      switch behavior {
      case .emitChunks(let chunks):
        for c in chunks {
          continuation.yield(.text(c))
        }
        continuation.yield(.done)
        continuation.finish()
      case .blockForever:
        // Don't finish. The task group's timeout race cancels us.
        // No-op: the continuation just dangles until cancellation.
        break
      case .throwImmediately:
        continuation.finish(
          throwing: URLError(.notConnectedToInternet)
        )
      }
    }
  }
}
