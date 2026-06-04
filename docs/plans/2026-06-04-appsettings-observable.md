# AppSettings Observable-Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `AppSettings` genuinely `@Observable` (stored-backing instead of UserDefaults-computed) so SwiftUI tracks changes, then drop the redundant `@State` mirror hacks in the six settings views.

**Architecture:** `AppSettings` keeps every public property name/type + the `Key` enum + the `default…Prompt` constants — only the storage changes (computed → stored var, init-from-UserDefaults, didSet-writes-back). No app-logic call-site ripple. The six views then bind directly via `@Bindable`/`$settings.foo` and lose their tracking-only `@State` mirrors. Per-view instances stay (no shared `@Environment`).

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest. Core tests: `cd Packages/Core && swift test`. App build: `xcodebuild … CODE_SIGNING_ALLOWED=NO`. New files via `xcodegen generate`.

**Branch:** Vor Task 1: `git checkout -b feat/appsettings-observable`

---

## Task 1: AppSettings — computed → stored-backing

**Files:** `Packages/Core/Sources/Core/Settings/AppSettings.swift`

This is the load-bearing change; the existing `AppSettingsTests` are the safety net.

- [ ] **Step 1: Implement**

Replace the property definitions (the `init` and every `var foo { get/set }`) with stored vars + a UserDefaults-reading init. Keep the file header, `@Observable @MainActor`, the `Key` enum, and the five `static let default…Prompt` constants UNCHANGED. The new shape:

```swift
public final class AppSettings {  // keep @Observable @MainActor above
  @ObservationIgnored private let defaults: UserDefaults

  // ... keep the five `public static let default…Prompt` constants ...
  // ... keep the private enum Key { … } unchanged ...

  public var selectedModel: String { didSet { defaults.set(selectedModel, forKey: Key.selectedModel) } }
  public var voiceEnabled: Bool { didSet { defaults.set(voiceEnabled, forKey: Key.voiceEnabled) } }
  public var voiceIdentifier: String { didSet { defaults.set(voiceIdentifier, forKey: Key.voiceIdentifier) } }
  public var replaceSelectionByDefault: Bool { didSet { defaults.set(replaceSelectionByDefault, forKey: Key.replaceSelectionByDefault) } }
  public var ttsProvider: String { didSet { defaults.set(ttsProvider, forKey: Key.ttsProvider) } }
  public var elevenLabsVoiceID: String { didSet { defaults.set(elevenLabsVoiceID, forKey: Key.elevenLabsVoiceID) } }
  public var speechRecognizer: String { didSet { defaults.set(speechRecognizer, forKey: Key.speechRecognizer) } }
  public var autoSendAfterPushToTalk: Bool { didSet { defaults.set(autoSendAfterPushToTalk, forKey: Key.autoSendAfterPushToTalk) } }
  public var dictationPolishPrompt: String { didSet { defaults.set(dictationPolishPrompt, forKey: Key.dictationPolishPrompt) } }
  public var dictationPillPosition: String { didSet { defaults.set(dictationPillPosition, forKey: Key.dictationPillPosition) } }
  public var dictationCalmerPrompt: String { didSet { defaults.set(dictationCalmerPrompt, forKey: Key.dictationCalmerPrompt) } }
  public var dictationEmojiPrompt: String { didSet { defaults.set(dictationEmojiPrompt, forKey: Key.dictationEmojiPrompt) } }
  public var dictationBulletsPrompt: String { didSet { defaults.set(dictationBulletsPrompt, forKey: Key.dictationBulletsPrompt) } }
  public var dictationProfessionalPrompt: String { didSet { defaults.set(dictationProfessionalPrompt, forKey: Key.dictationProfessionalPrompt) } }
  /// Stored normalised (trimmed, blank-free); didSet persists as a newline string.
  public var customVocabulary: [String] { didSet { defaults.set(customVocabulary.joined(separator: "\n"), forKey: Key.customVocabulary) } }
  public var localModelName: String { didSet { defaults.set(localModelName, forKey: Key.localModelName) } }

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    // Assigning in init does NOT fire didSet → no redundant write-back.
    self.selectedModel = defaults.string(forKey: Key.selectedModel) ?? "claude-sonnet-4-6"
    self.voiceEnabled = defaults.object(forKey: Key.voiceEnabled) as? Bool ?? true
    self.voiceIdentifier = defaults.string(forKey: Key.voiceIdentifier) ?? "com.apple.voice.compact.de-DE.Anna"
    self.replaceSelectionByDefault = defaults.bool(forKey: Key.replaceSelectionByDefault)
    self.ttsProvider = defaults.string(forKey: Key.ttsProvider) ?? "apple"
    self.elevenLabsVoiceID = defaults.string(forKey: Key.elevenLabsVoiceID) ?? "21m00Tcm4TlvDq8ikWAM"
    self.speechRecognizer = defaults.string(forKey: Key.speechRecognizer) ?? "hybrid"
    self.autoSendAfterPushToTalk = defaults.object(forKey: Key.autoSendAfterPushToTalk) as? Bool ?? true
    self.dictationPolishPrompt = defaults.string(forKey: Key.dictationPolishPrompt) ?? Self.defaultPolishPrompt
    self.dictationPillPosition = defaults.string(forKey: Key.dictationPillPosition) ?? "topCenter"
    self.dictationCalmerPrompt = defaults.string(forKey: Key.dictationCalmerPrompt) ?? Self.defaultCalmerPrompt
    self.dictationEmojiPrompt = defaults.string(forKey: Key.dictationEmojiPrompt) ?? Self.defaultEmojiPrompt
    self.dictationBulletsPrompt = defaults.string(forKey: Key.dictationBulletsPrompt) ?? Self.defaultBulletsPrompt
    self.dictationProfessionalPrompt = defaults.string(forKey: Key.dictationProfessionalPrompt) ?? Self.defaultProfessionalPrompt
    self.customVocabulary = Self.parseVocabulary(defaults.string(forKey: Key.customVocabulary) ?? "")
    self.localModelName = defaults.string(forKey: Key.localModelName) ?? "openai_whisper-small_216MB"
  }

  private static func parseVocabulary(_ raw: String) -> [String] {
    raw.split(separator: "\n", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }
}
```

Keep all the existing doc comments where reasonable (attach them to the new stored vars). The `@ObservationIgnored` on `defaults` prevents the macro from trying to track the UserDefaults reference.

- [ ] **Step 2: Run the existing tests (the safety net)**

Run: `cd Packages/Core && swift test --filter AppSettingsTests 2>&1 | tail -8`
Expected: PASS — every existing AppSettings test stays green (round-trip, defaults, vocabulary trim/parse, model/recognizer/localModelName). The semantics are identical: init reads UserDefaults (same default fallbacks), set persists.

If any test fails because it mutates `defaults` AFTER constructing the same instance and expects a live re-read, that's a test relying on the OLD computed behaviour — adjust it to construct a fresh `AppSettings(defaults:)` after the mutation (which is already how the existing tests are written, so this likely won't happen).

- [ ] **Step 3: Commit**

```bash
git add Packages/Core/Sources/Core/Settings/AppSettings.swift
git commit -m "refactor(core): AppSettings stored-backing for real @Observable tracking

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `ModelSection` — direct binding

**Files:** `Tide/Settings/ModelSection.swift`

- [ ] **Step 1: Replace the Binding(get:set:)**

Add `@Bindable var settings = settings` at the top of `body`, and replace the picker selection. New `body`:

```swift
  var body: some View {
    @Bindable var settings = settings
    Form {
      Section {
        Picker("Anthropic-Modell:", selection: $settings.selectedModel) {
          ForEach(availableModels, id: \.self) { model in
            Text(modelLabel(for: model)).tag(model)
          }
        }
        Text("Sonnet 4.6: schnell, gut. Opus 4.6: stärker, langsamer. Haiku 4.5: günstig, kurz.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("LLM")
      }
    }
    .formStyle(.grouped)
  }
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Tide/Settings/ModelSection.swift
git commit -m "refactor(settings): ModelSection binds AppSettings directly

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `VoiceSection` — drop recognizer mirror, keep validation

**Files:** `Tide/Settings/VoiceSection.swift`

This is the highest-care view: it has a `recognizerChoice` `@State` mirror AND real snap-back validation logic (key/model missing). The validation MUST be preserved.

- [ ] **Step 1: Apply**

Read the file fully. Make these changes:
- Add `@Bindable var settings = settings` at the top of `body`.
- Convert every `Binding(get: { settings.x }, set: { settings.x = $0 })` (voiceEnabled, ttsProvider, voiceIdentifier, elevenLabsVoiceID, autoSendAfterPushToTalk, replaceSelectionByDefault) to `$settings.x`.
- Remove the `@State private var recognizerChoice` mirror and its `.task` seed line that sets it. Bind the recognizer Picker through an enum adapter instead:
```swift
        Picker("Recognizer:", selection: Binding(
          get: { SpeechRecognizerChoice(rawValue: settings.speechRecognizer) ?? .default },
          set: { newChoice in
            // Preserve the existing snap-back validation:
            if newChoice.requiresElevenLabsKey, elevenLabsKey.isEmpty {
              settings.speechRecognizer = SpeechRecognizerChoice.apple.rawValue
              showRecognizerKeyMissingHint = true
              showLocalModelMissingHint = false
            } else if newChoice.requiresLocalModel,
                      !WhisperModelStore().isInstalled(settings.localModelName) {
              settings.speechRecognizer = SpeechRecognizerChoice.apple.rawValue
              showLocalModelMissingHint = true
              showRecognizerKeyMissingHint = false
            } else {
              settings.speechRecognizer = newChoice.rawValue
              showRecognizerKeyMissingHint = false
              showLocalModelMissingHint = false
            }
          }
        )) {
          ForEach(SpeechRecognizerChoice.allCases, id: \.self) { choice in
            Text(choice.displayName).tag(choice)
          }
        }
```
  (This folds the old `.onChange(of: recognizerChoice)` logic into the binding's `set`. Drop the now-unused `.onChange(of: recognizerChoice)` modifier and the `recognizerChoice` `@State`.)
- KEEP: `showRecognizerKeyMissingHint` / `showLocalModelMissingHint` `@State` + their hint `Text` views, `elevenLabsKey` `@State` + the fetch-voices logic, `elevenLabsVoices`, `fetchingVoices`, `fetchError`. These are real view state, not Settings mirrors.

- [ ] **Step 2: Build**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manual smoke**

Run app, Settings → Stimme: toggle voice/TTS/recognizer; selecting ElevenLabs/Local without key/model still snaps back to Apple + shows the hint; the picker reflects the persisted choice on reopen.

- [ ] **Step 4: Commit**

```bash
git add Tide/Settings/VoiceSection.swift
git commit -m "refactor(settings): VoiceSection binds AppSettings directly; keep validation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `DictationSection` — drop prompt/pill mirrors

**Files:** `Tide/Settings/DictationSection.swift`

- [ ] **Step 1: Apply**

Read the file. Keep `selectedMode` `@State` (it's a real UI selection, not a settings mirror). Remove the `promptText` and `pillPosition` `@State` mirrors + their `.onChange`/`.task` seeding. Bind directly:
- Add `@Bindable var settings = settings` in `body`.
- The prompt `TextEditor` binds to a per-mode binding derived from `$settings` — use a computed `Binding<String>` for the selected mode:
```swift
  private func promptBinding(for mode: PromptMode) -> Binding<String> {
    switch mode {
    case .polished:     Binding(get: { settings.dictationPolishPrompt }, set: { settings.dictationPolishPrompt = $0 })
    case .calmer:       Binding(get: { settings.dictationCalmerPrompt }, set: { settings.dictationCalmerPrompt = $0 })
    case .emoji:        Binding(get: { settings.dictationEmojiPrompt }, set: { settings.dictationEmojiPrompt = $0 })
    case .bullets:      Binding(get: { settings.dictationBulletsPrompt }, set: { settings.dictationBulletsPrompt = $0 })
    case .professional: Binding(get: { settings.dictationProfessionalPrompt }, set: { settings.dictationProfessionalPrompt = $0 })
    }
  }
```
  `TextEditor(text: promptBinding(for: selectedMode))`. The mode `Picker` stays `$selectedMode`. "Standard wiederherstellen" sets the prompt directly: `promptBinding(for: selectedMode).wrappedValue = selectedMode.default` (or assign `settings.dictation…Prompt = selectedMode.default`).
- Pill-position `Picker` → `$settings.dictationPillPosition`. Drop its `.onChange`.
- Remove the `.task` that seeded `promptText`/`pillPosition`.

- [ ] **Step 2: Build + smoke** — `BUILD SUCCEEDED`; switching modes shows each prompt, edits persist, "Standard wiederherstellen" resets the shown mode, pill-position persists.

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git add Tide/Settings/DictationSection.swift
git commit -m "refactor(settings): DictationSection binds prompts/pill directly

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `VocabularySection` — drop terms mirror

**Files:** `Tide/Settings/VocabularySection.swift`

- [ ] **Step 1: Apply**

Read the file. Remove the `terms` `@State` mirror + its `.task` seed. Operate directly on `settings.customVocabulary`:
- The `List`/`ForEach` iterates `settings.customVocabulary` (id: `\.self`). `onDelete` removes from a local copy and reassigns: `var v = settings.customVocabulary; v.remove(atOffsets: offsets); settings.customVocabulary = v`.
- `addTerm` appends: `let t = newTerm.trimmingCharacters(in: .whitespaces); guard !t.isEmpty, !settings.customVocabulary.contains(t) else { return }; settings.customVocabulary.append(t); newTerm = ""`.
- The soft-limit warning uses `settings.customVocabulary.count > softLimit`.
- Keep `newTerm` `@State`. `@Bindable` not strictly needed (no `$settings` binding used — direct reads/writes), but add it if a binding is convenient.

- [ ] **Step 2: Build + smoke** — `BUILD SUCCEEDED`; add/delete terms work + persist; soft-limit appears past 50.

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git add Tide/Settings/VocabularySection.swift
git commit -m "refactor(settings): VocabularySection operates on settings directly

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: `LocalModelSection` — drop selectedModel mirror

**Files:** `Tide/Settings/LocalModelSection.swift`

- [ ] **Step 1: Apply**

Read the file. Remove the `selectedModel` `@State` mirror + its `.task` seed line. Bind the model `Picker` to `$settings.localModelName` (add `@Bindable var settings = settings`). Replace all `selectedModel` references with `settings.localModelName`. The `.onChange(of: selectedModel)` that updated settings + prewarmed becomes `.onChange(of: settings.localModelName) { _, new in prewarmIfInstalled(new) }` (the settings write is now implicit via the binding). KEEP `catalog`, `downloading`, `downloadProgress`, `downloadError`, `store` — real view state.

- [ ] **Step 2: Build + smoke** — `BUILD SUCCEEDED`; model picker reflects/persists `localModelName`; download/progress/installed badge still work.

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git add Tide/Settings/LocalModelSection.swift
git commit -m "refactor(settings): LocalModelSection binds localModelName directly

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: `OnboardingSteps` `VoiceStep` — drop mirrors

**Files:** `Tide/Onboarding/Steps/OnboardingSteps.swift`

- [ ] **Step 1: Apply**

Read the file, find `struct VoiceStep`. Remove its `recognizer` and `tts` `@State` mirrors + the `.task` seed. Bind the recognizer `Picker` via the enum adapter (`Binding(get: { SpeechRecognizerChoice(rawValue: settings.speechRecognizer) ?? .default }, set: { settings.speechRecognizer = $0.rawValue })`) and the TTS `Picker` to `$settings.ttsProvider` (add `@Bindable var settings = settings`). Drop the `.onChange` handlers that wrote settings (now implicit). Leave the other onboarding steps untouched.

- [ ] **Step 2: Build + smoke** — `BUILD SUCCEEDED`; onboarding VoiceStep recognizer/TTS pickers reflect + persist.

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git add Tide/Onboarding/Steps/OnboardingSteps.swift
git commit -m "refactor(onboarding): VoiceStep binds AppSettings directly

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: CHANGELOG

**Files:** `CHANGELOG.md`

- [ ] **Step 1:** Under `## [Unreleased]` → `### Changed`, add:

```markdown
- **AppSettings echt observable** — die Einstellungen nutzen jetzt stored
  Properties (aus UserDefaults initialisiert, `didSet` persistiert) statt
  Computed-Getter, sodass `@Observable` Änderungen tatsächlich trackt. Die
  sechs Settings-Views verlieren ihre `@State`-Mirror-Workarounds und binden
  direkt. Verhalten unverändert.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for AppSettings observable redesign

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** AppSettings (T1), ModelSection (T2), VoiceSection (T3), DictationSection (T4), VocabularySection (T5), LocalModelSection (T6), OnboardingSteps VoiceStep (T7), changelog (T8). All covered.
- **Behaviour-preserving:** property names/types/defaults + Key enum + default…Prompt constants unchanged → no app-logic ripple; the existing AppSettingsTests are the regression gate (T1). View changes are pure binding-source swaps; per-view manual smoke verifies parity.
- **Highest risk:** VoiceSection (T3) — its snap-back validation must move into the recognizer binding's `set`, not be lost. DictationSection (T4) per-mode prompt binding. Each view is its own commit so a regression is bisectable.
- **`@Bindable` idiom:** `@Bindable var settings = settings` inside `body` is the SwiftUI-Observation way to derive `$` bindings from a `@State`-held `@Observable` object.
- **Quality gate:** after the view tasks, the controller runs a `swiftui-pro` review of the converted views + AppSettings.
```
