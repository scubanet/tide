import Foundation
import AVFoundation
import OSLog

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "tts.elevenlabs")

/// `Synthesizer` impl that pipes text → ElevenLabs API → AVAudioPlayer.
///
/// Queue behaviour: each `speak(_:)` triggers an async HTTP request. The
/// returned audio is appended to an internal FIFO queue. Playback is
/// serial — the next clip starts only after the previous one finishes.
/// This matches `AppleSynthesizer`'s queue semantics so the rest of the
/// app doesn't need to care which provider is active.
///
/// Isolation: the whole class is `@MainActor` (via `Synthesizer`), so
/// queue state and the `AVAudioPlayer` lifecycle live in one domain —
/// no lock, and `stop()` can never race a player mid-construction.
public final class ElevenLabsSynthesizer: NSObject, Synthesizer {
  private let client: ElevenLabsClient
  private var voiceID: String
  // Ordered playback queue — audio clips ready to play, in original speak() order.
  private var audioQueue: [Data] = []
  // Out-of-order arrivals: synthesis Tasks run in parallel for speed, but
  // their responses can come back in any order. Each speak() gets a
  // monotonically-increasing sequence number; arrivals land here keyed by
  // their sequence until they can be flushed into `audioQueue` contiguously.
  private var pendingAudio: [Int: Data] = [:]
  private var nextSequence: Int = 0
  private var nextToEnqueue: Int = 0
  // Epoch token: bumped on every stop(). Arrivals captured during an older
  // cycle compare their captured generation against the current one and
  // drop themselves if stale, so a late TTS response can't leak into a
  // freshly-reset queue.
  private var generation: Int = 0
  private var currentPlayer: AVAudioPlayer?
  // In-flight synthesis requests keyed by sequence. `stop()` cancels them
  // — cancellation propagates into URLSession, so abandoned requests
  // don't keep running (or keep `self` alive) after the user hit stop.
  private var inflightTasks: [Int: Task<Void, Never>] = [:]

  public init(client: ElevenLabsClient, defaultVoiceID: String) {
    self.client = client
    self.voiceID = defaultVoiceID
    super.init()
  }

  public var isSpeaking: Bool {
    currentPlayer?.isPlaying == true || !audioQueue.isEmpty || !pendingAudio.isEmpty
  }

  public func setVoice(identifier: String) {
    voiceID = identifier
  }

  public func speak(_ text: String) {
    guard !text.isEmpty else { return }
    let id = voiceID
    let seq = nextSequence
    nextSequence += 1
    let gen = generation
    log.debug("requesting TTS seq=\(seq, privacy: .public) (\(text.count, privacy: .public) chars)")
    inflightTasks[seq] = Task { [client, weak self] in
      do {
        let data = try await client.synthesize(text: text, voiceID: id)
        log.debug("TTS arrived seq=\(seq, privacy: .public) (\(data.count, privacy: .public) bytes)")
        self?.deliver(gen: gen, seq: seq, data: data)
      } catch {
        if !(error is CancellationError) {
          log.error("TTS seq=\(seq, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        // Mark this slot as a no-op so subsequent ones still flush.
        self?.skip(gen: gen, seq: seq)
      }
      self?.inflightTasks[seq] = nil
    }
  }

  public func stop() {
    generation += 1
    for task in inflightTasks.values { task.cancel() }
    inflightTasks.removeAll()
    audioQueue.removeAll()
    pendingAudio.removeAll()
    // Reset sequence numbers so the next response cycle starts at 0.
    nextSequence = 0
    nextToEnqueue = 0
    currentPlayer?.stop()
    currentPlayer = nil
  }

  // MARK: - Reorder buffer

  private func deliver(gen: Int, seq: Int, data: Data) {
    guard gen == generation else { return }  // stale cycle
    pendingAudio[seq] = data
    // Drain any contiguous prefix into the playback queue.
    while let ready = pendingAudio.removeValue(forKey: nextToEnqueue) {
      audioQueue.append(ready)
      nextToEnqueue += 1
    }
    if currentPlayer == nil && !audioQueue.isEmpty { playNext() }
  }

  private func skip(gen: Int, seq: Int) {
    guard gen == generation else { return }  // stale cycle
    pendingAudio[seq] = Data()  // empty marker
    while let ready = pendingAudio.removeValue(forKey: nextToEnqueue) {
      if !ready.isEmpty { audioQueue.append(ready) }
      nextToEnqueue += 1
    }
    if currentPlayer == nil && !audioQueue.isEmpty { playNext() }
  }

  // MARK: - Playback

  private func playNext() {
    guard !audioQueue.isEmpty else {
      currentPlayer = nil
      return
    }
    let data = audioQueue.removeFirst()
    do {
      let player = try AVAudioPlayer(data: data)
      player.delegate = self
      currentPlayer = player
      player.prepareToPlay()
      player.play()
    } catch {
      log.error("AVAudioPlayer init failed: \(error.localizedDescription, privacy: .public)")
      playNext()  // skip the bad clip and continue
    }
  }
}

extension ElevenLabsSynthesizer: AVAudioPlayerDelegate {
  nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in self.playNext() }
  }
}
