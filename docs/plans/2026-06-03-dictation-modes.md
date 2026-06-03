# Dictation Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Four new standalone-dictation transform modes — Calmer, Emoji, Bullets, Professional — each an opt-in hotkey that routes the transcript through Claude with an editable mode-specific prompt.

**Architecture:** Generalize the existing `polished` path. `DictationMode` gains the 4 cases; every non-`raw` mode runs through `DictationPolisher` with a base prompt selected per mode from `AppSettings`. New hotkeys + Settings prompt editors. No new processing logic.

**Tech Stack:** Swift 6, XCTest, SwiftUI, KeyboardShortcuts. Package tests via `swift test`; app-target via `xcodebuild … CODE_SIGNING_ALLOWED=NO`.

---

## File Structure

| Datei | Verantwortung |
|---|---|
| `Packages/Core/Sources/Core/Settings/AppSettings.swift` | 4 new prompt props + 5 `static let default…Prompt` + refactor polish getter |
| `Packages/Core/Tests/CoreTests/AppSettingsTests.swift` | defaults + round-trip tests |
| `Packages/Hotkeys/Sources/Hotkeys/Names.swift` | 4 new hotkey names |
| `Tide/Dictation/DictationCoordinator.swift` | extend `DictationMode` + helpers + generalize `stop()` switch |
| `Tide/Dictation/DictationPolisher.swift` | `polish(_:basePrompt:)` signature |
| `TideTests/DictationPolisherTests.swift` | adapt to new signature + basePrompt test |
| `TideTests/DictationModeTests.swift` | **new** |
| `Tide/AppEntry.swift` | 4 new hotkey wirings |
| `Tide/Settings/HotkeySection.swift` | 4 new Recorder widgets |
| `Tide/Settings/DictationSection.swift` | Picker→Editor over 5 modes |
| `CHANGELOG.md` | Unreleased entry |

**Branch:** Vor Task 1: `git checkout -b feat/dictation-modes`

---

## Task 1: AppSettings — 4 prompts + shared default constants

**Files:**
- Modify: `Packages/Core/Sources/Core/Settings/AppSettings.swift`
- Test: `Packages/Core/Tests/CoreTests/AppSettingsTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Packages/Core/Tests/CoreTests/AppSettingsTests.swift` inside the class:

```swift
  @MainActor
  func testTransformPromptDefaultsNonEmpty() {
    let s = AppSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    XCTAssertEqual(s.dictationCalmerPrompt, AppSettings.defaultCalmerPrompt)
    XCTAssertEqual(s.dictationEmojiPrompt, AppSettings.defaultEmojiPrompt)
    XCTAssertEqual(s.dictationBulletsPrompt, AppSettings.defaultBulletsPrompt)
    XCTAssertEqual(s.dictationProfessionalPrompt, AppSettings.defaultProfessionalPrompt)
    XCTAssertFalse(AppSettings.defaultCalmerPrompt.isEmpty)
  }

  @MainActor
  func testTransformPromptRoundTrip() {
    let defs = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let s = AppSettings(defaults: defs)
    s.dictationCalmerPrompt = "CALM X"
    s.dictationEmojiPrompt = "EMOJI X"
    s.dictationBulletsPrompt = "BULLET X"
    s.dictationProfessionalPrompt = "PRO X"
    let r = AppSettings(defaults: defs)
    XCTAssertEqual(r.dictationCalmerPrompt, "CALM X")
    XCTAssertEqual(r.dictationEmojiPrompt, "EMOJI X")
    XCTAssertEqual(r.dictationBulletsPrompt, "BULLET X")
    XCTAssertEqual(r.dictationProfessionalPrompt, "PRO X")
  }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Packages/Core && swift test --filter AppSettingsTests 2>&1 | tail -12`
Expected: FAIL — no member `dictationCalmerPrompt` / `defaultCalmerPrompt`.

- [ ] **Step 3: Implement**

In `Packages/Core/Sources/Core/Settings/AppSettings.swift`:

(a) Add to the `Key` enum (after `dictationPillPosition`):
```swift
    static let dictationCalmerPrompt = "tide.dictationCalmerPrompt"
    static let dictationEmojiPrompt = "tide.dictationEmojiPrompt"
    static let dictationBulletsPrompt = "tide.dictationBulletsPrompt"
    static let dictationProfessionalPrompt = "tide.dictationProfessionalPrompt"
```

(b) Add the shared default constants. Place them near the top of the class body (after `private let defaults` / `init`):
```swift
  // Default transform-mode prompts. Single source of truth: the property
  // getters fall back to these, and DictationSection's "restore default"
  // reads the same constants. All language-agnostic ("SAME language").
  public static let defaultPolishPrompt =
    "You are a text editor. Fix grammar and punctuation in the user's text. "
    + "Reply in the SAME language as the input. Keep the meaning 1:1, do not "
    + "shorten, do not add anything, do not explain. Output ONLY the corrected text."
  public static let defaultCalmerPrompt =
    "You are an editor. Rewrite the user's text as a calm, factual, professional "
    + "message. Keep the core point but remove anger, insults and venting. Reply "
    + "in the SAME language as the input. Output ONLY the rewritten message."
  public static let defaultEmojiPrompt =
    "Add a few fitting emojis to the user's text to match its tone. Do not "
    + "otherwise change the wording. Reply in the SAME language. Output ONLY the "
    + "text with emojis."
  public static let defaultBulletsPrompt =
    "Convert the user's spoken thoughts into a clean bullet-point list. Keep all "
    + "key points, add nothing. Reply in the SAME language. Output ONLY the bullet list."
  public static let defaultProfessionalPrompt =
    "Rewrite the user's text in a more formal, professional business tone. Keep "
    + "the meaning, do not add or remove content. Reply in the SAME language. "
    + "Output ONLY the rewritten text."
```

(c) Refactor the existing `dictationPolishPrompt` getter to use the constant (behaviour-preserving — the inline string equals `defaultPolishPrompt`):
```swift
  public var dictationPolishPrompt: String {
    get { defaults.string(forKey: Key.dictationPolishPrompt) ?? Self.defaultPolishPrompt }
    set { defaults.set(newValue, forKey: Key.dictationPolishPrompt) }
  }
```

(d) Add the 4 new properties (after `dictationPillPosition`):
```swift
  public var dictationCalmerPrompt: String {
    get { defaults.string(forKey: Key.dictationCalmerPrompt) ?? Self.defaultCalmerPrompt }
    set { defaults.set(newValue, forKey: Key.dictationCalmerPrompt) }
  }
  public var dictationEmojiPrompt: String {
    get { defaults.string(forKey: Key.dictationEmojiPrompt) ?? Self.defaultEmojiPrompt }
    set { defaults.set(newValue, forKey: Key.dictationEmojiPrompt) }
  }
  public var dictationBulletsPrompt: String {
    get { defaults.string(forKey: Key.dictationBulletsPrompt) ?? Self.defaultBulletsPrompt }
    set { defaults.set(newValue, forKey: Key.dictationBulletsPrompt) }
  }
  public var dictationProfessionalPrompt: String {
    get { defaults.string(forKey: Key.dictationProfessionalPrompt) ?? Self.defaultProfessionalPrompt }
    set { defaults.set(newValue, forKey: Key.dictationProfessionalPrompt) }
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Packages/Core && swift test --filter AppSettingsTests 2>&1 | tail -6`
Expected: PASS (incl. 2 new).

- [ ] **Step 5: Commit**

```bash
git add Packages/Core/Sources/Core/Settings/AppSettings.swift Packages/Core/Tests/CoreTests/AppSettingsTests.swift
git commit -m "feat(core): dictation transform-mode prompts + shared defaults

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Hotkey names

**Files:** `Packages/Hotkeys/Sources/Hotkeys/Names.swift`

- [ ] **Step 1: Add 4 names**

In `Packages/Hotkeys/Sources/Hotkeys/Names.swift`, after `dictatePolished`, add:

```swift
  /// Hold to dictate, then rewrite as a calm/factual message. Opt-in.
  static let dictateCalmer = Self("dictateCalmer", default: nil)
  /// Hold to dictate, then add fitting emojis. Opt-in.
  static let dictateEmoji = Self("dictateEmoji", default: nil)
  /// Hold to dictate, then convert to a bullet-point list. Opt-in.
  static let dictateBullets = Self("dictateBullets", default: nil)
  /// Hold to dictate, then rewrite in a formal business tone. Opt-in.
  static let dictateProfessional = Self("dictateProfessional", default: nil)
```

- [ ] **Step 2: Build**

Run: `cd Packages/Hotkeys && swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/Hotkeys/Sources/Hotkeys/Names.swift
git commit -m "feat(hotkeys): names for 4 dictation transform modes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `DictationPolisher.polish(_:basePrompt:)`

**Files:**
- Modify: `Tide/Dictation/DictationPolisher.swift`
- Test: `TideTests/DictationPolisherTests.swift`

- [ ] **Step 1: Adapt existing tests + add basePrompt test**

In `TideTests/DictationPolisherTests.swift`, every call to `polisher.polish("...")` must pass a `basePrompt:`. The simplest mechanical change: replace each `try await polisher.polish(RAW)` with `try await polisher.polish(RAW, basePrompt: settings.dictationPolishPrompt)` so behaviour matches the old implicit read. For the existing wiring test `test_polish_forwardsSystemPromptFromSettings` (which sets `settings.dictationPolishPrompt = "MY CUSTOM PROMPT"` then asserts `stub.lastSystemPrompt == "MY CUSTOM PROMPT"`), change it to pass the base explicitly and keep the assertion:

```swift
  func test_polish_forwardsBasePrompt() async throws {
    let stub = StubProvider(chunks: ["ok"])
    let polisher = DictationPolisher(provider: stub, settings: settings, timeoutSeconds: 2)
    _ = try await polisher.polish("raw", basePrompt: "MY CUSTOM PROMPT")
    XCTAssertEqual(stub.lastSystemPrompt, "MY CUSTOM PROMPT")
  }
```

Add a vocab-still-appended test:

```swift
  func test_polish_appendsVocabularyToBasePrompt() async throws {
    settings.customVocabulary = ["PADI"]
    let stub = StubProvider(chunks: ["ok"])
    let polisher = DictationPolisher(provider: stub, settings: settings, timeoutSeconds: 2)
    _ = try await polisher.polish("raw", basePrompt: "BASE")
    let prompt = try XCTUnwrap(stub.lastSystemPrompt)
    XCTAssertTrue(prompt.hasPrefix("BASE"))
    XCTAssertTrue(prompt.contains("PADI"))
  }
```

If the existing tests `test_polish_appendsVocabularyToSystemPrompt` / `test_polish_leavesSystemPromptUnchanged_whenNoVocabulary` set `settings.dictationPolishPrompt` and call `polish("raw")`, update them to call `polish("raw", basePrompt: "BASE PROMPT")` and assert against `"BASE PROMPT"` instead of the settings value (the base now comes from the argument). Keep the vocab assertions.

- [ ] **Step 2: Run to verify it fails (compile error)**

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/DictationPolisherTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -12`
Expected: FAIL — `polish` does not take a `basePrompt:` argument (compile error) until Step 3.

- [ ] **Step 3: Change the signature**

In `Tide/Dictation/DictationPolisher.swift`, change the function declaration (line ~70):

```swift
  func polish(_ raw: String, basePrompt: String) async throws -> String {
```

And change the `systemPrompt` construction (line ~80) from `base: settings.dictationPolishPrompt` to `base: basePrompt`:

```swift
    let systemPrompt = Self.systemPrompt(
      base: basePrompt,
      vocabulary: settings.customVocabulary
    )
```

Leave everything else (timeout, fallback, the `static func systemPrompt(base:vocabulary:)` helper) unchanged.

- [ ] **Step 4: Run to verify it passes**

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/DictationPolisherTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -8`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Tide/Dictation/DictationPolisher.swift TideTests/DictationPolisherTests.swift
git commit -m "refactor(dictation): polish takes explicit basePrompt

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Extend `DictationMode` + helpers

**Files:**
- Modify: `Tide/Dictation/DictationCoordinator.swift`
- Test: `TideTests/DictationModeTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `TideTests/DictationModeTests.swift`:

```swift
import XCTest
import Core
@testable import Tide

final class DictationModeTests: XCTestCase {
  @MainActor
  func test_allCases_containsAllSix() {
    let all = Set(DictationMode.allCases)
    XCTAssertEqual(all, [.raw, .polished, .calmer, .emoji, .bullets, .professional])
  }

  @MainActor
  func test_isRaw_onlyForRaw() {
    XCTAssertTrue(DictationMode.raw.isRaw)
    for m in DictationMode.allCases where m != .raw {
      XCTAssertFalse(m.isRaw)
    }
  }

  @MainActor
  func test_basePrompt_rawIsNil() {
    let s = AppSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    XCTAssertNil(DictationMode.raw.basePrompt(from: s))
  }

  @MainActor
  func test_basePrompt_mapsEachModeToItsSetting() {
    let s = AppSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    s.dictationPolishPrompt = "P"
    s.dictationCalmerPrompt = "C"
    s.dictationEmojiPrompt = "E"
    s.dictationBulletsPrompt = "B"
    s.dictationProfessionalPrompt = "PRO"
    XCTAssertEqual(DictationMode.polished.basePrompt(from: s), "P")
    XCTAssertEqual(DictationMode.calmer.basePrompt(from: s), "C")
    XCTAssertEqual(DictationMode.emoji.basePrompt(from: s), "E")
    XCTAssertEqual(DictationMode.bullets.basePrompt(from: s), "B")
    XCTAssertEqual(DictationMode.professional.basePrompt(from: s), "PRO")
  }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/DictationModeTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -12`
Expected: FAIL — `DictationMode` has no `.calmer` etc. / no `isRaw` / no `basePrompt`.

- [ ] **Step 3: Implement**

In `Tide/Dictation/DictationCoordinator.swift`, replace the existing `enum DictationMode { case raw; case polished }` with:

```swift
/// Which post-processing path a dictation session takes after the
/// recognizer returns its final text. `raw` inserts verbatim; every other
/// case routes the transcript through `DictationPolisher` with that mode's
/// editable base prompt.
enum DictationMode: String, CaseIterable, Sendable {
  case raw
  case polished
  case calmer
  case emoji
  case bullets
  case professional

  var isRaw: Bool { self == .raw }

  var displayName: String {
    switch self {
    case .raw:          "Roh"
    case .polished:     "Polished"
    case .calmer:       "Calmer (Dampf ablassen)"
    case .emoji:        "Emoji"
    case .bullets:      "Bullets"
    case .professional: "Professional"
    }
  }

  /// The editable base prompt for this transform mode, or `nil` for `.raw`.
  @MainActor
  func basePrompt(from settings: AppSettings) -> String? {
    switch self {
    case .raw:          nil
    case .polished:     settings.dictationPolishPrompt
    case .calmer:       settings.dictationCalmerPrompt
    case .emoji:        settings.dictationEmojiPrompt
    case .bullets:      settings.dictationBulletsPrompt
    case .professional: settings.dictationProfessionalPrompt
    }
  }
}
```

(Keep the surrounding doc comments / file otherwise unchanged for now — the `stop()` switch is updated in Task 5.)

- [ ] **Step 4: Run to verify it passes**

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/DictationModeTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -8`
Expected: `TEST SUCCEEDED` (4 tests).

(Note: the app may not yet build for the full DictationCoordinator if `stop()` still references only `.raw`/`.polished` — but a `switch` over the enum without `@unknown` will now be non-exhaustive. If the build breaks here, that's expected; Task 5 fixes `stop()`. If `-only-testing` still compiles the whole target and fails, proceed to Task 5 and re-run both. To keep Task 4 green on its own, you MAY apply Task 5's `stop()` change now — the two tasks are tightly coupled by the exhaustiveness requirement.)

- [ ] **Step 5: Commit**

```bash
git add Tide/Dictation/DictationCoordinator.swift TideTests/DictationModeTests.swift
git commit -m "feat(dictation): extend DictationMode with transform modes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Generalize `DictationCoordinator.stop()` switch

**Files:** `Tide/Dictation/DictationCoordinator.swift`

- [ ] **Step 1: Replace the mode switch**

In `stop()`, find the block (after the artifact-reject guard) that switches on `self.currentMode`:

```swift
      switch self.currentMode {
      case .raw:
        let result = await TextInjector.insert(trimmed)
        Self.logger.debug("text-injector result: \(String(describing: result), privacy: .public)")
      case .polished:
        do {
          let polished = try await polisher.polish(trimmed)
          let result = await TextInjector.insert(polished)
          Self.logger.debug("polish result: \(String(describing: result), privacy: .public)")
        } catch {
          Self.logger.warning(
            "polish failed: \(String(describing: error), privacy: .public) — injecting raw"
          )
          let result = await TextInjector.insert(trimmed)
          Self.logger.debug(
            "polish-fallback (raw) result: \(String(describing: result), privacy: .public)"
          )
          await notifyPolishFailed()
        }
      }
```

Replace it with:

```swift
      if self.currentMode.isRaw {
        let result = await TextInjector.insert(trimmed)
        Self.logger.debug("text-injector result: \(String(describing: result), privacy: .public)")
      } else {
        let base = self.currentMode.basePrompt(from: settings) ?? ""
        do {
          let transformed = try await polisher.polish(trimmed, basePrompt: base)
          let result = await TextInjector.insert(transformed)
          Self.logger.debug("transform (\(self.currentMode.rawValue, privacy: .public)) result: \(String(describing: result), privacy: .public)")
        } catch {
          Self.logger.warning(
            "transform failed: \(String(describing: error), privacy: .public) — injecting raw"
          )
          let result = await TextInjector.insert(trimmed)
          Self.logger.debug(
            "transform-fallback (raw) result: \(String(describing: result), privacy: .public)"
          )
          await notifyPolishFailed()
        }
      }
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Run dictation tests (no regression)**

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/DictationPolisherTests -only-testing:TideTests/DictationModeTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -8`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Tide/Dictation/DictationCoordinator.swift
git commit -m "feat(dictation): route all transform modes through polisher

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: AppEntry hotkey wirings

**Files:** `Tide/AppEntry.swift`

- [ ] **Step 1: Add 4 wiring pairs**

In `Tide/AppEntry.swift`, find the existing dictation hotkey wirings (the `KeyboardShortcuts.onKeyDown(for: .dictateRaw) { … }` … `.dictatePolished` block). After the `.dictatePolished` `onKeyUp` pair, add:

```swift
        KeyboardShortcuts.onKeyDown(for: .dictateCalmer) {
          Task { @MainActor in await dictation.start(mode: .calmer) }
        }
        KeyboardShortcuts.onKeyUp(for: .dictateCalmer) {
          Task { @MainActor in await dictation.stop() }
        }
        KeyboardShortcuts.onKeyDown(for: .dictateEmoji) {
          Task { @MainActor in await dictation.start(mode: .emoji) }
        }
        KeyboardShortcuts.onKeyUp(for: .dictateEmoji) {
          Task { @MainActor in await dictation.stop() }
        }
        KeyboardShortcuts.onKeyDown(for: .dictateBullets) {
          Task { @MainActor in await dictation.start(mode: .bullets) }
        }
        KeyboardShortcuts.onKeyUp(for: .dictateBullets) {
          Task { @MainActor in await dictation.stop() }
        }
        KeyboardShortcuts.onKeyDown(for: .dictateProfessional) {
          Task { @MainActor in await dictation.start(mode: .professional) }
        }
        KeyboardShortcuts.onKeyUp(for: .dictateProfessional) {
          Task { @MainActor in await dictation.stop() }
        }
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Tide/AppEntry.swift
git commit -m "feat(app): wire 4 dictation transform-mode hotkeys

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: HotkeySection Recorder widgets

**Files:** `Tide/Settings/HotkeySection.swift`

- [ ] **Step 1: Add 4 recorders**

In `Tide/Settings/HotkeySection.swift`, inside the "Standalone Dictation (Welle 4)" `Section`, after the `dictatePolished` Recorder + its caption, add:

```swift
        KeyboardShortcuts.Recorder("Diktieren (Calmer):", name: .dictateCalmer)
        KeyboardShortcuts.Recorder("Diktieren (Emoji):", name: .dictateEmoji)
        KeyboardShortcuts.Recorder("Diktieren (Bullets):", name: .dictateBullets)
        KeyboardShortcuts.Recorder("Diktieren (Professional):", name: .dictateProfessional)
        Text("Transform-Modi: der Text geht vor dem Einfügen durch Claude mit "
          + "dem jeweiligen Prompt (editierbar in Settings → Diktat). Alle opt-in.")
          .font(.caption)
          .foregroundStyle(.secondary)
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Tide/Settings/HotkeySection.swift
git commit -m "feat(settings): hotkey recorders for transform modes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: DictationSection — Picker → Editor

**Files:** `Tide/Settings/DictationSection.swift`

- [ ] **Step 1: Rewrite the prompt section as a mode picker + editor**

Replace the entire contents of `Tide/Settings/DictationSection.swift` with:

```swift
import SwiftUI
import Core

/// Settings tab for standalone dictation: per-mode transform prompts +
/// the on-screen pill position.
///
/// The five transform modes (polished/calmer/emoji/bullets/professional)
/// each have an editable system prompt. A picker selects which one the
/// editor shows; writing saves to that mode's `AppSettings` key.
/// `raw` has no prompt and is excluded from the picker.
struct DictationSection: View {
  @State private var settings = AppSettings()
  @State private var selectedMode: PromptMode = .polished
  @State private var promptText: String = ""
  @State private var pillPosition: String = "topCenter"

  /// The prompt-bearing modes (everything except raw).
  enum PromptMode: String, CaseIterable, Identifiable {
    case polished, calmer, emoji, bullets, professional
    var id: String { rawValue }
    var label: String {
      switch self {
      case .polished:     "Polished"
      case .calmer:       "Calmer"
      case .emoji:        "Emoji"
      case .bullets:      "Bullets"
      case .professional: "Professional"
      }
    }
    var `default`: String {
      switch self {
      case .polished:     AppSettings.defaultPolishPrompt
      case .calmer:       AppSettings.defaultCalmerPrompt
      case .emoji:        AppSettings.defaultEmojiPrompt
      case .bullets:      AppSettings.defaultBulletsPrompt
      case .professional: AppSettings.defaultProfessionalPrompt
      }
    }
  }

  private func currentPrompt(_ mode: PromptMode) -> String {
    switch mode {
    case .polished:     settings.dictationPolishPrompt
    case .calmer:       settings.dictationCalmerPrompt
    case .emoji:        settings.dictationEmojiPrompt
    case .bullets:      settings.dictationBulletsPrompt
    case .professional: settings.dictationProfessionalPrompt
    }
  }

  private func setPrompt(_ mode: PromptMode, _ value: String) {
    switch mode {
    case .polished:     settings.dictationPolishPrompt = value
    case .calmer:       settings.dictationCalmerPrompt = value
    case .emoji:        settings.dictationEmojiPrompt = value
    case .bullets:      settings.dictationBulletsPrompt = value
    case .professional: settings.dictationProfessionalPrompt = value
    }
  }

  var body: some View {
    Form {
      Section {
        Picker("Modus:", selection: $selectedMode) {
          ForEach(PromptMode.allCases) { mode in
            Text(mode.label).tag(mode)
          }
        }
        .pickerStyle(.menu)
        .onChange(of: selectedMode) { _, newMode in
          promptText = currentPrompt(newMode)
        }

        Text("System-Prompt für den gewählten Transform-Modus. Wird vor "
          + "jeder Sitzung dieses Modus an Claude gesendet; der Rohtext "
          + "kommt als User-Nachricht hinterher.")
          .font(.caption)
          .foregroundStyle(.secondary)

        TextEditor(text: $promptText)
          .font(.system(size: 12, design: .monospaced))
          .frame(minHeight: 120)
          .overlay(
            RoundedRectangle(cornerRadius: 4)
              .stroke(Color.gray.opacity(0.3), lineWidth: 1)
          )
          .onChange(of: promptText) { _, newValue in
            setPrompt(selectedMode, newValue)
          }

        HStack {
          Button("Standard wiederherstellen") {
            promptText = selectedMode.default
            setPrompt(selectedMode, selectedMode.default)
          }
          .controlSize(.small)
          Spacer()
        }
      } header: { Text("Transform-Prompts") }

      Section {
        Picker("Position:", selection: $pillPosition) {
          Text("Oben Mitte").tag("topCenter")
          Text("Oben Rechts").tag("topRight")
          Text("Unten Rechts").tag("bottomRight")
        }
        .pickerStyle(.menu)
        .onChange(of: pillPosition) { _, newValue in
          settings.dictationPillPosition = newValue
        }

        Text("Wo erscheint die kleine Aufnahme-Pille während des Diktats.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: { Text("Aufnahme-Pille") }
    }
    .formStyle(.grouped)
    .task {
      promptText = currentPrompt(selectedMode)
      pillPosition = settings.dictationPillPosition
    }
  }
}
```

- [ ] **Step 2: Build (with fresh project so the file is still globbed)**

Run: `xcodegen generate && xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manual smoke test**

Run the app (Cmd+R). Settings → Hotkey: bind "Diktieren (Calmer)" to a key. Settings → Diktat: pick "Calmer" in the mode picker → its prompt shows; edit + "Standard wiederherstellen" restores it. Dictate an annoyed sentence with the Calmer hotkey → a calmer rewrite lands at the cursor. Switch the picker between modes → editor swaps prompts correctly.

- [ ] **Step 4: Commit**

```bash
git add Tide/Settings/DictationSection.swift
git commit -m "feat(settings): per-mode transform prompt editor

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: CHANGELOG

**Files:** `CHANGELOG.md`

- [ ] **Step 1: Add to Unreleased → Added**

```markdown
- **Diktat-Transform-Modi** — vier neue Standalone-Diktat-Modi neben Roh/Polished:
  **Calmer** (Wut → ruhige Nachricht), **Emoji**, **Bullets** (Stichpunkte),
  **Professional** (formeller Ton). Jeder ein eigener opt-in Hotkey
  (Settings → Hotkey) mit editierbarem Prompt (Settings → Diktat, Modus-Picker).
  Laufen über denselben Claude-Pfad wie Polished. Inspiriert von Blitztexts
  Workflow-Personalities.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for dictation transform modes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** settings+defaults (T1), names (T2), polisher signature (T3), mode enum+helpers (T4), coordinator switch (T5), AppEntry (T6), HotkeySection (T7), DictationSection picker→editor (T8), changelog (T9). All covered.
- **Type consistency:** `DictationMode` cases + `isRaw`/`displayName`/`basePrompt(from:)`; `AppSettings.dictation{Calmer,Emoji,Bullets,Professional}Prompt` + `default…Prompt` statics; `DictationPolisher.polish(_:basePrompt:)`; hotkey names `dictate{Calmer,Emoji,Bullets,Professional}`. Consistent across tasks. The `DictationSection.PromptMode` is a separate UI-only enum (excludes raw) — intentional, doesn't need to match `DictationMode` 1:1.
- **Coupling note (T4↔T5):** extending the enum makes the old 2-case `switch` non-exhaustive; T5 fixes it. If the app build breaks between them, applying T5 before re-running T4's full-target test is fine — flagged in T4 Step 4.
- **Behaviour-preserving:** `defaultPolishPrompt` string is byte-identical to the old inline default; existing polish behaviour unchanged.
- **Test command:** app target needs `CODE_SIGNING_ALLOWED=NO`.
```
