import Foundation
import OSLog
@preconcurrency import WhisperKit

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "whisper-transcriber")

/// Abstraction over a local transcription engine so `WhisperKitRecognizer`
/// can be unit-tested with a mock.
public protocol Transcribing: Sendable {
  func transcribe(wav: Data, language: String?, modelName: String) async throws -> String
  /// Load (and cache) the model so the first transcription has no
  /// cold-start spike. A non-warming engine (or a mock) can no-op.
  func prewarm(modelName: String) async throws
}

/// One shared actor instance (built in AppEntry, reached via
/// `LocalTranscriberHolder`). Owns the loaded WhisperKit pipeline; the
/// pipeline never crosses the actor boundary (Swift-6 non-Sendable safe).
/// Reloads when a different `modelName` is requested.
public actor WhisperKitTranscriber: Transcribing {
  private let store: WhisperModelStore
  private var pipeline: WhisperKit?
  private var loadedModelName: String?

  public init(store: WhisperModelStore) {
    self.store = store
  }

  /// Load (and cache) the pipeline for `modelName` so the first dictation
  /// has no cold-start spike. Safe to call repeatedly.
  public func prewarm(modelName: String) async throws {
    try await ensurePipeline(modelName: modelName)
  }

  public func transcribe(wav: Data, language: String?, modelName: String) async throws -> String {
    try await ensurePipeline(modelName: modelName)
    guard let pipeline else { throw WhisperModelError.modelMissing(modelName) }

    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
    try wav.write(to: tmp)
    defer { try? fm.removeItem(at: tmp) }

    let options = DecodingOptions(task: .transcribe, language: language)
    let results = try await pipeline.transcribe(audioPath: tmp.path, decodeOptions: options)
    return results
      .map(\.text)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Ensures the pipeline for `modelName` is loaded and cached.
  private func ensurePipeline(modelName: String) async throws {
    if pipeline != nil, loadedModelName == modelName { return }
    let url = store.modelURL(id: modelName)
    guard store.isInstalled(modelName) else {
      throw WhisperModelError.modelMissing(modelName)
    }
    log.debug("loading WhisperKit model \(modelName, privacy: .public)")
    let loaded = try await WhisperKit(
      modelFolder: url.path,
      verbose: false,
      prewarm: true,
      load: true,
      download: false
    )
    pipeline = loaded
    loadedModelName = modelName
  }
}
