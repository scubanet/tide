import XCTest
@testable import Core

final class KeychainHelperTests: XCTestCase {
  private let testKey = "tide.test.\(UUID().uuidString)"

  override func tearDown() async throws {
    KeychainHelper.delete(key: testKey)
  }

  func testRoundTrip() throws {
    try KeychainHelper.set(key: testKey, value: "sk-ant-123")
    XCTAssertEqual(KeychainHelper.get(key: testKey), "sk-ant-123")
  }

  func testOverwrite() throws {
    try KeychainHelper.set(key: testKey, value: "first")
    try KeychainHelper.set(key: testKey, value: "second")
    XCTAssertEqual(KeychainHelper.get(key: testKey), "second")
  }

  func testDelete() throws {
    try KeychainHelper.set(key: testKey, value: "x")
    KeychainHelper.delete(key: testKey)
    XCTAssertNil(KeychainHelper.get(key: testKey))
  }

  func testGetMissingReturnsNil() {
    XCTAssertNil(KeychainHelper.get(key: "tide.does-not-exist.\(UUID().uuidString)"))
  }
}
