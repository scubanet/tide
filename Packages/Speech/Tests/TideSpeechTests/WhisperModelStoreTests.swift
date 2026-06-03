import XCTest
@testable import TideSpeech

final class WhisperModelStoreTests: XCTestCase {
  private func tempBase() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("whisper-test-\(UUID().uuidString)", isDirectory: true)
  }

  func test_catalog_hasThreeModels_smallFirst() {
    let store = WhisperModelStore(baseDirectory: tempBase())
    let catalog = store.catalog()
    XCTAssertEqual(catalog.count, 3)
    XCTAssertEqual(catalog.first?.id, WhisperModelStore.smallModelID)
  }

  func test_modelURL_isUnderBaseDirectory() {
    let base = tempBase()
    let store = WhisperModelStore(baseDirectory: base)
    let url = store.modelURL(id: WhisperModelStore.smallModelID)
    XCTAssertTrue(url.path.hasPrefix(base.path))
    XCTAssertEqual(url.lastPathComponent, WhisperModelStore.smallModelID)
  }

  func test_isInstalled_falseForEmptyDir() {
    let store = WhisperModelStore(baseDirectory: tempBase())
    XCTAssertFalse(store.isInstalled(WhisperModelStore.smallModelID))
  }

  func test_isInstalled_trueWhenMarkersPresent() throws {
    let base = tempBase()
    let store = WhisperModelStore(baseDirectory: base)
    let id = WhisperModelStore.smallModelID
    let dir = store.modelURL(id: id)
    let fm = FileManager.default
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for marker in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
      try fm.createDirectory(at: dir.appendingPathComponent(marker), withIntermediateDirectories: true)
    }
    XCTAssertTrue(store.isInstalled(id))
    addTeardownBlock { try? fm.removeItem(at: base) }
  }

  func test_installedCatalog_flagsInstalledModel() throws {
    let base = tempBase()
    let store = WhisperModelStore(baseDirectory: base)
    let id = WhisperModelStore.smallModelID
    let dir = store.modelURL(id: id)
    let fm = FileManager.default
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for marker in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
      try fm.createDirectory(at: dir.appendingPathComponent(marker), withIntermediateDirectories: true)
    }
    let catalog = store.catalog()
    XCTAssertTrue(catalog.first { $0.id == id }?.isInstalled ?? false)
    XCTAssertFalse(catalog.first { $0.id == WhisperModelStore.largeV3ModelID }?.isInstalled ?? true)
    addTeardownBlock { try? fm.removeItem(at: base) }
  }
}
