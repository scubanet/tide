import Foundation
import SwiftData

@Model
public final class Conversation {
  @Attribute(.unique) public var id: UUID
  public var title: String
  public var createdAt: Date
  public var updatedAt: Date
  @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
  public var messages: [Message]

  public init(id: UUID = UUID(), title: String = "Neue Konversation") {
    self.id = id
    self.title = title
    self.createdAt = Date()
    self.updatedAt = Date()
    self.messages = []
  }

  /// Append a message to this conversation and bump `updatedAt`. The
  /// caller is responsible for persisting via the owning `ModelContext`.
  public func append(_ message: Message) {
    message.conversation = self
    messages.append(message)
    updatedAt = Date()
  }

  /// Messages in chronological order. The `messages` array itself is
  /// stored Set-style by SwiftData under the hood — its ordering is
  /// undefined after a fetch round-trip. Always read through this
  /// computed property when you need a stable order.
  public var orderedMessages: [Message] {
    messages.sorted { $0.createdAt < $1.createdAt }
  }
}
