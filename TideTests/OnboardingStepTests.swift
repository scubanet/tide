import XCTest
@testable import Tide

final class OnboardingStepTests: XCTestCase {
  func test_order() {
    XCTAssertEqual(OnboardingStep.allCases,
      [.welcome, .apiKey, .permissions, .hotkey, .voice, .done])
  }

  func test_next_clampsAtDone() {
    XCTAssertEqual(OnboardingStep.welcome.next, .apiKey)
    XCTAssertEqual(OnboardingStep.done.next, .done)
  }

  func test_previous_clampsAtWelcome() {
    XCTAssertEqual(OnboardingStep.apiKey.previous, .welcome)
    XCTAssertEqual(OnboardingStep.welcome.previous, .welcome)
  }

  func test_progress_indexAndCount() {
    XCTAssertEqual(OnboardingStep.welcome.index, 0)
    XCTAssertEqual(OnboardingStep.done.index, 5)
    XCTAssertEqual(OnboardingStep.count, 6)
  }

  func test_titlesNonEmpty() {
    for s in OnboardingStep.allCases { XCTAssertFalse(s.title.isEmpty) }
  }
}
