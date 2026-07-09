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

  /// Set when the on-disk store could not be opened (schema mismatch) and
  /// was archived before a fresh store was created. The app surfaces the
  /// path to the user. `nil` on a clean open.
  public private(set) var archivedBackupURL: URL?

  public init(container: ModelContainer) {
    self.container = container
  }

  /// Convenience constructor that opens the on-disk SwiftData store at the
  /// app's default location. Use this in production; tests pass an
  /// in-memory container instead.
  ///
  /// If opening fails (e.g. an incompatible schema after an app update that
  /// SwiftData can't lightweight-migrate), the existing store files are
  /// archived to a dated `.bak` and a fresh store is created, so the app
  /// still launches instead of dying with no menubar item (design.md's
  /// "SwiftData-Migrationsfehler" contract).
  public convenience init() throws {
    let schema = Schema([Conversation.self, Message.self])
    let config = ModelConfiguration(schema: schema)
    do {
      let container = try ModelContainer(for: schema, configurations: config)
      self.init(container: container)
    } catch {
      Self.log.error("store open failed, archiving and starting fresh: \(error.localizedDescription, privacy: .public)")
      let archived = Self.archiveStore(at: config.url)
      let container = try ModelContainer(for: schema, configurations: config)
      self.init(container: container)
      self.archivedBackupURL = archived
    }
  }

  /// Move the SwiftData store (plus its -wal/-shm sidecars) aside to a
  /// dated backup so a fresh store can be created in its place. Returns
  /// the archived main-store path, or `nil` if there was nothing to move.
  private static func archiveStore(at url: URL) -> URL? {
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else { return nil }
    let stamp = ISO8601DateFormatter().string(from: Date())
      .replacingOccurrences(of: ":", with: "-")
    let base = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    let backup = url.deletingLastPathComponent()
      .appendingPathComponent("\(base).backup-\(stamp).\(ext)")
    for suffix in ["", "-wal", "-shm"] {
      let src = URL(fileURLWithPath: url.path + suffix)
      guard fm.fileExists(atPath: src.path) else { continue }
      let dst = URL(fileURLWithPath: backup.path + suffix)
      try? fm.moveItem(at: src, to: dst)
    }
    return backup
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

  /// Append a message to a conversation and persist. Derives the
  /// conversation title from the first user message (design.md) so the
  /// history list shows something better than "Neue Konversation".
  public func append(_ message: Message, to conversation: Conversation) throws {
    conversation.append(message)
    if message.role == .user, conversation.title == "Neue Konversation" {
      let firstLine = message.content
        .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        .first.map(String.init) ?? message.content
      let derived = firstLine.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)
      if !derived.isEmpty { conversation.title = String(derived) }
    }
    try context.save()
  }

  /// Persist edits to already-inserted models (e.g. an assistant message
  /// whose content streamed in after `append`). Unlike `append(_:to:)`
  /// this never re-appends to the relationship array.
  public func save() throws {
    try context.save()
  }

  /// Bump `updatedAt` so `conversation` becomes the active one, then
  /// persist. Used by the panel's history menu to switch conversations.
  public func touch(_ conversation: Conversation) {
    conversation.updatedAt = Date()
    do { try context.save() }
    catch { Self.log.warning("touch failed: \(error.localizedDescription, privacy: .public)") }
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
