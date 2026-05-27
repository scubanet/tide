import XCTest
import SwiftData
@testable import Core

final class ConversationTests: XCTestCase {
  func testConversationStoresMessagesInOrder() throws {
    let container = try ModelContainer(
      for: Conversation.self, Message.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = ModelContext(container)
    let conv = Conversation(title: "Test")
    ctx.insert(conv)
    conv.append(Message(role: .user, content: "Hallo"))
    conv.append(Message(role: .assistant, content: "Hallo zurück!"))
    try ctx.save()

    XCTAssertEqual(conv.messages.count, 2)
    let ordered = conv.orderedMessages
    XCTAssertEqual(ordered[0].role, .user)
    XCTAssertEqual(ordered[1].content, "Hallo zurück!")
  }

  func testAppendUpdatesTimestamp() throws {
    let container = try ModelContainer(
      for: Conversation.self, Message.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = ModelContext(container)
    let conv = Conversation(title: "Test")
    ctx.insert(conv)
    let beforeTimestamp = conv.updatedAt
    Thread.sleep(forTimeInterval: 0.01)
    conv.append(Message(role: .user, content: "Hi"))
    try ctx.save()
    XCTAssertGreaterThan(conv.updatedAt, beforeTimestamp)
  }
}
