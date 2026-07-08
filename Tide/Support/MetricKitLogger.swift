import Foundation
import OSLog
#if canImport(MetricKit)
import MetricKit
#endif

/// Minimal MetricKit subscriber. Logs crash / hang / CPU-exception
/// diagnostics to the `swiss.weckherlin.tide.metrics` OSLog subsystem so
/// they're retrievable via `log show` and Console after the fact — a
/// lightweight, privacy-preserving stand-in until a full crash-report
/// backend is wired (no data leaves the Mac).
final class MetricKitLogger: NSObject, @unchecked Sendable {
  static let shared = MetricKitLogger()
  private static let log = Logger(subsystem: "swiss.weckherlin.tide", category: "metrics")

  /// Register as a MetricKit subscriber. Call once at launch.
  func start() {
    #if canImport(MetricKit)
    MXMetricManager.shared.add(self)
    #endif
  }
}

#if canImport(MetricKit)
extension MetricKitLogger: MXMetricManagerSubscriber {
  func didReceive(_ payloads: [MXMetricPayload]) {
    for payload in payloads {
      Self.log.debug("MetricKit metrics payload: \(payload.jsonRepresentation().count, privacy: .public) bytes")
    }
  }

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    for payload in payloads {
      let json = String(data: payload.jsonRepresentation(), encoding: .utf8) ?? "<unreadable>"
      Self.log.error("MetricKit diagnostic payload: \(json, privacy: .public)")
    }
  }
}
#endif
