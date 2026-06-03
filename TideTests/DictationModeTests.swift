import XCTest
import Core
@testable import Tide

final class DictationModeTests: XCTestCase {
  @MainActor
  func test_allCases_containsAllSix() {
    let all = Set(DictationMode.allCases)
    XCTAssertEqual(all, [.raw, .polished, .calmer, .emoji, .bullets, .professional])
  }

  @MainActor
  func test_isRaw_onlyForRaw() {
    XCTAssertTrue(DictationMode.raw.isRaw)
    for m in DictationMode.allCases where m != .raw {
      XCTAssertFalse(m.isRaw)
    }
  }

  @MainActor
  func test_basePrompt_rawIsNil() {
    let s = AppSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    XCTAssertNil(DictationMode.raw.basePrompt(from: s))
  }

  @MainActor
  func test_basePrompt_mapsEachModeToItsSetting() {
    let s = AppSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    s.dictationPolishPrompt = "P"
    s.dictationCalmerPrompt = "C"
    s.dictationEmojiPrompt = "E"
    s.dictationBulletsPrompt = "B"
    s.dictationProfessionalPrompt = "PRO"
    XCTAssertEqual(DictationMode.polished.basePrompt(from: s), "P")
    XCTAssertEqual(DictationMode.calmer.basePrompt(from: s), "C")
    XCTAssertEqual(DictationMode.emoji.basePrompt(from: s), "E")
    XCTAssertEqual(DictationMode.bullets.basePrompt(from: s), "B")
    XCTAssertEqual(DictationMode.professional.basePrompt(from: s), "PRO")
  }
}
