import Foundation
import SwiftData

public enum MessageRole: String, Codable, Sendable {
  case user
  case assistant
  case tool
}

@Model
public final class Message {
  @Attribute(.unique) public var id: UUID
  public var role: MessageRole
  public var content: String
  public var createdAt: Date
  public var conversation: Conversation?
  /// Serialized JSON snapshot of `SelectedText` if this message was sent with
  /// selection context from another app. Phase 6 populates this.
  public var selectionContextJSON: String?

  public init(
    id: UUID = UUID(),
    role: MessageRole,
    content: String,
    selectionContextJSON: String? = nil
  ) {
    self.id = id
    self.role = role
    self.content = content
    self.createdAt = Date()
    self.selectionContextJSON = selectionContextJSON
  }
}
