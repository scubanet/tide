import Foundation
import OSLog
import Core
import LLM

/// Polishes a raw dictation transcript through Claude before the
/// `DictationCoordinator` injects it into the frontmost app.
///
/// We reuse the existing `LLMProvider` (Anthropic in production) and
/// drain its streaming response into a single string. The provider
/// only exposes a streaming API today — there's no separate
/// "completion" call — so we collect every `.text` chunk and return
/// the concatenated result. From the user's point of view this is a
/// one-shot polish call; the streaming is invisible.
///
/// **Daily-use rule:** any failure (missing API key, network down,
/// 5xx, timeout, empty response) is surfaced as a thrown error. The
/// caller (`DictationCoordinator.stop()`) is expected to catch and
/// fall back to injecting the raw transcript + posting a "Polish
/// fehlgeschlagen" notification, so the user never loses their
/// dictation just because Claude was unreachable.
@MainActor
final class DictationPolisher {
  /// Reason a polish attempt was abandoned. The coordinator doesn't
  /// branch on the specific case (it always falls back to raw + a
  /// single generic notification) but the distinct cases make logs
  /// and unit-tests readable.
  enum PolishError: Error, Sendable {
    /// No API key in the keychain. We fail fast without ever calling
    /// the provider — the provider would error anyway and we'd just
    /// burn the 8-second timeout window.
    case missingAPIKey
    /// The provider didn't finish within `timeoutSeconds`.
    case timeout
    /// The provider returned a stream with zero text content (after
    /// trimming). Treat as a failure so the caller falls back to raw.
    case empty
    /// The provider threw mid-stream (network, 5xx, decode error).
    /// The wrapped string is the original error's `localizedDescription`
    /// — we don't re-throw the typed `LLMError` because the coordinator
    /// only needs to know "polish didn't work".
    case provider(String)
  }

  private let provider: any LLMProvider
  private let settings: AppSettings
  /// How long to wait for the polish call before giving up. Injectable
  /// so unit-tests can use a sub-second cap instead of waiting the
  /// full 8 seconds for the timeout branch.
  private let timeoutSeconds: TimeInterval

  private static let logger = Logger(
    subsystem: "swiss.weckherlin.tide",
    category: "dictation-polish"
  )

  init(
    provider: any LLMProvider,
    settings: AppSettings,
    timeoutSeconds: TimeInterval = 8
  ) {
    self.provider = provider
    self.settings = settings
    self.timeoutSeconds = timeoutSeconds
  }

  /// Polish `raw` through the configured LLM provider. Throws on every
  /// failure mode — caller decides whether to fall back to the raw
  /// transcript (in production: yes, always).
  func polish(_ raw: String) async throws -> String {
    // Lazy guard: if the user removed their API key we'd otherwise
    // wait the full timeout window for the provider to ECONNREFUSED.
    // Short-circuit so the fallback notification fires immediately.
    guard let key = KeychainHelper.get(key: "anthropic.api_key"),
          !key.isEmpty
    else {
      throw PolishError.missingAPIKey
    }

    let systemPrompt = Self.systemPrompt(
      base: settings.dictationPolishPrompt,
      vocabulary: settings.customVocabulary
    )
    let userMessage = LLMMessage(role: .user, content: raw)
    let model = settings.selectedModel
    // Capture the timeout into a `Sendable` local so the timeout-task
    // closure doesn't have to reach back into `self`.
    let timeoutSec = self.timeoutSeconds

    let polishedResult = try await withThrowingTaskGroup(of: String.self) { group in
      // Task 1: drain the streaming response into one string. Each
      // `.text` chunk is a delta; we ignore `.toolUse` (the polish
      // prompt registers no tools) and treat `.done` as end-of-stream.
      group.addTask { [provider] in
        var accumulated = ""
        let stream = provider.streamChat(
          messages: [userMessage],
          tools: [],
          model: model,
          systemPrompt: systemPrompt
        )
        do {
          for try await chunk in stream {
            if case let .text(t) = chunk {
              accumulated += t
            }
          }
        } catch {
          // Re-wrap as our typed error so the coordinator's catch
          // doesn't have to know about LLMError. The raw localized
          // description is good enough for the log line.
          throw PolishError.provider(error.localizedDescription)
        }
        return accumulated
      }
      // Task 2: deadline. Whichever task finishes first wins. If the
      // sleep wins we throw `.timeout` and `group.next()` re-throws
      // it; the streaming task gets cancelled by `cancelAll()`.
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeoutSec * 1_000_000_000))
        throw PolishError.timeout
      }
      // Force-unwrap is safe — we just added two tasks.
      let first = try await group.next()!
      group.cancelAll()
      return first
    }

    let trimmed = polishedResult.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      throw PolishError.empty
    }
    Self.logger.debug(
      "polished \(raw.count, privacy: .public) → \(trimmed.count, privacy: .public) chars"
    )
    return trimmed
  }

  /// Build the polish system prompt. When the user has domain terms,
  /// append a single instruction line so Claude spells jargon correctly;
  /// an empty vocabulary returns `base` unchanged.
  static func systemPrompt(base: String, vocabulary: [String]) -> String {
    guard !vocabulary.isEmpty else { return base }
    let terms = vocabulary.joined(separator: ", ")
    return base
      + "\n\nDomain terms that may appear in the text — spell them exactly "
      + "as written, correcting any phonetic mis-transcription: \(terms)"
  }
}
