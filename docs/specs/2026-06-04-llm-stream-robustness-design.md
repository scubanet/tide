# Tide — LLM-Stream-Robustheit — Design-Spec

**Datum:** 04. Juni 2026
**Status:** Design abgesegnet (Dominik), bereit für Implementation-Plan
**Herkunft:** App-Audit (LLM-Subsystem). Behebt stille/abgeschnittene Streams
und unbrauchbare Fehlermeldungen im Chat.

---

## Problem

`AnthropicProvider.streamChat` schluckt Fehler:
1. **Mid-Stream-Error verschluckt.** Anthropic streamt bei Überlast/Fehler ein
   `event: error` (z.B. `overloaded_error`). `decodeChunk` hat keinen
   `case "error":` → `default: return nil` → die Schleife läuft weiter zu
   `continuation.finish()`. Der Aufrufer sieht einen **sauberen, abgeschnittenen
   Stream** ohne Fehler.
2. **non-2xx-Body verworfen.** Bei HTTP-Fehler wird `bytes` (der Body mit
   Anthropics JSON-Fehlererklärung) nie gelesen → `serverError(code:, message: "")`
   ist immer leer.
3. **`LLMError` ist kein `LocalizedError`** → `ChatViewModel`s
   `error.localizedDescription` zeigt generischen Enum-Text statt der echten
   Ursache. Der Chat-Bubble-Fehler `[Fehler: …]` ist nichtssagend.
4. **Role-Mapping ungeschützt.** `messages.map { ["role": role.rawValue …] }`
   reicht `.system`/`.tool` blind durch; Anthropics `messages`-Array akzeptiert
   nur `user`/`assistant` → HTTP 400. Heute sendet kein Aufrufer diese Rollen,
   aber das Enum erlaubt sie.

## Ziel

Stream-Fehler werden **geworfen** (nicht verschluckt), mit der **echten
Anthropic-Meldung**, die im Chat sichtbar wird. Defensive gegen das
Role-400.

Nicht-Ziel (eigene spätere Welle): SSE-Scan-O(n²)-Perf, `tool_use`
`input_json_delta`-Buffering (v1 hat keinen Tool-Service), Retry/Backoff.

## Komponenten & Fixes

### 1. `LLMError: LocalizedError`
Neue Extension (in `LLMError.swift`):
```swift
extension LLMError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .network(let m):              "Netzwerkfehler: \(m)"
    case .unauthorized:                "API-Key ungültig oder abgelaufen (401)."
    case .rateLimit(let s):            "Rate-Limit erreicht — in \(s)s erneut versuchen (429)."
    case .serverError(let code, let m):
      code > 0 ? "Server-Fehler \(code): \(m)" : "Stream-Fehler: \(m)"
    case .decoding(let m):             "Antwort nicht lesbar: \(m)"
    }
  }
}
```
Damit zeigt der Chat-Bubble-Fehler die echte Meldung.

### 2. Mid-Stream-`error`-Event
Im Byte-Streaming-Loop (und im End-of-Stream-Flush) wird jedes geparste Event
**vor** `decodeChunk` geprüft: ist `event.event == "error"`, wird das
`data`-JSON `{"error":{"type":..,"message":..}}` extrahiert und
`throw LLMError.serverError(code: 0, message: "<type>: <message>")` (code 0 =
Stream-Fehler ohne HTTP-Code) geworfen. Das bestehende `do/catch` leitet es an
`continuation.finish(throwing:)`. Ein neuer privater Helper
`errorMessage(from: SSEEvent) -> String?` kapselt das Parsen.

### 3. non-2xx-Body lesen
Bei non-2xx wird `bytes` in `Data` gedraint (`var d = Data(); for try await b in
bytes { d.append(b) }`), `{"error":{"message":..}}` decodiert, und die echte
Message an `.serverError(code:message:)` bzw. `.unauthorized`/`.rateLimit`
übergeben. Helper `drainBody(_ bytes:) async -> Data` + `errorMessage(from data:)`.
429 behält den `retry-after`-Header.

### 4. Role-Guard im RequestBuilder
`AnthropicRequestBuilder`: das `messages`-Array nur aus `.user`/`.assistant`
bauen (`.compactMap` mit `where role == .user || role == .assistant`).
`.system` gehört top-level (`systemPrompt`, schon so); `.tool` ist v1 nicht
unterstützt. Verhindert ein künftiges 400.

## Fehlerbehandlung / Datenfluss

- Mid-Stream-Error → `throw` → `finish(throwing:)` → `ChatViewModel.catch` hängt
  `[Fehler: <errorDescription>]` an die Assistant-Bubble (bestehender Pfad,
  jetzt mit echter Meldung).
- non-2xx → wie bisher `throw`, aber Message gefüllt.
- Cancellation (`onTermination` → `task.cancel()`) unverändert.

## Tests (LLMTests, `MockURLProtocol` vorhanden)

- **Mid-Stream-Error:** Mock streamt `event: message_start` … dann
  `event: error\ndata: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}` →
  der Stream wirft `LLMError.serverError(code: 0, message:)` mit „overloaded_error"/„Overloaded".
- **non-2xx-Body:** Mock antwortet 500 mit Body `{"error":{"message":"boom"}}` →
  `LLMError.serverError(code: 500, message:)` enthält „boom" (nicht leer).
- **`errorDescription`:** jede `LLMError`-Case → nicht-leerer, sinnvoller Text.
- **Role-Guard:** `AnthropicRequestBuilder.makeRequest` mit Messages
  `[.system, .user, .assistant, .tool]` → das serialisierte `messages`-Array
  enthält nur die 2 user/assistant-Einträge (Body-JSON inspizieren).

## Betroffene Dateien

| Datei | Fix |
|---|---|
| `Packages/LLM/Sources/LLM/Protocols/LLMError.swift` | `LocalizedError` (1) |
| `Packages/LLM/Sources/LLM/Anthropic/AnthropicProvider.swift` | Mid-Stream-Error (2) + non-2xx-Body (3) |
| `Packages/LLM/Sources/LLM/Anthropic/AnthropicRequest.swift` | Role-Guard (4) |
| `Packages/LLM/Tests/LLMTests/*.swift` | 4 Testgruppen |
| `CHANGELOG.md` | Eintrag |
