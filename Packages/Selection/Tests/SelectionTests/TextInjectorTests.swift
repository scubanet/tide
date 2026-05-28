import AppKit
import XCTest
@testable import Selection

/// Pure unit tests for `TextInjector` — no AX, no CGEvent.
///
/// We can't reach the AX-Insert path from XCTest (it requires
/// `AXIsProcessTrusted()` plus a real frontmost app with a focused text
/// element), and we can't reach the CGEvent ⌘V post from a unit-test
/// host (no event tap). What we *can* test is:
///
///   - Input-validation: empty / whitespace-only input is rejected
///     before any side-effect (no pasteboard mutation).
///   - Strategy-selection: when Tide itself is the frontmost app the
///     clipboard-paste branch is skipped (it'd be a no-op for
///     dictation), and we fall through to pasteboard-only.
///   - Strategy-selection: when another app is frontmost we take the
///     clipboard-paste branch — and the pasteboard ends up containing
///     our text immediately after the call (the synthetic ⌘V is a
///     no-op in the test host, but the pasteboard mutation is real).
///
/// Tests stub the frontmost-app check via `TextInjector._frontmostBundleID`
/// and reset it in `tearDown`.
@MainActor
final class TextInjectorTests: XCTestCase {
  private var originalFrontmostBundleID: (() -> String?)!
  private var originalFrontmostPID: (() -> pid_t?)!
  private var savedClipboard: String?

  override func setUp() {
    super.setUp()
    originalFrontmostBundleID = TextInjector._frontmostBundleID
    originalFrontmostPID = TextInjector._frontmostPID
    // Force the AX strategy to bail out fast in unit tests — return
    // nil PID so attemptAXInsert short-circuits without touching real
    // AX. (AXIsProcessTrusted() in xctest hosts is normally false too,
    // but belt-and-braces.)
    TextInjector._frontmostPID = { nil }
    // Disable the User-Notification path so running the suite never
    // pops a real macOS permission dialog. Strategy 3 still mutates
    // the pasteboard — it just doesn't try to toast.
    TextInjector._notificationsEnabled = false
    savedClipboard = NSPasteboard.general.string(forType: .string)
  }

  override func tearDown() {
    TextInjector._frontmostBundleID = originalFrontmostBundleID
    TextInjector._frontmostPID = originalFrontmostPID
    TextInjector._notificationsEnabled = true
    // Restore the developer's clipboard so running the test suite
    // doesn't trample their pasteboard.
    let pb = NSPasteboard.general
    pb.clearContents()
    if let saved = savedClipboard {
      pb.setString(saved, forType: .string)
    }
    super.tearDown()
  }

  // MARK: - Empty / whitespace input

  func test_insert_emptyString_returnsSkippedEmpty() async {
    let result = await TextInjector.insert("")
    XCTAssertEqual(result, .skippedEmpty)
  }

  func test_insert_whitespaceOnly_returnsSkippedEmpty() async {
    let result = await TextInjector.insert("   \n\t  ")
    XCTAssertEqual(result, .skippedEmpty)
  }

  func test_insert_emptyString_doesNotMutatePasteboard() async {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString("sentinel-do-not-touch", forType: .string)
    _ = await TextInjector.insert("")
    XCTAssertEqual(pb.string(forType: .string), "sentinel-do-not-touch")
  }

  // MARK: - Strategy selection: Tide frontmost

  func test_insert_whenTideIsFrontmost_skipsClipboardPaste() async throws {
    // Inside the injector the check is `front != Bundle.main.bundleIdentifier`.
    // For a swiftpm xctest host `Bundle.main.bundleIdentifier` is usually
    // nil; for an app-hosted xctest it's the host bundle. Either way,
    // returning that exact value from the stub forces front == tideBundle
    // and strategy 2 is skipped.
    let hostBundle = Bundle.main.bundleIdentifier
    try XCTSkipIf(hostBundle == nil,
      "Bundle.main.bundleIdentifier is nil under swift-test; covered by no-frontmost-app test")
    TextInjector._frontmostBundleID = { hostBundle }
    let result = await TextInjector.insert("Hello")
    XCTAssertEqual(result, .pasteboardOnly)
  }

  // MARK: - Strategy selection: another app frontmost

  func test_insert_whenOtherAppIsFrontmost_takesClipboardPaste() async {
    TextInjector._frontmostBundleID = { "com.example.SomeOtherApp" }
    let result = await TextInjector.insert("Hello")
    XCTAssertEqual(result, .clipboardPaste)
    // The pasteboard should contain our text immediately after the
    // call. (The synthetic ⌘V is a no-op in the test host — no event
    // tap, no frontmost app to receive — but the pasteboard mutation
    // is real and synchronous, before the 400ms restore timer fires.)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Hello")
  }

  func test_insert_whenNoFrontmostApp_fallsThroughToPasteboardOnly() async {
    TextInjector._frontmostBundleID = { nil }
    let result = await TextInjector.insert("Hello")
    XCTAssertEqual(result, .pasteboardOnly)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Hello")
  }

  // MARK: - Trimming preserves inner whitespace

  func test_insert_trimmingKeepsInnerWhitespace() async {
    TextInjector._frontmostBundleID = { "com.example.SomeOtherApp" }
    let result = await TextInjector.insert("  Hello world  ")
    XCTAssertEqual(result, .clipboardPaste)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Hello world")
  }
}
