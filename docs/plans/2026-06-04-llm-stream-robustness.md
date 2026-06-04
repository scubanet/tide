# LLM Stream Robustness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `AnthropicProvider` from swallowing stream errors — throw mid-stream `event: error` events, read the non-2xx error body, surface real messages via `LLMError: LocalizedError`, and guard the messages-array roles.

**Architecture:** All changes are in the `LLM` package: `LLMError` gains `LocalizedError`; `AnthropicProvider.streamChat` throws on `event: error` and drains the non-2xx body for its message; `AnthropicRequestBuilder` filters the messages array to user/assistant. Pure logic, fully unit-tested via the existing `MockURLProtocol`.

**Tech Stack:** Swift 6, XCTest, `URLSession.bytes` SSE streaming. Tests: `cd Packages/LLM && swift test`.

**Branch:** Vor Task 1: `git checkout -b feat/llm-stream-robustness`

---

## Task 1: `LLMError: LocalizedError`

**Files:**
- Modify: `Packages/LLM/Sources/LLM/Protocols/LLMError.swift`
- Test: `Packages/LLM/Tests/LLMTests/LLMTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Packages/LLM/Tests/LLMTests/LLMTests.swift` (inside a test class — if none exists there, add one):

```swift
  func test_llmError_errorDescription_nonEmptyForEveryCase() {
    let cases: [LLMError] = [
      .network("x"),
      .unauthorized,
      .rateLimit(retryAfterSeconds: 5),
      .serverError(code: 500, message: "boom"),
      .serverError(code: 0, message: "overloaded_error: Overloaded"),
      .decoding("y"),
    ]
    for e in cases {
      XCTAssertFalse((e.errorDescription ?? "").isEmpty, "\(e) has empty errorDescription")
    }
    // The real message must surface.
    XCTAssertTrue(LLMError.serverError(code: 500, message: "boom").errorDescription!.contains("boom"))
  }
```

(Ensure the file has `import XCTest` + `@testable import LLM` and a `final class … XCTestCase`.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd Packages/LLM && swift test --filter test_llmError_errorDescription 2>&1 | tail -12`
Expected: FAIL — `value of type 'LLMError' has no member 'errorDescription'`.

- [ ] **Step 3: Implement**

Append to `Packages/LLM/Sources/LLM/Protocols/LLMError.swift`:

```swift
extension LLMError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .network(let m):
      "Netzwerkfehler: \(m)"
    case .unauthorized:
      "API-Key ungültig oder abgelaufen (401)."
    case .rateLimit(let s):
      "Rate-Limit erreicht — in \(s)s erneut versuchen (429)."
    case .serverError(let code, let m):
      code > 0 ? "Server-Fehler \(code): \(m)" : "Stream-Fehler: \(m)"
    case .decoding(let m):
      "Antwort nicht lesbar: \(m)"
    }
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Packages/LLM && swift test --filter test_llmError_errorDescription 2>&1 | tail -6`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/LLM/Sources/LLM/Protocols/LLMError.swift Packages/LLM/Tests/LLMTests/LLMTests.swift
git commit -m "feat(llm): LLMError: LocalizedError surfaces real messages

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `AnthropicProvider` — throw mid-stream error + read non-2xx body

**Files:**
- Modify: `Packages/LLM/Sources/LLM/Anthropic/AnthropicProvider.swift`
- Test: `Packages/LLM/Tests/LLMTests/AnthropicProviderTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `AnthropicProviderTests.swift` (uses the existing `makeSession()` + `MockURLProtocol`):

```swift
  func test_midStreamErrorEvent_throwsServerError() async {
    let sseBody = """
    event: content_block_delta
    data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}

    event: error
    data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}

    """
    MockURLProtocol.handler = { request in
      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (response, sseBody.data(using: .utf8)!)
    }
    let provider = AnthropicProvider(apiKey: "sk-test", session: makeSession())
    let stream = provider.streamChat(
      messages: [LLMMessage(role: .user, content: "Hi")],
      tools: [], model: "m", systemPrompt: nil
    )
    do {
      for try await _ in stream {}
      XCTFail("Expected throw on mid-stream error")
    } catch let LLMError.serverError(code, message) {
      XCTAssertEqual(code, 0)
      XCTAssertTrue(message.contains("Overloaded") || message.contains("overloaded_error"),
        "message was: \(message)")
    } catch {
      XCTFail("Expected LLMError.serverError, got \(error)")
    }
  }

  func test_non2xx_includesErrorBodyMessage() async {
    MockURLProtocol.handler = { request in
      let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
      return (response, #"{"error":{"type":"api_error","message":"boom"}}"#.data(using: .utf8)!)
    }
    let provider = AnthropicProvider(apiKey: "sk-test", session: makeSession())
    let stream = provider.streamChat(
      messages: [LLMMessage(role: .user, content: "Hi")],
      tools: [], model: "m", systemPrompt: nil
    )
    do {
      for try await _ in stream {}
      XCTFail("Expected throw on 500")
    } catch let LLMError.serverError(code, message) {
      XCTAssertEqual(code, 500)
      XCTAssertTrue(message.contains("boom"), "message was: \(message)")
    } catch {
      XCTFail("Expected LLMError.serverError, got \(error)")
    }
  }
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd Packages/LLM && swift test --filter AnthropicProviderTests 2>&1 | tail -15`
Expected: FAIL — mid-stream error test sees a clean finish (no throw); 500 test sees empty message.

- [ ] **Step 3: Implement**

In `AnthropicProvider.swift`:

(a) Replace the status-code switch so non-2xx drains the body for its message:

```swift
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
```

(b) In BOTH event-processing spots (the main `for try await byte` loop and the end-of-stream flush), replace the `for event in events { if let chunk = decodeChunk(event: event) { continuation.yield(chunk) } }` body with a version that throws on `error` events. To avoid duplication, add a helper and call it. Add this private method:

```swift
  /// Process one parsed SSE event: throw on an Anthropic `error` event,
  /// otherwise yield the decoded chunk (if any).
  private func handle(_ event: SSEEvent, into continuation: AsyncThrowingStream<LLMChunk, Error>.Continuation) throws {
    if event.event == "error" {
      let msg = Self.errorMessage(fromEventData: event.data) ?? "stream error"
      throw LLMError.serverError(code: 0, message: msg)
    }
    if let chunk = decodeChunk(event: event) {
      continuation.yield(chunk)
    }
  }
```

Replace the two inner loops:
```swift
              for event in events {
                if let chunk = decodeChunk(event: event) {
                  continuation.yield(chunk)
                }
              }
```
and (in the flush):
```swift
            for event in events {
              if let chunk = decodeChunk(event: event) {
                continuation.yield(chunk)
              }
            }
```
both with:
```swift
              for event in events {
                try handle(event, into: continuation)
              }
```
(the `try` propagates to the enclosing `do/catch` → `continuation.finish(throwing:)`).

(c) Add the two parsing helpers (static, near `decodeChunk`):

```swift
  /// Collect the full response body from a streaming `AsyncBytes`.
  private static func drainBody(_ bytes: URLSession.AsyncBytes) async -> Data {
    var data = Data()
    if let collected = try? await { () async throws -> Data in
      var d = Data()
      for try await b in bytes { d.append(b) }
      return d
    }() {
      data = collected
    }
    return data
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
```

- [ ] **Step 4: Run to verify they pass**

Run: `cd Packages/LLM && swift test --filter AnthropicProviderTests 2>&1 | tail -8`
Expected: PASS — incl. the 2 new tests AND the pre-existing tests (text-chunks, 401, 429) still green.

- [ ] **Step 5: Commit**

```bash
git add Packages/LLM/Sources/LLM/Anthropic/AnthropicProvider.swift Packages/LLM/Tests/LLMTests/AnthropicProviderTests.swift
git commit -m "fix(llm): throw mid-stream error events + read non-2xx error body

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `AnthropicRequestBuilder` — role guard

**Files:**
- Modify: `Packages/LLM/Sources/LLM/Anthropic/AnthropicRequest.swift`
- Test: `Packages/LLM/Tests/LLMTests/AnthropicProviderTests.swift` (or a new `AnthropicRequestTests.swift`)

- [ ] **Step 1: Write the failing test**

Create `Packages/LLM/Tests/LLMTests/AnthropicRequestTests.swift`:

```swift
import XCTest
@testable import LLM

final class AnthropicRequestTests: XCTestCase {
  func test_messagesArray_onlyUserAndAssistant() throws {
    let req = try AnthropicRequestBuilder.makeRequest(
      apiKey: "k",
      messages: [
        LLMMessage(role: .system, content: "SYS"),
        LLMMessage(role: .user, content: "U"),
        LLMMessage(role: .assistant, content: "A"),
        LLMMessage(role: .tool, content: "T"),
      ],
      tools: [], model: "m", systemPrompt: nil
    )
    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    let messages = body["messages"] as! [[String: Any]]
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(messages.map { $0["role"] as! String }, ["user", "assistant"])
    XCTAssertEqual(messages.map { $0["content"] as! String }, ["U", "A"])
  }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Packages/LLM && swift test --filter AnthropicRequestTests 2>&1 | tail -12`
Expected: FAIL — `messages.count` is 4 (all roles forwarded).

- [ ] **Step 3: Implement**

In `AnthropicRequest.swift`, change the `messages` mapping to filter:

```swift
      "messages": messages
        .filter { $0.role == .user || $0.role == .assistant }
        .map { ["role": $0.role.rawValue, "content": $0.content] },
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Packages/LLM && swift test --filter AnthropicRequestTests 2>&1 | tail -6`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/LLM/Sources/LLM/Anthropic/AnthropicRequest.swift Packages/LLM/Tests/LLMTests/AnthropicRequestTests.swift
git commit -m "fix(llm): only send user/assistant roles in the messages array

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: CHANGELOG

**Files:** `CHANGELOG.md`

- [ ] **Step 1:** Under `## [Unreleased]` → `### Fixed`, add:

```markdown
- **LLM-Stream-Robustheit** — Anthropic-Fehler werden nicht mehr verschluckt:
  ein Mid-Stream-`error`-Event (z.B. Überlast) bricht den Stream mit Fehler ab
  statt still abzuschneiden, HTTP-Fehler zeigen die echte Server-Meldung, und
  der Chat-Fehler-Text ist dank `LLMError: LocalizedError` aussagekräftig. Plus
  ein defensiver Role-Guard (nur user/assistant im `messages`-Array).
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for LLM stream robustness

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** LocalizedError (T1), mid-stream error + non-2xx body (T2), role guard (T3), changelog (T4). All covered.
- **Type consistency:** `LLMError.serverError(code:message:)` reused (code 0 = stream error); helpers `drainBody`/`errorMessage(fromBody:)`/`errorMessage(fromEventData:)`/`handle(_:into:)`.
- **No regression:** the existing 401/429/text-chunk tests stay green (401/429 paths unchanged except the default arm now drains the body).
- **`drainBody`** reads the `AsyncBytes` only on the error path (after the status check, before any chunk processing) — the success path never calls it.
- **Tests are pure** (MockURLProtocol), no network. `cd Packages/LLM && swift test` covers everything.
