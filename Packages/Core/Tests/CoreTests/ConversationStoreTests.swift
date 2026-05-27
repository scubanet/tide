import XCTest
import SwiftData
@testable import Core

final class ConversationStoreTests: XCTestCase {
  @MainActor
  private func makeStore() throws -> ConversationStore {
    let container = try ModelContainer(
      for: Conversation.self, Message.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ConversationStore(container: container)
  }

  @MainActor
  func testActiveReturnsNilOnEmpty() throws {
    let store = try makeStore()
    XCTAssertNil(store.activeConversation())
  }

  @MainActor
  func testStartNewCreatesEmptyConversation() throws {
    let store = try makeStore()
    let conv = try store.startNew()
    XCTAssertEqual(conv.messages.count, 0)
    XCTAssertNotNil(store.activeConversation()?.id)
    XCTAssertEqual(store.activeConversation()?.id, conv.id)
  }

  @MainActor
  func testAppendUpdatesActive() throws {
    let store = try makeStore()
    let conv = try store.startNew()
    try store.append(Message(role: .user, content: "Hi"), to: conv)
    XCTAssertEqual(store.activeConversation()?.messages.count, 1)
  }

  @MainActor
  func testRecentReturnsConversationsNewestFirst() throws {
    let store = try makeStore()
    let first = try store.startNew(title: "Älteste")
    Thread.sleep(forTimeInterval: 0.01)
    let second = try store.startNew(title: "Neueste")
    let recent = try store.recent()
    XCTAssertEqual(recent.first?.id, second.id)
    XCTAssertEqual(recent.last?.id, first.id)
  }

  @MainActor
  func testDeleteRemovesConversation() throws {
    let store = try makeStore()
    let conv = try store.startNew()
    try store.delete(conv)
    XCTAssertEqual(try store.recent().count, 0)
  }
}
