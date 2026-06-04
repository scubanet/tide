# Hybrid-Local Recognizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New `.hybridLocal` recognizer — Apple live partials + WhisperKit final — fully offline.

**Architecture:** `HybridRecognizer` is already generic over its secondary recognizer; rename its `eleven` param to `secondary` and feed it a `WhisperKitRecognizer`. Add the `.hybridLocal` choice; `RecognizerFactory` builds it when a local model + transcriber are present, else falls back to Apple (like `.whisperKit`). Picker shows it automatically; prewarm covers it.

**Tech Stack:** Swift 6, XCTest. Package tests via `swift test`; app-target via `xcodebuild … CODE_SIGNING_ALLOWED=NO`.

---

## File Structure

| Datei | Änderung |
|---|---|
| `Packages/Speech/Sources/TideSpeech/Protocols/SpeechRecognizer.swift` | `.hybridLocal` case + displayName + flags |
| `Packages/Speech/Tests/TideSpeechTests/SpeechRecognizerChoiceTests.swift` | `.hybridLocal` asserts |
| `Packages/Speech/Sources/TideSpeech/HybridRecognizer.swift` | `eleven` → `secondary` (param + property + log) |
| `Packages/Speech/Tests/TideSpeechTests/HybridRecognizerTests.swift` | constructor label `eleven:` → `secondary:` |
| `Tide/Dictation/RecognizerFactory.swift` | `.hybridLocal` branch + `.hybrid` label update |
| `TideTests/RecognizerFactoryTests.swift` | `.hybridLocal` branch tests + mock Transcribing |
| `Tide/AppEntry.swift` | prewarm condition includes `.hybridLocal` |
| `CHANGELOG.md` | Unreleased entry |

**Branch:** Vor Task 1: `git checkout -b feat/hybrid-local`

---

## Task 1: `SpeechRecognizerChoice.hybridLocal`

**Files:**
- Modify: `Packages/Speech/Sources/TideSpeech/Protocols/SpeechRecognizer.swift`
- Test: `Packages/Speech/Tests/TideSpeechTests/SpeechRecognizerChoiceTests.swift`

- [ ] **Step 1: Add failing tests**

Append to `SpeechRecognizerChoiceTests` (inside the class):

```swift
  func test_hybridLocal_isInAllCases() {
    XCTAssertTrue(SpeechRecognizerChoice.allCases.contains(.hybridLocal))
  }

  func test_hybridLocal_flags() {
    XCTAssertTrue(SpeechRecognizerChoice.hybridLocal.requiresLocalModel)
    XCTAssertFalse(SpeechRecognizerChoice.hybridLocal.requiresElevenLabsKey)
  }

  func test_hybridLocal_displayName() {
    XCTAssertFalse(SpeechRecognizerChoice.hybridLocal.displayName.isEmpty)
  }
```

- [ ] **Step 2: Run to verify fail**

Run: `cd Packages/Speech && swift test --filter SpeechRecognizerChoiceTests 2>&1 | tail -10`
Expected: FAIL — no member `hybridLocal`.

- [ ] **Step 3: Implement**

In `SpeechRecognizer.swift`, `SpeechRecognizerChoice`:

(a) Add the case after `whisperKit`:
```swift
  case hybridLocal
```
(b) `displayName` switch — add:
```swift
    case .hybridLocal: "Hybrid Lokal (Apple live + WhisperKit final)"
```
(c) `requiresElevenLabsKey` — add `.hybridLocal` to the `false` arm:
```swift
    case .apple, .whisperKit, .hybridLocal:  false
    case .elevenLabs, .hybrid:               true
```
(d) `requiresLocalModel`:
```swift
  public var requiresLocalModel: Bool {
    self == .whisperKit || self == .hybridLocal
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Packages/Speech && swift test --filter SpeechRecognizerChoiceTests 2>&1 | tail -8`
Expected: PASS (existing 4 + 3 new).

- [ ] **Step 5: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/Protocols/SpeechRecognizer.swift \
        Packages/Speech/Tests/TideSpeechTests/SpeechRecognizerChoiceTests.swift
git commit -m "feat(speech): add .hybridLocal recognizer choice

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Generalize `HybridRecognizer` + factory `.hybridLocal` branch

Combined because renaming the `HybridRecognizer` init label breaks the factory's existing `.hybrid` call — both must change together for the app target to build.

**Files:**
- Modify: `Packages/Speech/Sources/TideSpeech/HybridRecognizer.swift`
- Modify: `Packages/Speech/Tests/TideSpeechTests/HybridRecognizerTests.swift`
- Modify: `Tide/Dictation/RecognizerFactory.swift`
- Test: `TideTests/RecognizerFactoryTests.swift`

- [ ] **Step 1: Rename in `HybridRecognizer.swift`**

- Property: `private let eleven: any SpeechRecognizer` → `private let secondary: any SpeechRecognizer`.
- Init: `public init(apple: any SpeechRecognizer, eleven: any SpeechRecognizer)` → `public init(apple: any SpeechRecognizer, secondary: any SpeechRecognizer)`, body `self.eleven = eleven` → `self.secondary = secondary`.
- All other `eleven` references in the body (`eleven.start()`, `eleven.feed(buffer)`, `eleven.stop()`, the `elevenFinal` local + log strings) → `secondary` / `secondaryFinal`. Update the doc-comment and log text from "ElevenLabs" to "secondary".

- [ ] **Step 2: Update `HybridRecognizerTests.swift` constructor calls**

Every `HybridRecognizer(apple: …, eleven: …)` → `HybridRecognizer(apple: …, secondary: …)`. The local stub variable names (e.g. `let eleven = StubRecognizer(...)`) may stay as-is — only the argument label changes. (Assertions/comments referencing ElevenLabs can stay; they describe the secondary role.)

- [ ] **Step 3: Run package tests to verify rename**

Run: `cd Packages/Speech && swift test --filter HybridRecognizerTests 2>&1 | tail -8`
Expected: PASS (rename compiles + logic tests green).

- [ ] **Step 4: Add failing factory tests**

In `TideTests/RecognizerFactoryTests.swift`, add a mock at file scope (after the imports, before or after the test class):

```swift
private actor MockHybridTranscriber: Transcribing {
  func transcribe(wav: Data, language: String?, modelName: String) async throws -> String { "x" }
  func prewarm(modelName: String) async throws {}
}
```

Add tests inside the class:

```swift
  func test_hybridLocal_withModelAndTranscriber_returnsHybrid() {
    let acc = AudioBufferAccumulator()
    let r = RecognizerFactory.make(
      for: .hybridLocal, apiKey: nil, accumulator: acc,
      localModelName: "m", localModelInstalled: true,
      transcriber: MockHybridTranscriber()
    )
    XCTAssertTrue(r is HybridRecognizer)
  }

  func test_hybridLocal_withoutModel_fallsBackToApple() {
    let acc = AudioBufferAccumulator()
    let r = RecognizerFactory.make(
      for: .hybridLocal, apiKey: nil, accumulator: acc,
      localModelName: "m", localModelInstalled: false,
      transcriber: MockHybridTranscriber()
    )
    XCTAssertTrue(r is AppleSpeechRecognizer)
  }

  func test_hybridLocal_withoutTranscriber_fallsBackToApple() {
    let acc = AudioBufferAccumulator()
    let r = RecognizerFactory.make(
      for: .hybridLocal, apiKey: nil, accumulator: acc,
      localModelName: "m", localModelInstalled: true,
      transcriber: nil
    )
    XCTAssertTrue(r is AppleSpeechRecognizer)
  }
```

(`Transcribing`, `HybridRecognizer`, `AppleSpeechRecognizer` come from `import TideSpeech`, already imported in this test file.)

- [ ] **Step 5: Update `RecognizerFactory.make`**

Read `Tide/Dictation/RecognizerFactory.swift` first. Make two changes:

(a) Generalize the local-model early block. Replace the existing `.whisperKit`-only block:
```swift
    if choice == .whisperKit {
      if localModelInstalled, let transcriber {
        return WhisperKitRecognizer(
          transcriber: transcriber,
          modelName: localModelName,
          bufferProvider: { accumulator.exportWAV(sampleRate: 16000, channels: 1) },
          language: nil
        )
      }
      return apple
    }
```
with:
```swift
    if choice == .whisperKit || choice == .hybridLocal {
      guard localModelInstalled, let transcriber else { return apple }
      let whisper = WhisperKitRecognizer(
        transcriber: transcriber,
        modelName: localModelName,
        bufferProvider: { accumulator.exportWAV(sampleRate: 16000, channels: 1) },
        language: nil
      )
      return choice == .hybridLocal
        ? HybridRecognizer(apple: apple, secondary: whisper)
        : whisper
    }
```

(b) In the trailing `switch choice`, update the `.hybrid` arm to the new label and add `.hybridLocal` to the apple-fallback arm:
```swift
    switch choice {
    case .elevenLabs:
      return elevenRecognizer
    case .hybrid:
      return HybridRecognizer(apple: apple, secondary: elevenRecognizer)
    case .apple, .whisperKit, .hybridLocal:
      return apple
    }
```

- [ ] **Step 6: Build + run tests**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/RecognizerFactoryTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -8`
Expected: `TEST SUCCEEDED` (existing 7 + 3 new).

- [ ] **Step 7: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/HybridRecognizer.swift \
        Packages/Speech/Tests/TideSpeechTests/HybridRecognizerTests.swift \
        Tide/Dictation/RecognizerFactory.swift \
        TideTests/RecognizerFactoryTests.swift
git commit -m "feat(dictation): hybrid-local recognizer (Apple live + WhisperKit final)

Generalize HybridRecognizer (eleven -> secondary) and add the
.hybridLocal factory branch with Apple fallback when no local model.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: AppEntry prewarm includes `.hybridLocal`

**Files:** `Tide/AppEntry.swift`

- [ ] **Step 1: Extend the prewarm condition**

Read `Tide/AppEntry.swift`. Find the prewarm block added for WhisperKit:
```swift
        if settings.speechRecognizer == SpeechRecognizerChoice.whisperKit.rawValue,
           localStore.isInstalled(settings.localModelName) {
          let modelName = settings.localModelName
          Task.detached { try? await transcriber.prewarm(modelName: modelName) }
        }
```
Replace the condition so it also covers `.hybridLocal`:
```swift
        let localChoice = SpeechRecognizerChoice(rawValue: settings.speechRecognizer)
        if (localChoice == .whisperKit || localChoice == .hybridLocal),
           localStore.isInstalled(settings.localModelName) {
          let modelName = settings.localModelName
          Task.detached { try? await transcriber.prewarm(modelName: modelName) }
        }
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Tide/AppEntry.swift
git commit -m "feat(app): prewarm local model for hybrid-local too

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: CHANGELOG

**Files:** `CHANGELOG.md`

- [ ] **Step 1: Add to Unreleased → Added**

```markdown
- **Hybrid-Lokal-Recognizer** — neue Recognizer-Wahl „Hybrid Lokal (Apple live
  + WhisperKit final)": Apple liefert sofortige Live-Partials, WhisperKit
  ersetzt am Ende mit der lokalen, offline-genauen Transkription. Kombiniert
  Live-Vorschau mit privater On-Device-Genauigkeit. Fällt auf Apple zurück,
  wenn kein lokales Modell installiert ist.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for hybrid-local recognizer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** choice+flags (T1), HybridRecognizer rename + factory branch + tests (T2), prewarm (T3), changelog (T4). All covered.
- **Type consistency:** `.hybridLocal`, `requiresLocalModel` (now `whisperKit || hybridLocal`), `HybridRecognizer(apple:secondary:)`, factory `localModelInstalled`/`transcriber` params (already exist from WhisperKit wave). Consistent.
- **Coupling (T2):** rename + factory label-update + `.hybridLocal` branch are one task so the app target never sits broken between the rename and the call-site fix.
- **Fallback:** `.hybridLocal` without model/transcriber → Apple, identical to `.whisperKit` — verified by T2 tests.
- **Test command:** app target needs `CODE_SIGNING_ALLOWED=NO`.
```
