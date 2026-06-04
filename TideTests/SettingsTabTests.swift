import XCTest
@testable import Tide

final class SettingsTabTests: XCTestCase {
  func test_allCases_hasEight() {
    XCTAssertEqual(SettingsTab.allCases.count, 8)
  }

  func test_everyCase_hasLabelAndIcon() {
    for tab in SettingsTab.allCases {
      XCTAssertFalse(tab.label.isEmpty, "\(tab) has empty label")
      XCTAssertFalse(tab.systemImage.isEmpty, "\(tab) has empty systemImage")
    }
  }

  func test_groups_coverEveryCase_withoutDuplication() {
    let grouped = SettingsTab.groups.flatMap { $0.tabs }
    XCTAssertEqual(Set(grouped), Set(SettingsTab.allCases), "groups must cover all cases")
    XCTAssertEqual(grouped.count, SettingsTab.allCases.count, "a tab appears in exactly one group")
  }

  func test_groups_titlesNonEmpty() {
    for group in SettingsTab.groups {
      XCTAssertFalse(group.title.isEmpty)
      XCTAssertFalse(group.tabs.isEmpty)
    }
  }
}
