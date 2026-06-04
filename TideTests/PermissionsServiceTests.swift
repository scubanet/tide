import XCTest
import AVFoundation
import Speech
@testable import Tide

final class PermissionsServiceTests: XCTestCase {
  func test_avStatusMapping() {
    XCTAssertEqual(PermissionsService.map(AVAuthorizationStatus.authorized), .granted)
    XCTAssertEqual(PermissionsService.map(AVAuthorizationStatus.denied), .denied)
    XCTAssertEqual(PermissionsService.map(AVAuthorizationStatus.restricted), .denied)
    XCTAssertEqual(PermissionsService.map(AVAuthorizationStatus.notDetermined), .notDetermined)
  }

  func test_speechStatusMapping() {
    XCTAssertEqual(PermissionsService.map(SFSpeechRecognizerAuthorizationStatus.authorized), .granted)
    XCTAssertEqual(PermissionsService.map(SFSpeechRecognizerAuthorizationStatus.denied), .denied)
    XCTAssertEqual(PermissionsService.map(SFSpeechRecognizerAuthorizationStatus.restricted), .denied)
    XCTAssertEqual(PermissionsService.map(SFSpeechRecognizerAuthorizationStatus.notDetermined), .notDetermined)
  }
}
