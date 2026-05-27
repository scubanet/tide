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
public final class ElevenLabsSynthesizer: NSObject, Synthesizer, @unchecked Sendable {
  private let client: ElevenLabsClient
  private let lock = NSLock()
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
  private var currentPlayer: AVAudioPlayer?

  public init(client: ElevenLabsClient, defaultVoiceID: String) {
    self.client = client
    self.voiceID = defaultVoiceID
    super.init()
  }

  public var isSpeaking: Bool {
    lock.lock(); defer { lock.unlock() }
    return currentPlayer?.isPlaying == true || !audioQueue.isEmpty || !pendingAudio.isEmpty
  }

  public func setVoice(identifier: String) {
    lock.lock(); defer { lock.unlock() }
    voiceID = identifier
  }

  public func speak(_ text: String) {
    guard !text.isEmpty else { return }
    lock.lock()
    let id = voiceID
    let seq = nextSequence
    nextSequence += 1
    lock.unlock()
    log.debug("requesting TTS seq=\(seq, privacy: .public) (\(text.count, privacy: .public) chars)")
    Task { [client] in
      do {
        let data = try await client.synthesize(text: text, voiceID: id)
        log.debug("TTS arrived seq=\(seq, privacy: .public) (\(data.count, privacy: .public) bytes)")
        await MainActor.run { self.deliver(seq: seq, data: data) }
      } catch {
        log.error("TTS seq=\(seq, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        // Mark this slot as a no-op so subsequent ones still flush.
        await MainActor.run { self.skip(seq: seq) }
      }
    }
  }

  public func stop() {
    lock.lock()
    audioQueue.removeAll()
    pendingAudio.removeAll()
    // Reset sequence numbers so the next response cycle starts at 0.
    nextSequence = 0
    nextToEnqueue = 0
    currentPlayer?.stop()
    currentPlayer = nil
    lock.unlock()
  }

  // MARK: - Reorder buffer

  @MainActor
  private func deliver(seq: Int, data: Data) {
    lock.lock()
    pendingAudio[seq] = data
    // Drain any contiguous prefix into the playback queue.
    while let ready = pendingAudio.removeValue(forKey: nextToEnqueue) {
      audioQueue.append(ready)
      nextToEnqueue += 1
    }
    let shouldStart = currentPlayer == nil && !audioQueue.isEmpty
    lock.unlock()
    if shouldStart { playNext() }
  }

  @MainActor
  private func skip(seq: Int) {
    lock.lock()
    pendingAudio[seq] = Data()  // empty marker
    while let ready = pendingAudio.removeValue(forKey: nextToEnqueue) {
      if !ready.isEmpty { audioQueue.append(ready) }
      nextToEnqueue += 1
    }
    let shouldStart = currentPlayer == nil && !audioQueue.isEmpty
    lock.unlock()
    if shouldStart { playNext() }
  }

  // MARK: - Playback

  @MainActor
  private func playNext() {
    lock.lock()
    guard !audioQueue.isEmpty else {
      currentPlayer = nil
      lock.unlock()
      return
    }
    let data = audioQueue.removeFirst()
    lock.unlock()

    do {
      let player = try AVAudioPlayer(data: data)
      player.delegate = self
      lock.lock()
      currentPlayer = player
      lock.unlock()
      player.prepareToPlay()
      player.play()
    } catch {
      log.error("AVAudioPlayer init failed: \(error.localizedDescription, privacy: .public)")
      playNext()  // skip the bad clip and continue
    }
  }
}

extension ElevenLabsSynthesizer: AVAudioPlayerDelegate {
  public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in self.playNext() }
  }
}
