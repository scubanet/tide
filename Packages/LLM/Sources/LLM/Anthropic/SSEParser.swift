import Foundation

/// One Server-Sent Event: an `event` name plus a `data` payload.
public struct SSEEvent: Equatable, Sendable {
  public let event: String
  public let data: String

  public init(event: String, data: String) {
    self.event = event
    self.data = data
  }
}

/// Tiny SSE parser. Splits a chunk of stream text on the blank-line
/// delimiter and extracts each event's `event:` and `data:` fields.
/// Multi-line `data:` fields (rare in Anthropic, but legal per spec) are
/// joined with `\n`. Blocks without an `event:` field are dropped — we
/// only care about typed events.
///
/// **Permissive by design.** The parser does NOT try to detect truncated
/// events at the boundary. If a block has an `event:` line and any
/// `data:` lines, it emits an SSEEvent — even if the `data` field
/// contains malformed JSON. That validation belongs at the decode step.
/// This keeps the parser usable both by the strict byte-streaming loop
/// (which only ever feeds `\n\n`-terminated blocks) and by tests that
/// use Swift multiline-string literals (which silently drop the trailing
/// `\n` of a blank line before `"""`).
public enum SSEParser {
  public static func parse(_ chunk: String) -> [SSEEvent] {
    var events: [SSEEvent] = []
    let blocks = chunk.components(separatedBy: "\n\n")
    for block in blocks where !block.isEmpty {
      var eventName = ""
      var data = ""
      for line in block.components(separatedBy: "\n") {
        if line.hasPrefix("event:") {
          eventName = String(line.dropFirst("event:".count))
            .trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
          let part = String(line.dropFirst("data:".count))
            .trimmingCharacters(in: .whitespaces)
          data = data.isEmpty ? part : data + "\n" + part
        }
      }
      if !eventName.isEmpty {
        events.append(SSEEvent(event: eventName, data: data))
      }
    }
    return events
  }
}
