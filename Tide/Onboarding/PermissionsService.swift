import Foundation
import AVFoundation
import Speech
import ApplicationServices

/// Tri-state permission status for the onboarding UI.
enum PermissionStatus: Equatable {
  case granted
  case denied
  case notDetermined
}

/// Thin fassade over the system permission APIs the onboarding wizard needs:
/// microphone, speech recognition, and Accessibility. The status→enum
/// mapping is the unit-tested part; the system calls themselves are not.
@MainActor
struct PermissionsService {

  // MARK: Mapping (pure, tested)

  nonisolated static func map(_ s: AVAuthorizationStatus) -> PermissionStatus {
    switch s {
    case .authorized:    .granted
    case .denied:        .denied
    case .restricted:    .denied
    case .notDetermined: .notDetermined
    @unknown default:    .notDetermined
    }
  }

  nonisolated static func map(_ s: SFSpeechRecognizerAuthorizationStatus) -> PermissionStatus {
    switch s {
    case .authorized:    .granted
    case .denied:        .denied
    case .restricted:    .denied
    case .notDetermined: .notDetermined
    @unknown default:    .notDetermined
    }
  }

  // MARK: Microphone

  func microphone() -> PermissionStatus {
    Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
  }

  func requestMicrophone() async -> Bool {
    await AVCaptureDevice.requestAccess(for: .audio)
  }

  // MARK: Speech recognition

  func speech() -> PermissionStatus {
    Self.map(SFSpeechRecognizer.authorizationStatus())
  }

  func requestSpeech() async -> Bool {
    await withCheckedContinuation { cont in
      SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
    }
  }

  // MARK: Accessibility (cannot be granted in-process)

  func accessibility() -> Bool {
    AXIsProcessTrusted()
  }

  /// Opens the system Accessibility prompt / Settings pane. The user must
  /// toggle Tide on there; poll `accessibility()` afterwards.
  func promptAccessibility() {
    // kAXTrustedCheckOptionPrompt is a C global — use its string value
    // directly to stay Swift 6 concurrency-safe.
    let key = "AXTrustedCheckOptionPrompt"
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
  }
}
