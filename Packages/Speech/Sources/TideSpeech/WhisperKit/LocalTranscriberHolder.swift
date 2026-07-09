import Foundation
import OSLog

/// Single access point for the process-wide shared `Transcribing` instance.
///
/// SwiftUI Settings views can't receive constructor-injected dependencies,
/// and `RecognizerFactory` is a static enum — so AppEntry sets the shared
/// `WhisperKitTranscriber` here once at launch and every consumer reads it.
///
/// Write-once: the first `install(_:)` wins; later calls are ignored and
/// logged. Consumers reading before AppEntry installs get `nil` and fall
/// back to the Apple recognizer — install as early in launch as possible.
@MainActor
public final class LocalTranscriberHolder {
  public static let shared = LocalTranscriberHolder()
  public private(set) var transcriber: (any Transcribing)?
  private static let log = Logger(subsystem: "swiss.weckherlin.tide", category: "whisperkit")
  private init() {}

  public func install(_ transcriber: any Transcribing) {
    guard self.transcriber == nil else {
      Self.log.warning("install ignored — transcriber already set")
      return
    }
    self.transcriber = transcriber
  }
}
