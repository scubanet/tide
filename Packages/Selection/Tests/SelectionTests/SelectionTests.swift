import XCTest
@testable import Selection

/// Smoke test that the package's public surface area is importable.
/// The meaty unit tests live in `TextInjectorTests`; this file just
/// verifies the module's public types exist.
final class SelectionTests: XCTestCase {
  func testPackageImports() {
    // Touch each public namespace so a future rename would surface
    // here as a compile error.
    _ = SelectionReplacer.self
    _ = SelectionReader.self
    _ = ClipboardPaste.self
    _ = TextInjector.self
  }
}
