# Custom Vocabulary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** User-pflegbare Begriffsliste, die die Apple-Erkennung biast (A) und im Polish-Schritt an Claude geht (B), damit Jargon (PADI, SeaExplorers, …) korrekt transkribiert wird.

**Architecture:** `AppSettings.customVocabulary: [String]` (Core, UserDefaults). Mechanismus A: `AppleSpeechRecognizer.contextualStrings`, durchgereicht via `RecognizerFactory.vocabulary`-Param von beiden Call-Sites. Mechanismus B: `DictationPolisher` hängt die Begriffe an den System-Prompt. UI: neuer Settings-Tab „Vokabular".

**Tech Stack:** Swift, XCTest, Speech.framework, SwiftUI. Package-Tests via `swift test`; App-Target-Tests via `xcodebuild test … CODE_SIGNING_ALLOWED=NO` (das `TideTests`-Target code-signt sonst und failt — gelernt in Welle Artefakt-Filter).

---

## File Structure

| Datei | Verantwortung |
|---|---|
| `Packages/Core/Sources/Core/Settings/AppSettings.swift` | + `customVocabulary` Property + Key |
| `Packages/Core/Tests/CoreTests/AppSettingsTests.swift` | Vocab round-trip / parsing tests |
| `Packages/Speech/Sources/TideSpeech/Apple/AppleSpeechRecognizer.swift` | + `contextualStrings` init-Param |
| `Tide/Dictation/RecognizerFactory.swift` | + `vocabulary` Param, an Apple durchreichen |
| `Tide/Dictation/DictationPolisher.swift` | Vocab-Suffix im System-Prompt |
| `TideTests/DictationPolisherTests.swift` | Vocab-Injektion / no-vocab tests |
| `Tide/Dictation/DictationCoordinator.swift` | `settings.customVocabulary` an Factory |
| `Tide/Panel/ChatViewModel.swift` | `settings.customVocabulary` an Factory |
| `Tide/Settings/VocabularySection.swift` | **neu** — Listen-Editor |
| `Tide/Settings/SettingsWindow.swift` | Tab einhängen |

**Branch:** Vor Task 1: `git checkout -b feat/custom-vocabulary`

---

## Task 1: `AppSettings.customVocabulary`

**Files:**
- Modify: `Packages/Core/Sources/Core/Settings/AppSettings.swift`
- Test: `Packages/Core/Tests/CoreTests/AppSettingsTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Packages/Core/Tests/CoreTests/AppSettingsTests.swift` inside the class (before closing brace):

```swift
  @MainActor
  func testCustomVocabularyDefaultsEmpty() {
    let s = AppSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    XCTAssertEqual(s.customVocabulary, [])
  }

  @MainActor
  func testCustomVocabularyRoundTrip() {
    let suite = "test.\(UUID().uuidString)"
    let defs = UserDefaults(suiteName: suite)!
    let s = AppSettings(defaults: defs)
    s.customVocabulary = ["PADI", "Nitrox"]
    let reloaded = AppSettings(defaults: defs)
    XCTAssertEqual(reloaded.customVocabulary, ["PADI", "Nitrox"])
  }

  @MainActor
  func testCustomVocabularyTrimsAndDropsBlankLines() {
    let suite = "test.\(UUID().uuidString)"
    let defs = UserDefaults(suiteName: suite)!
    // Simulate a raw multiline string with blank lines and padding.
    defs.set("PADI\n\n  Nitrox  \n\n", forKey: "tide.customVocabulary")
    let s = AppSettings(defaults: defs)
    XCTAssertEqual(s.customVocabulary, ["PADI", "Nitrox"])
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/Core && swift test --filter AppSettingsTests 2>&1 | tail -15`
Expected: FAIL — `value of type 'AppSettings' has no member 'customVocabulary'`

- [ ] **Step 3: Implement**

In `Packages/Core/Sources/Core/Settings/AppSettings.swift`, add to the `Key` enum (after `dictationPillPosition`):

```swift
    static let customVocabulary = "tide.customVocabulary"
```

Then add this computed property after the `dictationPillPosition` property (or at the end of the class, before the closing brace):

```swift
  /// User-maintained domain terms (e.g. "PADI", "SeaExplorers") that bias
  /// the Apple speech recognizer and are injected into the polish prompt.
  /// Persisted as a newline-joined string; the getter normalises it into a
  /// trimmed, blank-free list so consumers never see empty entries.
  public var customVocabulary: [String] {
    get {
      (defaults.string(forKey: Key.customVocabulary) ?? "")
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    }
    set {
      defaults.set(newValue.joined(separator: "\n"), forKey: Key.customVocabulary)
    }
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/Core && swift test --filter AppSettingsTests 2>&1 | tail -8`
Expected: PASS (incl. 3 new tests)

- [ ] **Step 5: Commit**

```bash
git add Packages/Core/Sources/Core/Settings/AppSettings.swift \
        Packages/Core/Tests/CoreTests/AppSettingsTests.swift
git commit -m "feat(core): AppSettings.customVocabulary

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `AppleSpeechRecognizer.contextualStrings`

**Files:**
- Modify: `Packages/Speech/Sources/TideSpeech/Apple/AppleSpeechRecognizer.swift`

No unit test — `SFSpeechRecognizer` is a non-mockable system service. Verified by build + the existing `SpeechTests` compile-conformance check.

- [ ] **Step 1: Add a stored `contextualStrings` property + init param**

In `AppleSpeechRecognizer`, add a stored property near the other `private var`s:

```swift
  private let contextualStrings: [String]
```

Change the initializer signature and body. Current:

```swift
  public init(locale: Locale = Locale(identifier: "de-DE")) {
    guard let recognizer = SFSpeechRecognizer(locale: locale) else {
      fatalError("SFSpeechRecognizer unavailable for locale \(locale.identifier)")
    }
    self.recognizer = recognizer
    var continuation: AsyncStream<String>.Continuation!
    self.partialTranscript = AsyncStream<String> { continuation = $0 }
    self.partialContinuation = continuation
  }
```

Replace with:

```swift
  public init(
    locale: Locale = Locale(identifier: "de-DE"),
    contextualStrings: [String] = []
  ) {
    guard let recognizer = SFSpeechRecognizer(locale: locale) else {
      fatalError("SFSpeechRecognizer unavailable for locale \(locale.identifier)")
    }
    self.recognizer = recognizer
    self.contextualStrings = contextualStrings
    var continuation: AsyncStream<String>.Continuation!
    self.partialTranscript = AsyncStream<String> { continuation = $0 }
    self.partialContinuation = continuation
  }
```

- [ ] **Step 2: Apply the contextual strings to the request**

In `start()`, find:

```swift
    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
```

Add immediately after:

```swift
    // Bias recognition toward user-supplied domain terms (names, jargon).
    // Empty array is a harmless no-op.
    req.contextualStrings = contextualStrings
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd Packages/Speech && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/Speech/Sources/TideSpeech/Apple/AppleSpeechRecognizer.swift
git commit -m "feat(speech): AppleSpeechRecognizer contextualStrings bias

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `RecognizerFactory.vocabulary` + call sites

**Files:**
- Modify: `Tide/Dictation/RecognizerFactory.swift`
- Modify: `Tide/Dictation/DictationCoordinator.swift`
- Modify: `Tide/Panel/ChatViewModel.swift`

- [ ] **Step 1: Add the `vocabulary` parameter to the factory**

In `Tide/Dictation/RecognizerFactory.swift`, change the `make` signature. Current:

```swift
  static func make(
    for choice: SpeechRecognizerChoice,
    apiKey: String?,
    accumulator: AudioBufferAccumulator
  ) -> any SpeechRecognizer {
    let apple = AppleSpeechRecognizer()
```

Replace with:

```swift
  static func make(
    for choice: SpeechRecognizerChoice,
    apiKey: String?,
    accumulator: AudioBufferAccumulator,
    vocabulary: [String] = []
  ) -> any SpeechRecognizer {
    let apple = AppleSpeechRecognizer(contextualStrings: vocabulary)
```

(The default `[]` keeps `RecognizerFactoryTests` compiling unchanged.)

- [ ] **Step 2: Pass vocabulary from `DictationCoordinator.start`**

In `Tide/Dictation/DictationCoordinator.swift`, find the `RecognizerFactory.make` call in `start()`:

```swift
    let recognizer = RecognizerFactory.make(
      for: choice,
      apiKey: apiKey,
      accumulator: accumulator
    )
```

Replace with:

```swift
    let recognizer = RecognizerFactory.make(
      for: choice,
      apiKey: apiKey,
      accumulator: accumulator,
      vocabulary: settings.customVocabulary
    )
```

- [ ] **Step 3: Pass vocabulary from `ChatViewModel.startRecording`**

In `Tide/Panel/ChatViewModel.swift`, find the `RecognizerFactory.make` call in `startRecording()`:

```swift
    let recognizer = RecognizerFactory.make(
      for: choice,
      apiKey: apiKey,
      accumulator: accumulator
    )
```

Replace with:

```swift
    let recognizer = RecognizerFactory.make(
      for: choice,
      apiKey: apiKey,
      accumulator: accumulator,
      vocabulary: settings.customVocabulary
    )
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add Tide/Dictation/RecognizerFactory.swift Tide/Dictation/DictationCoordinator.swift Tide/Panel/ChatViewModel.swift
git commit -m "feat(dictation): wire customVocabulary into recognizer bias

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `DictationPolisher` vocab injection

**Files:**
- Modify: `Tide/Dictation/DictationPolisher.swift`
- Test: `TideTests/DictationPolisherTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `TideTests/DictationPolisherTests.swift` inside the class (before the closing brace, after the existing wiring-assertion tests):

```swift
  func test_polish_appendsVocabularyToSystemPrompt() async throws {
    settings.dictationPolishPrompt = "BASE PROMPT"
    settings.customVocabulary = ["PADI", "SeaExplorers"]
    let stub = StubProvider(chunks: ["ok"])
    let polisher = DictationPolisher(
      provider: stub,
      settings: settings,
      timeoutSeconds: 2
    )
    _ = try await polisher.polish("raw")
    let prompt = try XCTUnwrap(stub.lastSystemPrompt)
    XCTAssertTrue(prompt.hasPrefix("BASE PROMPT"))
    XCTAssertTrue(prompt.contains("PADI"))
    XCTAssertTrue(prompt.contains("SeaExplorers"))
  }

  func test_polish_leavesSystemPromptUnchanged_whenNoVocabulary() async throws {
    settings.dictationPolishPrompt = "BASE PROMPT"
    // customVocabulary defaults to empty.
    let stub = StubProvider(chunks: ["ok"])
    let polisher = DictationPolisher(
      provider: stub,
      settings: settings,
      timeoutSeconds: 2
    )
    _ = try await polisher.polish("raw")
    XCTAssertEqual(stub.lastSystemPrompt, "BASE PROMPT")
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/DictationPolisherTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15`
Expected: FAIL — `test_polish_appendsVocabularyToSystemPrompt` fails (vocab not in prompt). `test_polish_leavesSystemPromptUnchanged_whenNoVocabulary` should already pass.

- [ ] **Step 3: Implement the vocab suffix**

In `Tide/Dictation/DictationPolisher.swift`, inside `polish(_:)`, find:

```swift
    let systemPrompt = settings.dictationPolishPrompt
    let userMessage = LLMMessage(role: .user, content: raw)
```

Replace the first line with a built prompt:

```swift
    let systemPrompt = Self.systemPrompt(
      base: settings.dictationPolishPrompt,
      vocabulary: settings.customVocabulary
    )
    let userMessage = LLMMessage(role: .user, content: raw)
```

Add this static helper to the `DictationPolisher` class (e.g. right after the `polish` method):

```swift
  /// Build the polish system prompt. When the user has domain terms,
  /// append a single instruction line so Claude spells jargon correctly;
  /// an empty vocabulary returns `base` unchanged.
  static func systemPrompt(base: String, vocabulary: [String]) -> String {
    guard !vocabulary.isEmpty else { return base }
    let terms = vocabulary.joined(separator: ", ")
    return base
      + "\n\nDomain terms that may appear in the text — spell them exactly "
      + "as written, correcting any phonetic mis-transcription: \(terms)"
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/DictationPolisherTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -8`
Expected: `TEST SUCCEEDED` — all DictationPolisherTests pass (incl. 2 new).

- [ ] **Step 5: Commit**

```bash
git add Tide/Dictation/DictationPolisher.swift TideTests/DictationPolisherTests.swift
git commit -m "feat(dictation): inject custom vocabulary into polish prompt

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `VocabularySection` UI + Settings tab

**Files:**
- Create: `Tide/Settings/VocabularySection.swift`
- Modify: `Tide/Settings/SettingsWindow.swift`

No unit test — SwiftUI view glue, verified by build + manual smoke test.

- [ ] **Step 1: Create the VocabularySection view**

Create `Tide/Settings/VocabularySection.swift`:

```swift
import SwiftUI
import Core

/// Settings tab for the custom vocabulary (Tide custom-vocabulary wave).
///
/// Domain terms entered here bias the Apple speech recognizer
/// (`contextualStrings`) and are injected into the polished-dictation
/// system prompt so Claude spells jargon (PADI, SeaExplorers, …)
/// correctly. The list is mirrored into local `@State` and written back
/// to `AppSettings.customVocabulary` on every change — same pattern as
/// `DictationSection`'s prompt mirror.
struct VocabularySection: View {
  @State private var settings = AppSettings()
  @State private var terms: [String] = []
  @State private var newTerm: String = ""

  /// Above this count we surface a soft warning — Apple recommends fewer
  /// than 100 contextual strings, and very long lists can degrade
  /// recognition. Not a hard cap.
  private static let softLimit = 50

  var body: some View {
    Form {
      Section {
        Text("Begriffe (Namen, Fachjargon), die Tide korrekt erkennen und "
          + "schreiben soll. Beeinflusst die Apple-Erkennung und den "
          + "Polish-Schritt.")
          .font(.caption)
          .foregroundStyle(.secondary)

        if terms.isEmpty {
          Text("Noch keine Begriffe.")
            .font(.caption)
            .foregroundStyle(.tertiary)
        } else {
          List {
            ForEach(terms, id: \.self) { term in
              Text(term)
            }
            .onDelete { offsets in
              terms.remove(atOffsets: offsets)
              settings.customVocabulary = terms
            }
          }
          .frame(minHeight: 120)
        }

        HStack {
          TextField("Begriff hinzufügen", text: $newTerm)
            .textFieldStyle(.roundedBorder)
            .onSubmit(addTerm)
          Button("Hinzufügen", action: addTerm)
            .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        if terms.count > Self.softLimit {
          Text("Apple empfiehlt unter 100 Begriffe; sehr lange Listen "
            + "können die Erkennung verschlechtern.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } header: { Text("Vokabular") }
    }
    .formStyle(.grouped)
    .task {
      terms = settings.customVocabulary
    }
  }

  private func addTerm() {
    let trimmed = newTerm.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !terms.contains(trimmed) else { return }
    terms.append(trimmed)
    settings.customVocabulary = terms
    newTerm = ""
  }
}
```

- [ ] **Step 2: Hook the tab into SettingsWindow**

In `Tide/Settings/SettingsWindow.swift`, add the tab after `DictationSection`:

```swift
      DictationSection()
        .tabItem { Label("Diktat", systemImage: "mic.fill") }
      VocabularySection()
        .tabItem { Label("Vokabular", systemImage: "character.book.closed") }
      QuickActionsEditor()
        .tabItem { Label("Actions", systemImage: "bolt") }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Manual smoke test**

Build + run in Xcode (Cmd+R). Open Settings → Vokabular. Verify:
1. Add "PADI" + "SeaExplorers" → appear in list; reopen Settings → still there (persisted).
2. Delete a row → gone after reopen.
3. Add 51+ terms → soft-warning caption appears.

- [ ] **Step 5: Commit**

```bash
git add Tide/Settings/VocabularySection.swift Tide/Settings/SettingsWindow.swift
git commit -m "feat(settings): custom vocabulary editor tab

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add to the Unreleased section**

In `CHANGELOG.md`, under the existing `## [Unreleased]` → `### Added`, add a second bullet:

```markdown
- **Custom-Vokabular** — pflegbare Begriffsliste (Settings→Vokabular) für
  Namen/Fachjargon (PADI, SeaExplorers, …). Biast die Apple-Erkennung
  (`contextualStrings`) und wird im polished-Diktat an Claude weitergegeben,
  damit Jargon korrekt geschrieben wird. ElevenLabs Scribe hat keine
  Keyword-Bias-API — dort greift nur der Polish-Pfad.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for custom vocabulary

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** Storage (T1), Apple-Bias A (T2 + T3 wiring), Polish-Injektion B (T4), UI-Tab (T5), CHANGELOG (T6). Alle Spec-Abschnitte abgedeckt.
- **Type consistency:** `customVocabulary: [String]`, `contextualStrings`, `RecognizerFactory.make(…, vocabulary:)`, `DictationPolisher.systemPrompt(base:vocabulary:)` durchgängig benannt.
- **Backward-compat:** `vocabulary` + `contextualStrings` haben Default `[]` → bestehende `RecognizerFactoryTests` + andere Call-Sites kompilieren unverändert.
- **Test-Befehl:** App-Target braucht `CODE_SIGNING_ALLOWED=NO`, sonst Code-Sign-Fehler (pre-existing TideTests-Config).
