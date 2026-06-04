import Foundation
import OSLog
import SwiftData

/// Facade over the SwiftData `ModelContainer` that hides persistence
/// plumbing from the rest of the app. `MainActor`-isolated because all
/// SwiftData `ModelContext` work happens on the main actor by default.
@MainActor
public final class ConversationStore {
  private let container: ModelContainer
  private var context: ModelContext { container.mainContext }

  private static let log = Logger(subsystem: "swiss.weckherlin.tide", category: "store")

  public init(container: ModelContainer) {
    self.container = container
  }

  /// Convenience constructor that opens the on-disk SwiftData store at the
  /// app's default location. Use this in production; tests pass an
  /// in-memory container instead.
  public convenience init() throws {
    let container = try ModelContainer(
      for: Conversation.self, Message.self
    )
    self.init(container: container)
  }

  /// The most recently updated conversation, or `nil` if none exist.
  /// Implements the "letzte Konversation läuft weiter" semantics — the
  /// menubar panel calls this on open.
  public func activeConversation() -> Conversation? {
    var descriptor = FetchDescriptor<Conversation>(
      sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
    )
    descriptor.fetchLimit = 1
    do {
      return try context.fetch(descriptor).first
    } catch {
      // A fetch error is NOT "no conversations" — log it so a transient
      // store failure that would orphan history is visible.
      Self.log.warning("activeConversation fetch failed: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  /// Start a brand-new conversation and return it. The new conversation
  /// becomes the active one because its `updatedAt` is now the newest.
  @discardableResult
  public func startNew(title: String = "Neue Konversation") throws -> Conversation {
    let conv = Conversation(title: title)
    context.insert(conv)
    try context.save()
    return conv
  }

  /// Append a message to a conversation and persist.
  public func append(_ message: Message, to conversation: Conversation) throws {
    conversation.append(message)
    try context.save()
  }

  /// Recent conversations newest first, capped at `limit`.
  public func recent(limit: Int = 50) throws -> [Conversation] {
    var descriptor = FetchDescriptor<Conversation>(
      sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
    )
    descriptor.fetchLimit = limit
    return try context.fetch(descriptor)
  }

  public func delete(_ conversation: Conversation) throws {
    context.delete(conversation)
    try context.save()
  }
}
