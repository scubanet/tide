import Foundation

/// Common error shape across providers. Concrete impls (e.g.
/// `AnthropicProvider`) map their HTTP/parsing failures into these cases.
public enum LLMError: Error, Sendable, Equatable {
  /// Transport-level failure (DNS, TCP, TLS, connection drop).
  case network(String)
  /// HTTP 401 — API key invalid or expired.
  case unauthorized
  /// HTTP 429 — rate-limited. `retryAfterSeconds` comes from the response
  /// header when present, falls back to 10.
  case rateLimit(retryAfterSeconds: Int)
  /// 4xx/5xx other than the above.
  case serverError(code: Int, message: String)
  /// Body could not be decoded as expected.
  case decoding(String)
}

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
