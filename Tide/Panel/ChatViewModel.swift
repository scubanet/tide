import Foundation
import Observation
import OSLog
import Core
import LLM
import TideSpeech
import Selection

@Observable
@MainActor
final class ChatViewModel {
  let conversationStore: ConversationStore
  private let provider: any LLMProvider
  private let settings: AppSettings

  private static let log = Logger(subsystem: "swiss.weckherlin.tide", category: "chat")

  var messages: [Message] = []
  var input: String = ""
  var isStreaming = false

  var isRecording = false
  var liveTranscript = ""

  /// Selection captured from another app, waiting to be included in the
  /// next outgoing user message. Cleared after send() or startNew().
  var pendingSelection: SelectedText? = nil

  /// Slug of the armed QuickAction. When non-nil, its systemPrompt replaces
  /// the default for the next outgoing message. Reset after send() and on
  /// startNew() — single-shot semantics.
  var selectedActionSlug: String? = nil

  private let quickActionLibrary = QuickActionLibrary()

  /// Quick actions available to the panel UI. Cached — `all()` decodes
  /// the custom-actions JSON from UserDefaults, which must not happen on
  /// every `ChatContainer.body` evaluation (i.e. every keystroke).
  /// Reloaded via `QuickActionLibrary.didChange` when the editor mutates.
  private(set) var availableActions: [QuickAction] = []
  /// Written once in init, read in deinit — by then no other reference
  /// can touch it concurrently. `@ObservationIgnored` keeps the
  /// `@Observable` macro from rewriting it (observers aren't UI state).
  @ObservationIgnored
  private nonisolated(unsafe) var quickActionsObserver: (any NSObjectProtocol)?

  /// Whether the Send button should be enabled. The user can send when
  /// any of these is true:
  ///   • they've typed something
  ///   • a selection context is attached (the user just wants Tide to
  ///     act on the selection, no extra text needed)
  /// AND we're not already streaming or recording.
  var canSend: Bool {
    let hasContent = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || pendingSelection != nil
    return hasContent && !isStreaming && !isRecording
  }

  private var recorder: AudioRecorder?
  private var partialTask: Task<Void, Never>?
  private let speech: SpeechPlayback

  /// Handle to the in-flight streaming Task so it can be cancelled
  /// (Stop button / ⌘.). Cancelling it tears down the SSE URLSession
  /// task via the stream's onTermination — the partial answer stays.
  private var streamTask: Task<Void, Never>?

  /// Last stream/API error, surfaced as an inline banner in the panel.
  /// `nil` when there is nothing to show.
  var lastError: ChatError? = nil

  /// Transient hint after a rejected or failed push-to-talk recording
  /// (e.g. "Nichts verstanden · nochmal versuchen"). Auto-clears.
  var sttHint: String? = nil
  private var sttHintTask: Task<Void, Never>?

  /// User-facing chat error. Decouples the UI banner from `LLMError`
  /// so the panel can offer the right affordance (retry vs. key-check).
  enum ChatError: Equatable {
    case rateLimited
    case unauthorized
    case network(String)
    case server(String)

    var message: String {
      switch self {
      case .rateLimited:      "Rate-Limit erreicht — bitte kurz warten."
      case .unauthorized:     "API-Key ungültig oder abgelaufen."
      case .network:          "Verbindung weg."
      case .server(let m):    m.isEmpty ? "Server-Fehler." : m
      }
    }

    /// Whether a "Wiederholen" button makes sense. Auth errors need the
    /// key fixed first, so they get a "API-Key prüfen" action instead.
    var isRetryable: Bool {
      if case .unauthorized = self { return false }
      return true
    }
  }

  init(conversationStore: ConversationStore, provider: any LLMProvider, settings: AppSettings) {
    self.conversationStore = conversationStore
    self.provider = provider
    self.settings = settings
    self.speech = SpeechPlayback(settings: settings)

    availableActions = quickActionLibrary.all()
    quickActionsObserver = NotificationCenter.default.addObserver(
      forName: QuickActionLibrary.didChange, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.availableActions = self.quickActionLibrary.all()
      }
    }

    loadActiveConversation()
  }

  deinit {
    if let quickActionsObserver {
      NotificationCenter.default.removeObserver(quickActionsObserver)
    }
  }

  private func loadActiveConversation() {
    if let conv = conversationStore.activeConversation() {
      messages = conv.messages.sorted { $0.createdAt < $1.createdAt }
    }
  }

  /// Fire-and-forget send that stores the streaming Task so the response
  /// can be cancelled (Stop button / ⌘.). UI entry point for Return, the
  /// send button, and push-to-talk auto-send.
  func beginSend() {
    streamTask?.cancel()
    streamTask = Task { [weak self] in await self?.send() }
  }

  /// Cancel the in-flight response and any queued TTS. The partial answer
  /// that already streamed stays in the chat.
  func cancelStreaming() {
    streamTask?.cancel()
    speech.stop()
  }

  /// Re-run the last failed response in place (banner "Wiederholen").
  func beginRetry() {
    streamTask?.cancel()
    streamTask = Task { [weak self] in await self?.retryLast() }
  }

  func retryLast() async {
    guard !isStreaming, let error = lastError, error.isRetryable else { return }
    guard let assistantMsg = messages.last, assistantMsg.role == .assistant,
          let conv = conversationStore.activeConversation() else { return }
    lastError = nil
    isStreaming = true
    defer { isStreaming = false }
    await runStream(conv: conv, assistantMsg: assistantMsg)
  }

  func send() async {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    // Allow send when there's text OR a pending selection (the user just
    // wants Tide to act on the selection without typing anything).
    guard (!trimmed.isEmpty || pendingSelection != nil), !isStreaming else { return }
    input = ""
    lastError = nil
    clearSTTHint()

    let conv: Conversation
    if let active = conversationStore.activeConversation() {
      conv = active
    } else {
      do {
        conv = try conversationStore.startNew()
      } catch {
        return
      }
    }

    // Compose the actual prompt. If we have a selection, include it.
    let promptText: String
    if let sel = pendingSelection {
      promptText = """
      Selektierter Text aus \(sel.sourceAppName):
      \"\"\"
      \(sel.text)
      \"\"\"

      \(trimmed)
      """
    } else {
      promptText = trimmed
    }

    let userMsg = Message(role: .user, content: promptText)
    // Persist selection-context JSON on the message for UI redisplay.
    if let sel = pendingSelection,
       let data = try? JSONEncoder().encode(sel),
       let json = String(data: data, encoding: .utf8) {
      userMsg.selectionContextJSON = json
    }
    // Clear pendingSelection after composing — single-shot semantic.
    pendingSelection = nil

    do { try conversationStore.append(userMsg, to: conv) }
    catch { Self.log.warning("append user message failed: \(error.localizedDescription, privacy: .public)") }
    messages.append(userMsg)

    let assistantMsg = Message(role: .assistant, content: "")
    do { try conversationStore.append(assistantMsg, to: conv) }
    catch { Self.log.warning("append assistant message failed: \(error.localizedDescription, privacy: .public)") }
    messages.append(assistantMsg)

    isStreaming = true
    defer { isStreaming = false }

    await runStream(conv: conv, assistantMsg: assistantMsg)

    // Single-shot: clear the armed action so the next message uses the default.
    selectedActionSlug = nil
  }

  /// Stream the assistant reply into `assistantMsg`. Auto-retries HTTP 429
  /// with exponential backoff (max 3 attempts, per docs/design.md); other
  /// failures surface via `lastError`. Cancellation keeps the partial answer.
  private func runStream(conv: Conversation, assistantMsg: Message) async {
    let maxAttempts = 3
    var attempt = 0
    while true {
      attempt += 1
      assistantMsg.content = ""
      speech.discardPending()
      do {
        let llmMessages = messages.dropLast().map { msg in
          LLMMessage(
            role: msg.role == .user ? .user : .assistant,
            content: msg.content
          )
        }
        let stream = provider.streamChat(
          messages: Array(llmMessages),
          tools: [],
          model: settings.selectedModel,
          systemPrompt: effectiveSystemPrompt()
        )
        for try await chunk in stream {
          if case let .text(t) = chunk {
            assistantMsg.content += t
            speech.ingest(t)
          }
        }
        speech.flush()
        // The placeholder was appended before streaming — only persist
        // the streamed content here, never re-append.
        do { try conversationStore.save() }
        catch { Self.log.warning("persist assistant message failed: \(error.localizedDescription, privacy: .public)") }
        lastError = nil
        return
      } catch {
        // Cancellation (Stop button): keep the partial answer, persist, quit.
        if Task.isCancelled {
          speech.discardPending()
          try? conversationStore.save()
          return
        }
        // 429 → exponential backoff auto-retry (seeded by retry-after).
        if let llm = error as? LLMError,
           case let .rateLimit(retryAfter) = llm, attempt < maxAttempts {
          let backoff = Double(retryAfter) * pow(2, Double(attempt - 1))
          try? await Task.sleep(nanoseconds: UInt64(min(backoff, 60) * 1_000_000_000))
          continue
        }
        handleStreamError(error)
        return
      }
    }
  }

  private func handleStreamError(_ error: Error) {
    speech.discardPending()
    // Persist whatever partial text streamed before the failure.
    try? conversationStore.save()
    if let llm = error as? LLMError {
      switch llm {
      case .unauthorized:          lastError = .unauthorized
      case .rateLimit:             lastError = .rateLimited
      case .network(let m):        lastError = .network(m)
      case .serverError(_, let m): lastError = .server(m)
      case .decoding(let m):       lastError = .server(m)
      }
    } else {
      lastError = .network(error.localizedDescription)
    }
  }

  func startNew() {
    cancelStreaming()
    do { _ = try conversationStore.startNew() }
    catch { Self.log.warning("startNew failed: \(error.localizedDescription, privacy: .public)") }
    messages = []
    pendingSelection = nil
    selectedActionSlug = nil
    lastError = nil
    clearSTTHint()
  }

  // MARK: Conversation history

  /// Recent conversations, newest first, for the panel's history menu.
  func recentConversations(limit: Int = 20) -> [Conversation] {
    (try? conversationStore.recent(limit: limit)) ?? []
  }

  /// Switch the panel to an existing conversation. Bumping `updatedAt`
  /// makes it the active one so subsequent sends append to it.
  func switchTo(_ conversation: Conversation) {
    cancelStreaming()
    conversationStore.touch(conversation)
    messages = conversation.orderedMessages
    pendingSelection = nil
    selectedActionSlug = nil
    lastError = nil
    clearSTTHint()
  }

  /// Delete a conversation. If it was the one on screen, fall back to the
  /// next active conversation (or an empty panel).
  func delete(_ conversation: Conversation) {
    let wasOnScreen = messages.first?.conversation === conversation
    do { try conversationStore.delete(conversation) }
    catch { Self.log.warning("delete conversation failed: \(error.localizedDescription, privacy: .public)") }
    if wasOnScreen {
      messages = conversationStore.activeConversation()?.orderedMessages ?? []
    }
  }

  private func setSTTHint(_ text: String) {
    sttHint = text
    sttHintTask?.cancel()
    sttHintTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      guard !Task.isCancelled else { return }
      self?.sttHint = nil
    }
  }

  private func clearSTTHint() {
    sttHintTask?.cancel()
    sttHint = nil
  }

  /// Stop any in-flight or queued TTS playback. Safe to call when
  /// nothing is speaking — a no-op in that case. Also clears the
  /// sentence-buffer so a still-streaming LLM response doesn't
  /// immediately resume speech with the leftover tokens; the remaining
  /// text still lands in the chat as usual (we only mute the audio,
  /// never the visible message).
  func stopSpeaking() {
    speech.stop()
  }

  func startRecording() async {
    guard !isRecording else { return }
    speech.stop()
    clearSTTHint()
    // Recognizer + recorder are built per-session from current settings
    // via the shared factory (same code path as DictationCoordinator).
    let recorder = RecordingSession.makeRecorder(settings: settings)
    self.recorder = recorder
    liveTranscript = ""
    isRecording = true

    // Subscribe to partial transcripts so the UI can show the live text.
    // Bind the stream before the Task so the Task iterates `stream` rather
    // than strongly capturing `recorder`. The class is @MainActor, so the
    // `for await` body resumes on the main actor — no MainActor.run hop.
    let stream = recorder.partialTranscript
    partialTask = Task { [weak self] in
      for await partial in stream {
        self?.liveTranscript = partial
      }
    }

    do {
      try await recorder.start()
      // A stopRecording() can interleave during the await above (fast
      // push-to-talk tap) and nil out self.recorder while start() is
      // suspended. If we've been superseded, tear down this now-orphaned
      // engine instead of leaving the mic hot. Mirrors DictationCoordinator.
      guard self.recorder === recorder else {
        _ = try? await recorder.stop()
        return
      }
    } catch {
      isRecording = false
      partialTask?.cancel()
      self.recorder = nil
      liveTranscript = ""
    }
  }

  func stopRecording() async {
    guard isRecording, let recorder else { return }
    // Don't flip isRecording yet — keep the live-transcript pill on
    // screen until we have the final text. Otherwise SwiftUI swaps to
    // the (still-empty) TextField in the gap between recorder.stop()
    // starting and the trimmed text getting written, and in
    // dictation-mode that empty TextField is what the user is stuck
    // staring at.
    do {
      let finalText = try await recorder.stop()
      let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
      let duration = recorder.bufferAccumulator.duration
      if TranscriptionQuality.isReject(trimmed, duration: duration) {
        // Too short / likely a hallucination — drop it (no send, no
        // wasted Claude call) but tell the user something was heard-and-
        // rejected, matching the design's STT-failed feedback.
        isRecording = false
        setSTTHint("Nichts verstanden · nochmal versuchen")
      } else {
        input = trimmed
        isRecording = false
        // Dictation mode: when the user has disabled auto-send the
        // transcription just lands in the input field — they can edit
        // and submit manually. Default (true) preserves the original
        // push-to-talk-and-send behavior. beginSend() (not await send())
        // so the resulting stream is cancellable via the Stop button.
        if settings.autoSendAfterPushToTalk {
          beginSend()
        }
      }
    } catch {
      // Recorder failed — drop the recording-state so the UI can
      // recover, and surface a hint instead of a silent empty field.
      isRecording = false
      setSTTHint("Aufnahme fehlgeschlagen")
    }
    self.recorder = nil
    partialTask?.cancel()
    liveTranscript = ""
  }

  private let defaultSystemPrompt = """
  Du bist ein präziser Assistent für einen deutschsprachigen Nutzer.
  Antworte direkt und ohne Floskeln.
  """

  private func effectiveSystemPrompt() -> String {
    if let slug = selectedActionSlug,
       let action = availableActions.first(where: { $0.slug == slug }) {
      return action.systemPrompt
    }
    return defaultSystemPrompt
  }
}
