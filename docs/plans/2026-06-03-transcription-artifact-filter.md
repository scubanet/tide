# Transcription Artifact Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verwerfe ASR-Artefakte (zu-kurze Aufnahmen, Halluzinationen) bevor sie am Cursor (Diktat) oder als Chat-Bubble (PTT) landen.

**Architecture:** Reine Filter-Logik (`TranscriptionQuality`) im `TideSpeech`-Package, gespeist von einer neuen `AudioBufferAccumulator.duration`-Property. Zwei Consumer (`DictationCoordinator`, `ChatViewModel`) rufen den Filter nach `recorder.stop()`. Diktat-Reject zeigt einen Pille-Flash, Chat-Reject verwirft still.

**Tech Stack:** Swift, XCTest, AVFoundation, SwiftUI/AppKit (Pille). Package-Tests via `swift test`, App-Tests via `xcodebuild test`.

---

## File Structure

| Datei | Verantwortung |
|---|---|
| `Packages/Speech/Sources/TideSpeech/TranscriptionQuality.swift` | **neu** — reine Reject/Artefakt-Heuristik |
| `Packages/Speech/Tests/TideSpeechTests/TranscriptionQualityTests.swift` | **neu** — Grenzfall-Tests |
| `Tide/Recorder/AudioBufferAccumulator.swift` | + `duration`-Property |
| `TideTests/AudioBufferAccumulatorTests.swift` | + duration-Tests |
| `Tide/Dictation/FloatingPill.swift` | + `flash()`, `PillViewState.isHint` |
| `Tide/Dictation/DictationIndicator.swift` | + `flash()` pass-through |
| `Tide/Dictation/DictationCoordinator.swift` | Reject-Guard + flash statt Notification |
| `Tide/Panel/ChatViewModel.swift` | Reject-Guard (still verwerfen) |

**Branch:** Vor Task 1 anlegen: `git checkout -b feat/artifact-filter`

---

## Task 1: `TranscriptionQuality` Filter-Logik

**Files:**
- Create: `Packages/Speech/Sources/TideSpeech/TranscriptionQuality.swift`
- Test: `Packages/Speech/Tests/TideSpeechTests/TranscriptionQualityTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Packages/Speech/Tests/TideSpeechTests/TranscriptionQualityTests.swift`:

```swift
import XCTest
@testable import TideSpeech

final class TranscriptionQualityTests: XCTestCase {

  // MARK: shouldRejectRecording

  func test_shouldReject_belowMinimumDuration() {
    XCTAssertTrue(TranscriptionQuality.shouldRejectRecording(duration: 0.2))
    XCTAssertTrue(TranscriptionQuality.shouldRejectRecording(duration: 0.29))
  }

  func test_shouldNotReject_atOrAboveMinimum() {
    XCTAssertFalse(TranscriptionQuality.shouldRejectRecording(duration: 0.3))
    XCTAssertFalse(TranscriptionQuality.shouldRejectRecording(duration: 1.0))
  }

  // MARK: isLikelyArtifact — empty / non-letter

  func test_artifact_emptyString() {
    XCTAssertTrue(TranscriptionQuality.isLikelyArtifact("", recordingDuration: 2.0))
  }

  func test_artifact_whitespaceOnly() {
    XCTAssertTrue(TranscriptionQuality.isLikelyArtifact("   \n  ", recordingDuration: 2.0))
  }

  func test_artifact_noLetters() {
    XCTAssertTrue(TranscriptionQuality.isLikelyArtifact("12 . , !", recordingDuration: 2.0))
  }

  // MARK: isLikelyArtifact — short recording, too much text

  func test_artifact_shortRecording_manyWords() {
    // 0.5s but 6 words → hallucination
    XCTAssertTrue(TranscriptionQuality.isLikelyArtifact(
      "one two three four five six", recordingDuration: 0.5))
  }

  func test_artifact_shortRecording_longText() {
    // 0.5s but >= 32 chars
    XCTAssertTrue(TranscriptionQuality.isLikelyArtifact(
      "abcdefghij abcdefghij abcdefghij x", recordingDuration: 0.5))
  }

  func test_ok_shortRecording_fewWords() {
    // 0.5s, 2 short words → plausible
    XCTAssertFalse(TranscriptionQuality.isLikelyArtifact(
      "ja klar", recordingDuration: 0.5))
  }

  // MARK: isLikelyArtifact — medium recording, long text

  func test_artifact_mediumRecording_veryLongText() {
    // 0.7s but >= 56 chars
    let text = String(repeating: "a ", count: 30) // 60 chars
    XCTAssertTrue(TranscriptionQuality.isLikelyArtifact(text, recordingDuration: 0.7))
  }

  func test_ok_longRecording_longText() {
    // 1.5s, long text → legit
    let text = String(repeating: "wort ", count: 40)
    XCTAssertFalse(TranscriptionQuality.isLikelyArtifact(text, recordingDuration: 1.5))
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/Speech && swift test --filter TranscriptionQualityTests`
Expected: FAIL — `cannot find 'TranscriptionQuality' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `Packages/Speech/Sources/TideSpeech/TranscriptionQuality.swift`:

```swift
import Foundation

/// Pure heuristics that decide whether an ASR result should be kept or
/// discarded. Ported from Blitztext's `TranscriptionQualityService`.
///
/// ASR engines (Apple Speech, ElevenLabs Scribe) occasionally emit
/// hallucinated text on very short or silent recordings — a stray
/// "Untertitel…", "Thank you", etc. These checks reject such results
/// before they reach the cursor (dictation) or a chat bubble (PTT).
///
/// Stateless by design: both checks are static and depend only on the
/// transcript text and the recording duration, so they're trivially
/// unit-testable and free of side effects.
public enum TranscriptionQuality {

  /// Recordings shorter than this almost certainly contain no real
  /// speech — a hotkey double-tap or an accidental brush.
  public static let minimumRecordingDuration: TimeInterval = 0.3

  /// True when the recording was too short to contain usable speech.
  public static func shouldRejectRecording(duration: TimeInterval) -> Bool {
    duration < minimumRecordingDuration
  }

  /// True when `text` is likely an ASR hallucination rather than real
  /// transcribed speech, judged against how long the user actually
  /// recorded. The thresholds are deliberately conservative: a short
  /// recording cannot plausibly produce many words or long text.
  public static func isLikelyArtifact(_ text: String, recordingDuration: TimeInterval) -> Bool {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return true }

    let words = cleaned.split { $0.isWhitespace || $0.isNewline }
    let letters = cleaned.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count

    if letters == 0 {
      return true
    }
    if recordingDuration < 0.55 && (words.count >= 5 || cleaned.count >= 32) {
      return true
    }
    if recordingDuration < 0.8 && cleaned.count >= 56 {
      return true
    }
    return false
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/Speech && swift test --filter TranscriptionQualityTests`
Expected: PASS — all 10 tests green

- [ ] **Step 5: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/TranscriptionQuality.swift \
        Packages/Speech/Tests/TideSpeechTests/TranscriptionQualityTests.swift
git commit -m "feat(speech): TranscriptionQuality artifact filter

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `AudioBufferAccumulator.duration`

**Files:**
- Modify: `Tide/Recorder/AudioBufferAccumulator.swift`
- Test: `TideTests/AudioBufferAccumulatorTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `TideTests/AudioBufferAccumulatorTests.swift` (inside the class, before the closing brace):

```swift
  func test_duration_isZero_whenEmpty() {
    let acc = AudioBufferAccumulator()
    XCTAssertEqual(acc.duration, 0, accuracy: 0.0001)
  }

  func test_duration_matchesBufferedFrames() {
    let acc = AudioBufferAccumulator()
    // 500ms at 44100 Hz
    acc.append(makeSineBuffer(sampleRate: 44100, durationMs: 500))
    XCTAssertEqual(acc.duration, 0.5, accuracy: 0.01)
  }

  func test_duration_isZero_afterReset() {
    let acc = AudioBufferAccumulator()
    acc.append(makeSineBuffer(sampleRate: 44100, durationMs: 300))
    acc.reset()
    XCTAssertEqual(acc.duration, 0, accuracy: 0.0001)
  }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/AudioBufferAccumulatorTests 2>&1 | tail -20`
Expected: FAIL — `value of type 'AudioBufferAccumulator' has no member 'duration'`

- [ ] **Step 3: Write minimal implementation**

In `Tide/Recorder/AudioBufferAccumulator.swift`, add right after the `frameCount` computed property (inside the main class body):

```swift
  /// Total recorded time in seconds, derived from the buffered frame
  /// count and the input format's sample rate. Returns 0 when nothing
  /// has been buffered yet (no `inputFormat` captured). Lock-guarded —
  /// callers may read this from the main actor after `stop()` while the
  /// audio thread is already idle, but the lock keeps it consistent if
  /// a stray tap is still draining.
  public var duration: TimeInterval {
    lock.lock()
    defer { lock.unlock() }
    guard let format = inputFormat, format.sampleRate > 0 else { return 0 }
    let frames = chunks.reduce(0) { $0 + $1.frameLength }
    return Double(frames) / format.sampleRate
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/AudioBufferAccumulatorTests 2>&1 | tail -20`
Expected: PASS — duration tests green (alongside existing tests)

- [ ] **Step 5: Commit**

```bash
git add Tide/Recorder/AudioBufferAccumulator.swift TideTests/AudioBufferAccumulatorTests.swift
git commit -m "feat(recorder): AudioBufferAccumulator.duration

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Pille-Flash (`FloatingPill` + `PillViewState`)

No unit test — this is AppKit/SwiftUI view glue verified manually in Task 6's smoke test. Keep the change minimal and obviously correct.

**Files:**
- Modify: `Tide/Dictation/FloatingPill.swift`

- [ ] **Step 1: Add `isHint` to `PillViewState`**

In `Tide/Dictation/FloatingPill.swift`, change the `PillViewState` class body to:

```swift
@MainActor
@Observable
final class PillViewState {
  var partial: String = ""
  /// When true, the pill renders a transient hint (e.g. "Nichts erkannt")
  /// rather than live-recording state: grey dot instead of red, and the
  /// text is shown verbatim with no "Aufnahme…" placeholder fallback.
  var isHint: Bool = false
}
```

- [ ] **Step 2: Update `PillContents` to honour `isHint`**

Replace the `body` of `PillContents` with:

```swift
  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(state.isHint ? Color.secondary : Color.red)
        .frame(width: 8, height: 8)
      Text(displayText)
        .font(.system(size: 12))
        .foregroundStyle(.primary)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
  }

  private var displayText: String {
    if state.isHint { return state.partial }
    return state.partial.isEmpty ? "Aufnahme…" : truncated(state.partial)
  }
```

- [ ] **Step 3: Add `flash()` to `FloatingPill`**

In `FloatingPill`, add after the `show(initialText:)` method:

```swift
  /// Show a transient hint (e.g. "Nichts erkannt") at the configured
  /// corner, then fade out after `duration`. Used when a dictation
  /// session produced no usable transcript. Re-positions and re-shows
  /// the pill even if it was already faded out by a prior `hide()`.
  func flash(_ message: String, duration: TimeInterval = 1.2) {
    viewState.isHint = true
    viewState.partial = message
    repositionForCurrentScreen()
    self.alphaValue = 1.0
    self.orderFrontRegardless()
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
      self?.hide()
      // Reset hint state after the fade so the next live session starts
      // with the red recording dot.
      try? await Task.sleep(nanoseconds: 200_000_000)
      self?.viewState.isHint = false
    }
  }
```

- [ ] **Step 4: Update `show(initialText:)` to clear hint state**

In `show(initialText:)`, add `viewState.isHint = false` as the first line of the method body (so a live session never inherits a leftover hint flag):

```swift
  func show(initialText: String) {
    viewState.isHint = false
    viewState.partial = initialText
    repositionForCurrentScreen()
    self.alphaValue = 1.0
    self.orderFrontRegardless()
  }
```

- [ ] **Step 5: Build to verify it compiles**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add Tide/Dictation/FloatingPill.swift
git commit -m "feat(dictation): FloatingPill.flash for transient hints

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `DictationIndicator.flash` pass-through

**Files:**
- Modify: `Tide/Dictation/DictationIndicator.swift`

- [ ] **Step 1: Add `flash()` method**

In `Tide/Dictation/DictationIndicator.swift`, add after the `hide()` method:

```swift
  /// Show a transient hint on the pill (e.g. after a rejected
  /// recording). The menubar tint is untouched — by the time a reject
  /// is known the coordinator has already called `hide()`, which
  /// deactivated the tint.
  func flash(_ message: String) {
    pill.flash(message)
  }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add Tide/Dictation/DictationIndicator.swift
git commit -m "feat(dictation): DictationIndicator.flash pass-through

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Reject-Guard im `DictationCoordinator`

**Files:**
- Modify: `Tide/Dictation/DictationCoordinator.swift`

- [ ] **Step 1: Replace the empty-transcript guard with the artifact filter**

In `Tide/Dictation/DictationCoordinator.swift`, inside `stop()`, find the block that starts with `let finalText = try await rec.stop()`. Replace the existing guard:

```swift
      let finalText = try await rec.stop()
      let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
      Self.logger.debug("final transcript (mode \(String(describing: self.currentMode), privacy: .public)): '\(trimmed, privacy: .public)'")
      guard !trimmed.isEmpty else {
        // Recognizer returned nothing usable — usually a sub-200ms
        // hold or background noise. Tell the user the hotkey *did*
        // fire so they don't think dictation is broken.
        Self.logger.debug("empty transcript — posting too-short notification")
        await TextInjector.notifyTranscriptTooShort()
        return
      }
```

with:

```swift
      let finalText = try await rec.stop()
      let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
      let duration = rec.bufferAccumulator.duration
      Self.logger.debug("final transcript (mode \(String(describing: self.currentMode), privacy: .public)): '\(trimmed, privacy: .public)' (\(duration, privacy: .public)s)")
      let isReject = trimmed.isEmpty
        || TranscriptionQuality.shouldRejectRecording(duration: duration)
        || TranscriptionQuality.isLikelyArtifact(trimmed, recordingDuration: duration)
      guard !isReject else {
        // Too short / likely a hallucination. Flash a hint on the pill
        // (it was already hidden before the await) instead of inserting
        // garbage at the user's cursor.
        Self.logger.debug("rejected transcript — flashing pill hint")
        indicator?.flash("Nichts erkannt")
        return
      }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

Note: `TextInjector.notifyTranscriptTooShort()` is now unused by the coordinator but stays defined in `TextInjector` — leave it; removing it is out of scope and other call sites may exist.

- [ ] **Step 3: Run the dictation test suites to confirm no regression**

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/DictationPolisherTests 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Tide/Dictation/DictationCoordinator.swift
git commit -m "feat(dictation): reject artifacts before insert

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Reject-Guard im `ChatViewModel` (PTT)

**Files:**
- Modify: `Tide/Panel/ChatViewModel.swift`

- [ ] **Step 1: Add the filter guard in `stopRecording()`**

In `Tide/Panel/ChatViewModel.swift`, inside `stopRecording()`, find:

```swift
    do {
      let finalText = try await recorder.stop()
      let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        input = trimmed
      }
      isRecording = false
      // Dictation mode: when the user has disabled auto-send the
      // transcription just lands in the input field — they can edit
      // and submit manually. Default (true) preserves the original
      // push-to-talk-and-send behavior.
      if !trimmed.isEmpty, settings.autoSendAfterPushToTalk {
        await send()
      }
    } catch {
```

Replace it with:

```swift
    do {
      let finalText = try await recorder.stop()
      let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
      let duration = recorder.bufferAccumulator.duration
      let isReject = trimmed.isEmpty
        || TranscriptionQuality.shouldRejectRecording(duration: duration)
        || TranscriptionQuality.isLikelyArtifact(trimmed, recordingDuration: duration)
      if isReject {
        // Too short / likely a hallucination — silently drop it. No
        // input, no send, no wasted Claude call. The user just sees the
        // empty input field (panel context, so no pill hint needed).
        isRecording = false
      } else {
        input = trimmed
        isRecording = false
        // Dictation mode: when the user has disabled auto-send the
        // transcription just lands in the input field — they can edit
        // and submit manually. Default (true) preserves the original
        // push-to-talk-and-send behavior.
        if settings.autoSendAfterPushToTalk {
          await send()
        }
      }
    } catch {
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Run the full app + package test suites**

Run: `cd Packages/Speech && swift test 2>&1 | tail -10`
Expected: PASS

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' 2>&1 | tail -15`
Expected: `TEST SUCCEEDED`

- [ ] **Step 4: Manual smoke test (Daily-Use verification)**

Build + run the app in Xcode (Cmd+R). Verify:
1. **Diktat reject:** Set a dictation hotkey, tap-and-release it instantly (sub-300ms). Expected: pill flashes „Nichts erkannt" then fades; nothing inserted at cursor.
2. **Diktat normal:** Hold hotkey, speak a sentence, release. Expected: text inserted as before, no hint.
3. **PTT reject:** Open panel, tap-and-release the PTT hotkey instantly. Expected: no bubble appears, no Claude call, input field stays empty.
4. **PTT normal:** Hold, speak, release. Expected: message sends as before.

- [ ] **Step 5: Commit**

```bash
git add Tide/Panel/ChatViewModel.swift
git commit -m "feat(chat): reject artifacts before send in PTT

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add an Unreleased entry**

Add under the top of `CHANGELOG.md` (after the intro block, before `## [0.3.0]`):

```markdown
## [Unreleased]

### Added

- **Artefakt-Filter** — zu kurze Aufnahmen (< 0.3s) und ASR-Halluzinationen
  (viel Text bei kurzer Aufnahme) werden verworfen, bevor sie am Cursor
  (Diktat) oder als Chat-Bubble (PTT) landen. Diktat zeigt einen kurzen
  Pille-Hinweis „Nichts erkannt", der Chat verwirft still. Reine Logik in
  `TranscriptionQuality` (TideSpeech), gespeist von neuer
  `AudioBufferAccumulator.duration`. Portiert aus Blitztext.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for artifact filter

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** `TranscriptionQuality` (T1), `duration` (T2), Pille-Flash (T3+T4), Diktat-Reject (T5), PTT-Reject still (T6) — alle Spec-Abschnitte abgedeckt.
- **Type consistency:** `flash(_:)` / `isHint` / `duration` / `shouldRejectRecording` / `isLikelyArtifact` durchgängig identisch benannt zwischen Tasks.
- **Reject-Logik identisch** in T5 + T6 (DRY-Abweichung bewusst: zwei Consumer, je 3 Zeilen — kein eigenes Helper nötig, würde nur Indirektion ohne Gewinn schaffen).
