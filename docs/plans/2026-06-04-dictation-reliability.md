# Dictation Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the intermittent dictation-paste failure (synthetic ⌘V race) and the audit-found concurrency/lifecycle bugs in the dictation path.

**Architecture:** Selection package gets a robust async ⌘V + AX-trust guard + force-cast guards (one cohesive task — they share the `paste` signature). TideSpeech recognizers/synth get lock + continuation-lifecycle + epoch fixes. Dictation/Recorder/Panel get teardown/interleave/generation-token/retain fixes. No behavior changes beyond reliability.

**Tech Stack:** Swift 6, XCTest. Package tests via `swift test`; app build via `xcodebuild … CODE_SIGNING_ALLOWED=NO`. New app files need `xcodegen generate`.

> Quit any running dev Tide before `xcodebuild test` (the XCTest-guard on main mitigates this, but be safe).

**Branch:** Vor Task 1: `git checkout -b feat/dictation-reliability`

---

## Task 1: Selection — robust ⌘V, AX-guard, force-cast guards

**Files:**
- Modify: `Packages/Selection/Sources/Selection/ClipboardPaste.swift`
- Modify: `Packages/Selection/Sources/Selection/SelectionReplacer.swift`
- Modify: `Packages/Selection/Sources/Selection/SelectionReader.swift`
- Modify: `Packages/Selection/Sources/Selection/TextInjector.swift`
- Test: `Packages/Selection/Tests/SelectionTests/TextInjectorTests.swift` (find exact path; it exists)

### Step 1: Write the failing test (AX-guard)

In `TextInjectorTests.swift`, add (the file already flips `_notificationsEnabled = false` in setUp; mirror that for the new seam):

```swift
  @MainActor
  func test_insert_untrustedAX_fallsBackToPasteboardOnly() async {
    TextInjector._notificationsEnabled = false
    TextInjector._isProcessTrusted = { false }
    TextInjector._frontmostBundleID = { "com.example.other" }   // non-Tide frontmost
    defer {
      TextInjector._isProcessTrusted = { AXIsProcessTrusted() }
      TextInjector._frontmostBundleID = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    }
    let result = await TextInjector.insert("hallo welt")
    XCTAssertEqual(result, .pasteboardOnly)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hallo welt")
  }
```

(Add `import AppKit` / `import ApplicationServices` to the test if not present.)

### Step 2: Run to verify it fails

Run: `cd Packages/Selection && swift test --filter TextInjectorTests 2>&1 | tail -15`
Expected: FAIL — `_isProcessTrusted` doesn't exist (compile) → after adding seam, the assertion fails because strategy-1 currently posts ⌘V and returns `.clipboardPaste`.

### Step 3: `ClipboardPaste.swift` — async robust ⌘V

Replace the file body with:

```swift
import AppKit
import OSLog

private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "selection")

/// Posts a synthetic ⌘V to the frontmost application after dropping
/// `text` on the pasteboard, then restores the prior clipboard later.
public enum ClipboardPaste {
  /// Drop `text` on the pasteboard, post ⌘V (serialized so the ⌘
  /// modifier registers before V), then restore the previous clipboard
  /// after a delay. Returns `false` if the synthetic events could not be
  /// created. `@MainActor` + `async` because it sleeps between events.
  @MainActor
  @discardableResult
  public static func paste(_ text: String) async -> Bool {
    let pasteboard = NSPasteboard.general
    let oldContents = pasteboard.string(forType: .string)
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)

    let ok = await postCommandV()
    log.debug("ClipboardPaste ⌘V posted=\(ok, privacy: .public) (\(text.count, privacy: .public) chars)")

    // Restore after the target app has had time to consume the paste.
    // Electron/WebKit hosts read the pasteboard asynchronously; 800ms is
    // comfortably past their read window.
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 800_000_000)
      pasteboard.clearContents()
      if let old = oldContents { pasteboard.setString(old, forType: .string) }
    }
    return ok
  }

  /// Post ⌘V as four events with a small inter-event gap so the ⌘
  /// modifier is registered before V (a no-gap burst races and lands as
  /// a bare "v" or nothing, worse in optimized release builds). The
  /// `.maskCommand` flag is stamped on the modifier-down + both V events.
  @MainActor
  private static func postCommandV() async -> Bool {
    let source = CGEventSource(stateID: .combinedSessionState)
    let cmdKey: CGKeyCode = 0x37
    let vKey: CGKeyCode = 0x09
    guard
      let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true),
      let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
      let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false),
      let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)
    else {
      log.error("postCommandV: CGEvent creation failed")
      return false
    }
    cmdDown.flags = .maskCommand
    vDown.flags = .maskCommand
    vUp.flags = .maskCommand
    cmdUp.flags = []

    let gap: UInt64 = 8_000_000  // 8ms
    cmdDown.post(tap: .cghidEventTap)
    try? await Task.sleep(nanoseconds: gap)
    vDown.post(tap: .cghidEventTap)
    try? await Task.sleep(nanoseconds: gap)
    vUp.post(tap: .cghidEventTap)
    try? await Task.sleep(nanoseconds: gap)
    cmdUp.post(tap: .cghidEventTap)
    return true
  }
}
```

### Step 4: `SelectionReplacer.swift` — keep sync API, spawn Task

```swift
import AppKit

/// Writes text back into the previous app's selection via `ClipboardPaste`.
public enum SelectionReplacer {
  /// Replaces the frontmost app's selection with `text`. Fire-and-forget:
  /// the async paste runs on the main actor; the result isn't awaited
  /// (replacement is best-effort and restores the clipboard either way).
  /// Caller must yield focus (e.g. `NSApp.hide`) first.
  @MainActor
  public static func replaceSelection(with newText: String) {
    Task { @MainActor in _ = await ClipboardPaste.paste(newText) }
  }
}
```

(If `replaceSelection`'s caller in `MessageList.swift` isn't already on the main actor, the `@MainActor` annotation may require the call site to be in a `@MainActor` context — it is, it's a SwiftUI button action. If the build complains, wrap the call site in `Task { @MainActor in … }` instead of annotating here.)

### Step 5: `SelectionReader.swift` — ⌘C hardening + force-cast guard

(a) Replace the `readViaAX` force-cast:
```swift
    guard focusStatus == .success, let focused = focused else { return nil }
    let focusedElement = focused as! AXUIElement
```
with:
```swift
    guard focusStatus == .success, let focused,
          CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
    let focusedElement = focused as! AXUIElement
```

(b) Replace `sendCommandC()` body with the gap+flag hardened version:
```swift
  private static func sendCommandC() {
    let source = CGEventSource(stateID: .combinedSessionState)
    let cKey: CGKeyCode = 0x08
    let cmdKey: CGKeyCode = 0x37
    guard
      let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true),
      let cDown = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true),
      let cUp = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false),
      let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)
    else { return }
    cmdDown.flags = .maskCommand
    cDown.flags = .maskCommand
    cUp.flags = .maskCommand
    cmdUp.flags = []
    cmdDown.post(tap: .cghidEventTap)
    usleep(8_000)
    cDown.post(tap: .cghidEventTap)
    usleep(8_000)
    cUp.post(tap: .cghidEventTap)
    usleep(8_000)
    cmdUp.post(tap: .cghidEventTap)
  }
```

### Step 6: `TextInjector.swift` — AX-trust guard + force-cast guard + await paste

(a) Add the test seam near `_notificationsEnabled`:
```swift
  /// Test seam — overridable in unit tests. Default reads the real AX
  /// trust state. `nonisolated(unsafe)`: only read/written on the main
  /// actor (insert is `@MainActor`, tests run `@MainActor`).
  nonisolated(unsafe) static var _isProcessTrusted: () -> Bool = { AXIsProcessTrusted() }
```

(b) In `insert(_:)`, change strategy 1 so it guards AX trust and awaits the now-async paste. Replace:
```swift
    if let front = frontBundle, front != tideBundle {
      ClipboardPaste.paste(trimmed)
      log.debug("insert via clipboard-paste into \(front, privacy: .public) (\(trimmed.count, privacy: .public) chars)")
      return .clipboardPaste
    }
```
with:
```swift
    if let front = frontBundle, front != tideBundle {
      // ⌘V is delivered via CGEvent, which requires Accessibility trust.
      // Untrusted → the keystroke is silently dropped, so don't claim
      // success: fall through to pasteboard-only + a notification.
      if _isProcessTrusted(), await ClipboardPaste.paste(trimmed) {
        log.debug("insert via clipboard-paste into \(front, privacy: .public) (\(trimmed.count, privacy: .public) chars)")
        return .clipboardPaste
      }
      log.debug("insert: AX untrusted or ⌘V failed — pasteboard-only fallback")
      // fall through to strategy 3 below
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(trimmed, forType: .string)
      await postPasteboardNotification()
      return .pasteboardOnly
    }
```

(c) Replace the AX force-cast in `attemptAXInsert`:
```swift
    guard focusStatus == .success, let focused = focused else {
      log.debug("AX-Insert: no focused element")
      return false
    }
    let element = focused as! AXUIElement
```
with:
```swift
    guard focusStatus == .success, let focused,
          CFGetTypeID(focused) == AXUIElementGetTypeID() else {
      log.debug("AX-Insert: no focused element")
      return false
    }
    let element = focused as! AXUIElement
```

### Step 7: Run tests + build the package

Run: `cd Packages/Selection && swift test 2>&1 | tail -12`
Expected: PASS incl. the new `test_insert_untrustedAX_fallsBackToPasteboardOnly` + existing TextInjectorTests.

### Step 8: Commit

```bash
git add Packages/Selection/Sources/Selection/ClipboardPaste.swift \
        Packages/Selection/Sources/Selection/SelectionReplacer.swift \
        Packages/Selection/Sources/Selection/SelectionReader.swift \
        Packages/Selection/Sources/Selection/TextInjector.swift \
        Packages/Selection/Tests/SelectionTests/TextInjectorTests.swift
git commit -m "fix(selection): robust synthetic Cmd-V/Cmd-C + AX-trust guard + force-cast guards

Serialize the synthetic keystroke with .maskCommand flags + 8ms gaps so
the modifier registers before the key (fixes intermittent paste, worse in
release builds). Guard AXIsProcessTrusted before posting Cmd-V (no false
success when untrusted → pasteboard-only + notification). Type-check the
AX focused element before force-casting. Lengthen the clipboard restore
to 800ms.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `AppleSpeechRecognizer` — lock + continuation lifecycle

**Files:** `Packages/Speech/Sources/TideSpeech/Apple/AppleSpeechRecognizer.swift`

No unit test (SFSpeechRecognizer is a system service); build-verified.

- [ ] **Step 1: Add a lock + per-start stream + finish on stop**

Read the file first. Apply:

(a) Add `private let lock = NSLock()`. Make `request`, `task`, `lastFinalTranscript` accessed only under the lock. The `partialTranscript`/`partialContinuation` must be re-created per `start()`, so change them from `let` to `var` and from init-created to start-created:

```swift
  private var partialContinuation: AsyncStream<String>.Continuation?
  public var partialTranscript: AsyncStream<String> {
    lock.lock(); defer { lock.unlock() }
    if let existing = _stream { return existing }
    let stream = AsyncStream<String> { cont in
      self.partialContinuation = cont
    }
    _stream = stream
    return stream
  }
  private var _stream: AsyncStream<String>?
```

NOTE: the protocol exposes `partialTranscript` as a computed stream; consumers call it AFTER `start()`. Simplest robust approach: in `start()`, create a fresh stream+continuation and store both; have `partialTranscript` return the current stored stream. Implement so that:
- `start()` (under lock): builds a new `AsyncStream` + stores its continuation in `partialContinuation` and the stream in `_stream`; resets `lastFinalTranscript = ""`.
- The recognitionTask callback updates `lastFinalTranscript` + yields `partialContinuation?.yield(text)` all under the lock.
- `stop()` (under lock): `request?.endAudio()`, `task?.finish()`, capture `lastFinalTranscript`, `partialContinuation?.finish()`, nil out `task`/`request`/`partialContinuation`. Return the captured final after the existing 200ms settle sleep.
- `feed(_:)`: `lock.lock(); let r = request; lock.unlock(); r?.append(buffer)`.

If reworking `partialTranscript` to be created in `start()` while the protocol requires it readable any time is awkward, keep a single lazily-created stream but ALWAYS `finish()` it in `stop()` and recreate on the next `start()`. The key invariants: (1) all mutable state under the lock, (2) `partialContinuation.finish()` called in `stop()`, (3) a second start/stop cycle yields into a live (recreated) stream, never a finished one.

- [ ] **Step 2: Build**

Run: `cd Packages/Speech && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Run the speech package tests (no regression)**

Run: `cd Packages/Speech && swift test --filter HybridRecognizerTests 2>&1 | tail -6`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/Apple/AppleSpeechRecognizer.swift
git commit -m "fix(speech): AppleSpeechRecognizer lock + continuation lifecycle

Synchronize request/task/lastFinalTranscript behind an NSLock (the
recognitionTask callback runs on a Speech queue, racing the caller),
finish the partial-transcript continuation in stop(), and recreate the
stream per start() so the reusable-recognizer contract holds.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `HybridRecognizer` — cancel forwardTask early + lock

**Files:** `Packages/Speech/Sources/TideSpeech/HybridRecognizer.swift`

- [ ] **Step 1: Apply**

Add `private let lock = NSLock()`. Guard `forwardTask` reads/writes with the lock. In `stop()`, cancel + nil `forwardTask` **before** awaiting `apple.stop()`/`secondary.stop()`:

```swift
  public func stop() async throws -> String {
    lock.lock()
    forwardTask?.cancel()
    forwardTask = nil
    lock.unlock()

    let appleFinal = (try? await apple.stop()) ?? ""
    let secondaryFinal = (try? await secondary.stop()) ?? ""
    partialContinuation.finish()

    if secondaryFinal.isEmpty {
      Self.logger.debug("Hybrid: secondary returned empty, keeping Apple result.")
      return appleFinal
    }
    Self.logger.debug("Hybrid: replacing Apple (\(appleFinal.count) chars) with secondary (\(secondaryFinal.count) chars).")
    return secondaryFinal
  }
```

In `start()`, set `forwardTask` under the lock. (Recreate the partial stream per start is out of scope here — B1's Apple finish() lets the forward loop terminate; this task only fixes the forwardTask race + early cancel.)

- [ ] **Step 2: Build + test**

Run: `cd Packages/Speech && swift test --filter HybridRecognizerTests 2>&1 | tail -6`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/HybridRecognizer.swift
git commit -m "fix(speech): HybridRecognizer cancel forwardTask early + lock it

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `ElevenLabsSynthesizer` — generation/epoch token

**Files:** `Packages/Speech/Sources/TideSpeech/ElevenLabs/ElevenLabsSynthesizer.swift`

- [ ] **Step 1: Apply**

Add `private var generation: Int = 0`. Capture it in `speak()` alongside `seq`; pass it through to `deliver`/`skip`; drop stale arrivals.

(a) In `speak()`, under the existing lock add `let gen = generation` (next to `let seq = nextSequence`). Pass `gen` into the Task’s `deliver`/`skip` calls:
```swift
        await MainActor.run { self.deliver(gen: gen, seq: seq, data: data) }
        …
        await MainActor.run { self.skip(gen: gen, seq: seq) }
```

(b) In `stop()`, bump the generation instead of relying on the counter reset alone:
```swift
    lock.lock()
    generation += 1
    audioQueue.removeAll()
    pendingAudio.removeAll()
    nextSequence = 0
    nextToEnqueue = 0
    currentPlayer?.stop()
    currentPlayer = nil
    lock.unlock()
```

(c) `deliver`/`skip` gain a `gen:` param and drop stale deliveries first:
```swift
  @MainActor
  private func deliver(gen: Int, seq: Int, data: Data) {
    lock.lock()
    guard gen == generation else { lock.unlock(); return }   // stale cycle
    pendingAudio[seq] = data
    …
```
(same `guard gen == generation` at the top of `skip`, after `lock.lock()`).

- [ ] **Step 2: Build**

Run: `cd Packages/Speech && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/ElevenLabs/ElevenLabsSynthesizer.swift
git commit -m "fix(speech): ElevenLabsSynthesizer epoch token drops stale TTS arrivals

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `AudioRecorder.start` — teardown on failure

**Files:** `Tide/Recorder/AudioRecorder.swift`

- [ ] **Step 1: Apply**

Read the file. Reorder so the input-format validation happens BEFORE `recognizer.start()`, and wrap tap-install + engine-start so a throw tears down the tap + recognizer:

```swift
  func start() async throws {
    guard !isRunning else { return }
    bufferAccumulator.reset()

    // Validate the input format BEFORE starting the recognizer, so a bad
    // format doesn't leak a started recognizer.
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw NSError(domain: "Tide.AudioRecorder", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Audio input not available (0 sample rate). Check mic permission."])
    }

    try await recognizer.start()

    do {
      let capturedRecognizer = recognizer
      let capturedAccumulator = bufferAccumulator
      let block: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { [capturedRecognizer, capturedAccumulator] buffer, _ in
        capturedAccumulator.append(buffer)
        capturedRecognizer.feed(buffer)
      }
      input.installTap(onBus: 0, bufferSize: 1024, format: format, block: block)
      engine.prepare()
      try engine.start()
      isRunning = true
    } catch {
      // Roll back: remove the tap we installed and stop the recognizer we
      // already started, so a failed start() leaks nothing.
      engine.inputNode.removeTap(onBus: 0)
      _ = try? await recognizer.stop()
      throw error
    }
  }
```

(Keep the existing `log.debug` lines if desired; the structure above is what matters. Match the existing `stop()` unchanged.)

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Tide/Recorder/AudioRecorder.swift
git commit -m "fix(recorder): tear down tap + recognizer when engine.start fails

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: `DictationCoordinator.start` — interleave guard

**Files:** `Tide/Dictation/DictationCoordinator.swift`

- [ ] **Step 1: Apply**

In `start(mode:)`, after `try await rec.start()` succeeds, verify this session is still current before showing the indicator / starting the partial task. Replace the success block:

```swift
    do {
      try await rec.start()
      // A stop() may have fired during the await (fast tap), nilling
      // `recorder`. If so, this session is stale — tear it down instead of
      // leaving a running engine with no way to stop it.
      guard self.recorder === rec else {
        Self.logger.debug("start: session superseded during await — tearing down")
        _ = try? await rec.stop()
        return
      }
      Self.logger.debug("recording started (mode: \(String(describing: mode), privacy: .public))")
      indicator?.show()
      let partials = rec.partialTranscript
      partialTask = Task { [weak self] in
        for await partial in partials {
          guard !Task.isCancelled else { return }
          await MainActor.run { self?.indicator?.update(partial: partial) }
        }
      }
    } catch {
      Self.logger.error("AudioRecorder.start failed: \(error.localizedDescription, privacy: .public)")
      self.recorder = nil
    }
```

(`AudioRecorder` is a reference type, so `===` identity works. Confirm `recorder` is a `var` of `AudioRecorder?`.)

- [ ] **Step 2: Build**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Tide/Dictation/DictationCoordinator.swift
git commit -m "fix(dictation): guard against start/stop interleave (stuck recording)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: `FloatingPill` — generation token for cleanup tasks

**Files:** `Tide/Dictation/FloatingPill.swift`

- [ ] **Step 1: Apply**

Read the file. Add `private var generation = 0` and a stored cleanup task `private var cleanupTask: Task<Void, Never>?`. Every `show`/`flash`/`hide` bumps `generation`, cancels `cleanupTask`, and the delayed bodies capture the bumped value and no-op if it's stale.

- `show(initialText:)`: at top, `generation += 1; cleanupTask?.cancel()`.
- `hide()`: capture `let gen = (generation += 1, generation).1`-style — concretely:
```swift
  func hide() {
    generation += 1
    let gen = generation
    cleanupTask?.cancel()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      self.animator().alphaValue = 0.0
    }
    cleanupTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 160_000_000)
      guard let self, self.generation == gen else { return }
      self.orderOut(nil)
    }
  }
```
- `flash(_:duration:)`: same pattern — bump generation, capture `gen`, cancel prior `cleanupTask`, and in the delayed body guard `self.generation == gen` before `hide()`/`isHint = false`. Store the task in `cleanupTask`.

The invariant: a newer `show/flash/hide` always invalidates any pending delayed body, so a flash's fade/`isHint`-reset can never order-out or clobber a freshly-shown recording pill.

- [ ] **Step 2: Build**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Tide/Dictation/FloatingPill.swift
git commit -m "fix(dictation): FloatingPill generation token cancels stale cleanup tasks

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: `ChatViewModel.startRecording` — don't retain the recorder

**Files:** `Tide/Panel/ChatViewModel.swift`

- [ ] **Step 1: Apply**

In `startRecording()`, bind the stream before the Task and iterate that (so the Task doesn't strongly capture `recorder`); in the catch, cancel the task before nilling and clear `liveTranscript`. Replace the partial-task + catch:

```swift
    let stream = recorder.partialTranscript
    partialTask = Task { [weak self] in
      for await partial in stream {
        self?.liveTranscript = partial
      }
    }

    do {
      try await recorder.start()
    } catch {
      isRecording = false
      partialTask?.cancel()
      self.recorder = nil
      liveTranscript = ""
    }
```

(The class is `@MainActor`, so `for await` resumes on the main actor — the inner `await MainActor.run { … }` is removed.)

- [ ] **Step 2: Build**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Tide/Panel/ChatViewModel.swift
git commit -m "fix(chat): bind partial-transcript stream instead of retaining recorder

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: CHANGELOG

**Files:** `CHANGELOG.md`

- [ ] **Step 1:** Under `## [Unreleased]` → add a `### Fixed`:

```markdown
### Fixed

- **Diktat-Paste zuverlässig** — das synthetische ⌘V wurde gehärtet (Modifier-
  Flag + Inter-Event-Gaps), sodass der Text nicht mehr intermittierend „im
  Nirvana" verschwindet (vor allem im Release-Build). Fehlt das
  Bedienungshilfen-Recht, landet der Text sichtbar in der Zwischenablage mit
  Hinweis statt stillem Fehlschlag.
- **Diktat-Concurrency** — Daten-Race in `AppleSpeechRecognizer`, steckenge-
  bliebene Aufnahmen bei schnellem Hotkey-Tap, Recorder-Leak bei Start-Fehler,
  Pillen-Flacker-Races, ElevenLabs-TTS-Reihenfolge und ein Recorder-Retain im
  Panel-Pfad behoben (aus dem App-Audit).
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for dictation reliability wave

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** A1-A4 (T1), B1 (T2), B2 (T3), B3 (T4), C1 (T5), C2 (T6), C3 (T7), C4 (T8), changelog (T9). All covered.
- **Coupling:** all Selection paste-signature changes are in T1 (one task) so the package never sits broken. B1's Apple `finish()` is what lets B2's forward loop terminate — T2 before T3.
- **Test seam:** `TextInjector._isProcessTrusted` mirrors the existing `_frontmostBundleID`/`_notificationsEnabled` seams; the AX-guard path is unit-tested.
- **Async ripple:** `ClipboardPaste.paste` → async is absorbed by `TextInjector.insert` (already async, awaits) and `SelectionReplacer` (sync API, spawns a Task) — no MessageList change.
- **Quality gate:** after the concurrency tasks (T2-T4, T6-T8), the controller runs a `swift-concurrency-pro` review.
- **Verification:** package tests + app build green per task; the decisive check is the manual smoke (10× dictation, no flake/stuck).
