import Foundation
import UserNotifications
import OSLog

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "notification")

/// Shared "Tide — Diktat" local-notification poster. Both the paste
/// fallback (`TextInjector`) and the polish-failed notice
/// (`DictationCoordinator`) post the same shape of notification —
/// permission handling and failure logging live here once.
public enum TideNotification {
  /// Request `.alert` authorization (no-op if already decided) and post
  /// a notification. Failures degrade gracefully and are logged.
  public static func post(body: String, idPrefix: String) async {
    let center = UNUserNotificationCenter.current()
    let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
    guard granted else {
      log.warning("notification permission denied — '\(idPrefix, privacy: .public)' notice skipped")
      return
    }
    let content = UNMutableNotificationContent()
    content.title = "Tide — Diktat"
    content.body = body
    let request = UNNotificationRequest(
      identifier: "\(idPrefix).\(UUID().uuidString)",
      content: content,
      trigger: nil
    )
    do {
      try await center.add(request)
    } catch {
      log.warning("posting '\(idPrefix, privacy: .public)' notification failed: \(error.localizedDescription, privacy: .public)")
    }
  }
}
