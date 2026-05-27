import Foundation

/// Streamed event types emitted by `LLMProvider.streamChat(...)`.
///
/// - `.text(String)` — a delta of the assistant message text. Concatenate.
/// - `.toolUse` — the assistant called a registered tool. v1 doesn't
///   register any, but the case exists so the streaming pipeline can be
///   reused unchanged when Mac-app integration ships (see design spec
///   "Phase 2 — Tool-Use für Mac-App-Integration").
/// - `.done` — the stream ended cleanly.
public enum LLMChunk: Sendable, Equatable {
  case text(String)
  case toolUse(id: String, name: String, inputJSON: String)
  case done
}
