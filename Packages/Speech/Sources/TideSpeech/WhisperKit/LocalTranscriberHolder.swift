import Foundation

/// Single access point for the process-wide shared `Transcribing` instance.
///
/// SwiftUI Settings views can't receive constructor-injected dependencies,
/// and `RecognizerFactory` is a static enum — so AppEntry sets the shared
/// `WhisperKitTranscriber` here once at launch and every consumer reads it.
@MainActor
public final class LocalTranscriberHolder {
  public static let shared = LocalTranscriberHolder()
  public var transcriber: (any Transcribing)?
  private init() {}
}
