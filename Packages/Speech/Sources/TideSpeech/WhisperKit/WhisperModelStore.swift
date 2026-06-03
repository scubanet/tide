import Foundation
import OSLog
import WhisperKit

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "whisper-store")

/// Metadata for a WhisperKit CoreML model in the curated catalog.
public struct WhisperModelInfo: Identifiable, Sendable, Hashable {
  public let id: String
  public let displayName: String
  public let approxSizeMB: Int
  public let isInstalled: Bool
}

public enum WhisperModelError: LocalizedError {
  case modelMissing(String)
  case downloadIncomplete(String)

  public var errorDescription: String? {
    switch self {
    case .modelMissing(let id):       "Lokales Modell fehlt: \(id)"
    case .downloadIncomplete(let id): "Modell-Download unvollständig: \(id)"
    }
  }
}

/// Manages on-disk WhisperKit models: catalog, install detection, download.
/// Stateless aside from the injected base directory, so it is cheap to
/// construct anywhere (tests inject a temp directory).
public struct WhisperModelStore: Sendable {
  public static let smallModelID   = "openai_whisper-small_216MB"
  public static let turboModelID   = "openai_whisper-large-v3-v20240930_turbo_632MB"
  public static let largeV3ModelID = "openai_whisper-large-v3-v20240930_626MB"
  public static let modelRepo      = "argmaxinc/whisperkit-coreml"

  /// Catalog order = UI order. Small first (default, fastest).
  private static let entries: [(id: String, name: String, mb: Int)] = [
    (smallModelID,   "Whisper Small",          216),
    (turboModelID,   "Whisper Large v3 Turbo", 632),
    (largeV3ModelID, "Whisper Large v3",       626),
  ]

  public let baseDirectory: URL

  /// - Parameter baseDirectory: where models live. Defaults to
  ///   `~/Library/Application Support/Tide/models/whisperkit`.
  public init(baseDirectory: URL? = nil) {
    if let baseDirectory {
      self.baseDirectory = baseDirectory
    } else {
      let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first!
      self.baseDirectory = appSupport
        .appendingPathComponent("Tide", isDirectory: true)
        .appendingPathComponent("models", isDirectory: true)
        .appendingPathComponent("whisperkit", isDirectory: true)
    }
  }

  public func modelURL(id: String) -> URL {
    baseDirectory.appendingPathComponent(id, isDirectory: true)
  }

  public func isInstalled(_ id: String) -> Bool {
    let dir = modelURL(id: id)
    let fm = FileManager.default
    return ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"]
      .allSatisfy { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }
  }

  /// The curated catalog with per-entry install state.
  public func catalog() -> [WhisperModelInfo] {
    Self.entries.map {
      WhisperModelInfo(id: $0.id, displayName: $0.name, approxSizeMB: $0.mb, isInstalled: isInstalled($0.id))
    }
  }

  /// Download + install `id` from HuggingFace into `baseDirectory`. Reports
  /// fractional progress (0…1). No-op (progress 1) if already installed.
  /// Not unit-tested (network + CoreML); exercised by manual smoke test.
  public func download(
    id: String,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    if isInstalled(id) { progress(1); return }
    let fm = FileManager.default
    try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

    let downloadRoot = baseDirectory
      .appendingPathComponent("downloads", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: downloadRoot, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: downloadRoot) }

    let downloaded = try await WhisperKit.download(
      variant: id,
      downloadBase: downloadRoot,
      from: Self.modelRepo,
      progressCallback: { p in
        let f = p.fractionCompleted
        progress(f.isFinite ? f : 0)
      }
    )

    let destination = modelURL(id: id)
    if fm.fileExists(atPath: destination.path) {
      try fm.removeItem(at: destination)
    }
    try fm.moveItem(at: downloaded, to: destination)

    guard isInstalled(id) else {
      throw WhisperModelError.downloadIncomplete(id)
    }
    progress(1)
  }
}
