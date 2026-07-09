import Foundation

/// `LLMProvider` implementation against the Anthropic Messages API with
/// SSE streaming. Errors map onto `LLMError`. Tool-use chunks emit only
/// the `content_block_start` for the tool — v1 doesn't service tool
/// calls yet, but the event is surfaced so future code paths can.
public final class AnthropicProvider: LLMProvider {
  private let apiKeyProvider: @Sendable () -> String
  private let session: URLSession

  /// `apiKeyProvider` is consulted per request, so a key saved while the
  /// app is running (onboarding, Settings) takes effect on the next send
  /// — no relaunch needed.
  public init(apiKeyProvider: @escaping @Sendable () -> String, session: URLSession = .shared) {
    self.apiKeyProvider = apiKeyProvider
    self.session = session
  }

  /// Convenience for a fixed key (tests, CLI usage).
  public convenience init(apiKey: String, session: URLSession = .shared) {
    self.init(apiKeyProvider: { apiKey }, session: session)
  }

  public func streamChat(
    messages: [LLMMessage],
    tools: [LLMTool],
    model: String,
    systemPrompt: String?
  ) -> AsyncThrowingStream<LLMChunk, Error> {
    AsyncThrowingStream { continuation in
      let task = Task { [apiKeyProvider, session] in
        do {
          let request = try AnthropicRequestBuilder.makeRequest(
            apiKey: apiKeyProvider(), messages: messages, tools: tools,
            model: model, systemPrompt: systemPrompt
          )
          let (bytes, response) = try await session.bytes(for: request)
          guard let http = response as? HTTPURLResponse else {
            throw LLMError.network("non-HTTP response")
          }
          switch http.statusCode {
          case 200..<300: break
          case 401: throw LLMError.unauthorized
          case 429:
            let retry = Int(http.value(forHTTPHeaderField: "retry-after") ?? "10") ?? 10
            throw LLMError.rateLimit(retryAfterSeconds: retry)
          default:
            let body = await Self.drainBody(bytes)
            throw LLMError.serverError(
              code: http.statusCode,
              message: Self.errorMessage(fromBody: body) ?? ""
            )
          }

          // SSE-framing note: we cannot use `bytes.lines` here because
          // `URLSession.AsyncBytes.lines` silently drops empty lines (Swift
          // forum bug). Empty lines are exactly how SSE separates events,
          // so we read raw bytes and scan for the `\n\n` terminator ourselves.
          var buffer = Data()
          let newline: UInt8 = 0x0a
          for try await byte in bytes {
            buffer.append(byte)
            // An event can only complete on the byte that finishes a
            // "\n\n" pair, so checking the buffer tail is enough — no
            // full-buffer scan per byte (that was O(n²) per event block).
            guard byte == newline, buffer.count >= 2,
                  buffer[buffer.count - 2] == newline else { continue }
            let blockData = buffer.subdata(in: 0..<(buffer.count - 2))
            buffer.removeAll(keepingCapacity: true)
            guard let blockStr = String(data: blockData, encoding: .utf8) else { continue }
            let events = SSEParser.parse(blockStr)
            for event in events {
              try handle(event, into: continuation)
            }
          }
          // End-of-stream flush: if anything is left in `buffer`, treat it
          // as a final event. Anthropic doesn't always emit a trailing
          // `\n\n` after `message_stop`, and Swift multiline-string test
          // bodies drop the trailing blank line entirely.
          if !buffer.isEmpty, let tail = String(data: buffer, encoding: .utf8) {
            let events = SSEParser.parse(tail)
            for event in events {
              try handle(event, into: continuation)
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Process one parsed SSE event: throw on an Anthropic `error` event,
  /// otherwise yield the decoded chunk (if any).
  private func handle(_ event: SSEEvent, into continuation: AsyncThrowingStream<LLMChunk, Error>.Continuation) throws {
    if event.event == "error" {
      let msg = Self.errorMessage(fromEventData: event.data) ?? "stream error"
      // Anthropic signals transient overload/rate-limiting mid-stream as
      // an SSE error event, not an HTTP 429 — map it onto `.rateLimit`
      // so the caller's existing backoff/retry path applies.
      switch Self.errorType(fromEventData: event.data) {
      case "overloaded_error", "rate_limit_error":
        throw LLMError.rateLimit(retryAfterSeconds: 10)
      default:
        throw LLMError.serverError(code: 0, message: msg)
      }
    }
    if let chunk = decodeChunk(event: event) {
      continuation.yield(chunk)
    }
  }

  /// Collect the full response body from a streaming `AsyncBytes`.
  private static func drainBody(_ bytes: URLSession.AsyncBytes) async -> Data {
    do {
      var data = Data()
      for try await b in bytes { data.append(b) }
      return data
    } catch {
      return Data()
    }
  }

  /// Extract `error.message` (prefixed with `error.type` when present) from
  /// an Anthropic error JSON body.
  private static func errorMessage(fromBody data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let err = json["error"] as? [String: Any] else { return nil }
    let message = err["message"] as? String ?? ""
    let type = err["type"] as? String
    if let type, !type.isEmpty { return message.isEmpty ? type : "\(type): \(message)" }
    return message.isEmpty ? nil : message
  }

  /// Same shape, from an SSE event's `data:` string.
  private static func errorMessage(fromEventData data: String) -> String? {
    guard let d = data.data(using: .utf8) else { return nil }
    return errorMessage(fromBody: d)
  }

  /// `error.type` of an SSE error event, e.g. `"overloaded_error"`.
  private static func errorType(fromEventData data: String) -> String? {
    guard let d = data.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let err = json["error"] as? [String: Any] else { return nil }
    return err["type"] as? String
  }

  private func decodeChunk(event: SSEEvent) -> LLMChunk? {
    guard let data = event.data.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    switch event.event {
    case "content_block_delta":
      if let delta = json["delta"] as? [String: Any],
         let type = delta["type"] as? String,
         type == "text_delta",
         let text = delta["text"] as? String {
        return .text(text)
      }
    case "content_block_start":
      if let block = json["content_block"] as? [String: Any],
         let type = block["type"] as? String,
         type == "tool_use",
         let id = block["id"] as? String,
         let name = block["name"] as? String {
        // Tool input arrives via subsequent input_json_delta events.
        // v1: surface the start, leave input buffering to Phase-2-future.
        return .toolUse(id: id, name: name, inputJSON: "")
      }
    case "message_stop":
      return .done
    default:
      return nil
    }
    return nil
  }
}
