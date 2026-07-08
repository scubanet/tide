import XCTest
import SwiftData
import LLM
import Core
import Selection
@testable import Tide

/// Unit tests for `ChatViewModel` — the panel's core orchestration, which
/// had no coverage. Uses an in-memory `ConversationStore` and a sequencing
/// stub provider so send/retry/error paths run without real audio or network.
@MainActor
final class ChatViewModelTests: XCTestCase {
  private var defaults: UserDefaults!
  private var settings: AppSettings!

  override func setUp() async throws {
    defaults = UserDefaults(suiteName: "tide.tests.ChatVM.\(UUID().uuidString)")
    settings = AppSettings(defaults: defaults)
    settings.voiceEnabled = false  // no TTS side effects in tests
  }

  private func makeStore() throws -> ConversationStore {
    let container = try ModelContainer(
      for: Conversation.self, Message.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ConversationStore(container: container)
  }

  private func makeVM(_ provider: any LLMProvider) throws -> ChatViewModel {
    ChatViewModel(conversationStore: try makeStore(), provider: provider, settings: settings)
  }

  // MARK: canSend

  func test_canSend_falseWhenEmpty_trueWithText() throws {
    let vm = try makeVM(SequenceProvider([.chunks(["x"])]))
    XCTAssertFalse(vm.canSend)
    vm.input = "  "
    XCTAssertFalse(vm.canSend, "whitespace-only is not sendable")
    vm.input = "hallo"
    XCTAssertTrue(vm.canSend)
  }

  func test_canSend_trueWithPendingSelectionOnly() throws {
    let vm = try makeVM(SequenceProvider([.chunks(["x"])]))
    vm.pendingSelection = SelectedText(text: "sel", sourceAppBundleID: "com.x", sourceAppName: "X")
    XCTAssertTrue(vm.canSend, "a selection alone is enough to send")
  }

  // MARK: happy path + system prompt

  func test_send_streamsAndPersistsAssistantReply() async throws {
    let vm = try makeVM(SequenceProvider([.chunks(["Hal", "lo"])]))
    vm.input = "Hi"
    await vm.send()
    XCTAssertEqual(vm.messages.count, 2)
    XCTAssertEqual(vm.messages.last?.content, "Hallo")
    XCTAssertNil(vm.lastError)
  }

  func test_send_usesDefaultSystemPrompt_whenNoActionArmed() async throws {
    let stub = SequenceProvider([.chunks(["ok"])])
    let vm = try makeVM(stub)
    vm.input = "Hi"
    await vm.send()
    XCTAssertEqual(stub.lastSystemPrompt?.contains("präziser Assistent"), true)
  }

  func test_send_usesArmedQuickActionPrompt_thenResetsSlug() async throws {
    let stub = SequenceProvider([.chunks(["ok"])])
    let vm = try makeVM(stub)
    let action = try XCTUnwrap(vm.availableActions.first)
    vm.selectedActionSlug = action.slug
    vm.input = "Hi"
    await vm.send()
    XCTAssertEqual(stub.lastSystemPrompt, action.systemPrompt)
    XCTAssertNil(vm.selectedActionSlug, "armed slug is single-shot")
  }

  // MARK: selection embedding

  func test_send_embedsSelectionContext() async throws {
    let stub = SequenceProvider([.chunks(["ok"])])
    let vm = try makeVM(stub)
    vm.pendingSelection = SelectedText(text: "MARKIERT", sourceAppBundleID: "com.x", sourceAppName: "Mail")
    vm.input = "fasse zusammen"
    await vm.send()
    let sentUser = try XCTUnwrap(stub.lastMessages?.last)
    XCTAssertTrue(sentUser.content.contains("MARKIERT"))
    XCTAssertTrue(sentUser.content.contains("Mail"))
    let userMsg = vm.messages[vm.messages.count - 2]
    XCTAssertNotNil(userMsg.selectionContextJSON, "selection JSON persisted on the message")
    XCTAssertNil(vm.pendingSelection, "selection cleared after send")
  }

  // MARK: error handling

  func test_send_setsLastError_onServerError() async throws {
    let vm = try makeVM(SequenceProvider([.error(LLMError.serverError(code: 500, message: "boom"))]))
    vm.input = "Hi"
    await vm.send()
    XCTAssertEqual(vm.lastError, .server("boom"))
  }

  func test_send_setsUnauthorized_onAuthError() async throws {
    let vm = try makeVM(SequenceProvider([.error(LLMError.unauthorized)]))
    vm.input = "Hi"
    await vm.send()
    XCTAssertEqual(vm.lastError, .unauthorized)
    XCTAssertFalse(vm.lastError!.isRetryable)
  }

  // MARK: 429 auto-retry

  func test_send_autoRetriesRateLimit_thenSucceeds() async throws {
    // retryAfterSeconds: 0 → zero backoff so the test doesn't sleep.
    let stub = SequenceProvider([
      .error(LLMError.rateLimit(retryAfterSeconds: 0)),
      .chunks(["nach Retry"]),
    ])
    let vm = try makeVM(stub)
    vm.input = "Hi"
    await vm.send()
    XCTAssertEqual(stub.callCount, 2, "rate-limit is retried")
    XCTAssertEqual(vm.messages.last?.content, "nach Retry")
    XCTAssertNil(vm.lastError)
  }

  func test_send_givesUpRateLimit_afterThreeAttempts() async throws {
    let stub = SequenceProvider([.error(LLMError.rateLimit(retryAfterSeconds: 0))])  // always 429
    let vm = try makeVM(stub)
    vm.input = "Hi"
    await vm.send()
    XCTAssertEqual(stub.callCount, 3, "max 3 attempts")
    XCTAssertEqual(vm.lastError, .rateLimited)
  }

  // MARK: retry

  func test_retryLast_reRunsAndClearsError() async throws {
    let stub = SequenceProvider([.error(LLMError.network("weg")), .chunks(["endlich"])])
    let vm = try makeVM(stub)
    vm.input = "Hi"
    await vm.send()
    XCTAssertEqual(vm.lastError, .network("weg"))
    await vm.retryLast()
    XCTAssertNil(vm.lastError)
    XCTAssertEqual(vm.messages.last?.content, "endlich")
  }
}

// MARK: - Sequencing stub provider

/// `LLMProvider` that plays one scripted step per `streamChat` call, so a
/// test can script "429 then success" or "fail then retry".
final class SequenceProvider: LLMProvider, @unchecked Sendable {
  enum Step {
    case chunks([String])
    case error(Error)
  }

  private let steps: [Step]
  private let lock = NSLock()
  private var index = 0
  private var _lastMessages: [LLMMessage]?
  private var _lastSystemPrompt: String?

  var callCount: Int { lock.withLock { index } }
  var lastMessages: [LLMMessage]? { lock.withLock { _lastMessages } }
  var lastSystemPrompt: String? { lock.withLock { _lastSystemPrompt } }

  init(_ steps: [Step]) { self.steps = steps }

  func streamChat(
    messages: [LLMMessage],
    tools: [LLMTool],
    model: String,
    systemPrompt: String?
  ) -> AsyncThrowingStream<LLMChunk, Error> {
    let step: Step = lock.withLock {
      _lastMessages = messages
      _lastSystemPrompt = systemPrompt
      let s = steps[min(index, steps.count - 1)]
      index += 1
      return s
    }
    return AsyncThrowingStream { continuation in
      switch step {
      case .chunks(let chunks):
        for c in chunks { continuation.yield(.text(c)) }
        continuation.yield(.done)
        continuation.finish()
      case .error(let error):
        continuation.finish(throwing: error)
      }
    }
  }
}
