import XCTest
@testable import Core

final class QuickActionLibraryTests: XCTestCase {
  @MainActor
  func testReturnsSixBuiltIns() {
    let suite = "test.\(UUID().uuidString)"
    let lib = QuickActionLibrary(defaults: UserDefaults(suiteName: suite)!)
    XCTAssertEqual(lib.all().count, 6)
    XCTAssertTrue(lib.all().contains { $0.slug == "summarize" })
    XCTAssertTrue(lib.all().contains { $0.slug == "translate" })
  }

  @MainActor
  func testAddCustomAction() {
    let suite = "test.\(UUID().uuidString)"
    let lib = QuickActionLibrary(defaults: UserDefaults(suiteName: suite)!)
    let custom = QuickAction(slug: "rhyme", label: "Reimen",
      systemPrompt: "Mach daraus ein Reim.", isBuiltIn: false)
    lib.add(custom)
    XCTAssertEqual(lib.all().count, 7)
    XCTAssertTrue(lib.all().contains { $0.slug == "rhyme" })
  }

  @MainActor
  func testUpdateCustomAction() {
    let suite = "test.\(UUID().uuidString)"
    let lib = QuickActionLibrary(defaults: UserDefaults(suiteName: suite)!)
    var custom = QuickAction(slug: "x", label: "X", systemPrompt: "x", isBuiltIn: false)
    lib.add(custom)
    custom.label = "X2"
    lib.update(custom)
    XCTAssertEqual(lib.custom().first?.label, "X2")
  }

  @MainActor
  func testDeleteCustomAction() {
    let suite = "test.\(UUID().uuidString)"
    let lib = QuickActionLibrary(defaults: UserDefaults(suiteName: suite)!)
    let custom = QuickAction(slug: "x", label: "X", systemPrompt: "x", isBuiltIn: false)
    lib.add(custom)
    lib.delete(id: custom.id)
    XCTAssertEqual(lib.custom().count, 0)
    XCTAssertEqual(lib.all().count, 6)  // built-ins still there
  }

  @MainActor
  func testCannotUpdateBuiltIn() {
    let suite = "test.\(UUID().uuidString)"
    let lib = QuickActionLibrary(defaults: UserDefaults(suiteName: suite)!)
    var builtIn = lib.all().first(where: { $0.slug == "summarize" })!
    builtIn.label = "Hijacked"
    lib.update(builtIn)
    XCTAssertEqual(lib.all().first(where: { $0.slug == "summarize" })?.label, "Zusammenfassen")
  }
}
