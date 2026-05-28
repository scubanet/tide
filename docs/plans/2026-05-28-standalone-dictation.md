# Implementation Plan — Standalone Dictation (Tide v0.3.0)

Date: 2026-05-28
Spec: `docs/specs/2026-05-28-standalone-dictation-design.md`
Predecessor: v0.2.1 (Diktiermodus-Toggle, Quit-Button, Single-Instance)

Six phases, each committable as a green build. Order matters — the
hotkey wiring needs the new shortcut names, which need the new
DictationCoordinator stubs, which need the existing AudioRecorder
re-used. Then UI + injector + polish path. Rollout last.

---

## Phase A — Shortcut names + AppSettings keys

**Goal:** wire the foundation so Settings can offer Recorder widgets
and AppEntry can register handlers, even before the coordinator
exists.

**Files:**

- `Packages/Hotkeys/Sources/Hotkeys/KeyboardShortcuts+Names.swift`
  (new — or extend existing): add `.dictateRaw` and `.dictatePolished`
  with `default: nil`.
- `Packages/Core/Sources/Core/Settings/AppSettings.swift`: add
  `dictationPolishPrompt` (computed over UserDefaults, default = the
  German polish prompt from the spec) and `dictationPillPosition`
  (default `"topRight"`).
- `Packages/Core/Tests/CoreTests/AppSettingsTests.swift`: add a
  roundtrip test per new property, plus a default-value test.

**Verify:** all tests green via the swift-test loop in tide-test.yml
(simulated locally with `cd Packages/Core && swift test`).

**Commit message:**
> feat(core): dictation shortcut-names + AppSettings keys

---

## Phase B — DictationCoordinator skeleton + AudioRecorder reuse

**Goal:** stub the coordinator so AppEntry's hotkey-handler can call
`.start(mode:)` / `.stop()` without crashing. Recording works end-to-
end; the final text is logged but not yet injected.

**Files:**

- `Tide/Dictation/DictationCoordinator.swift` (new). Properties:
  `private let provider`, `private let settings`, `private var
  recorder: AudioRecorder?`, `private var isActive: Bool`. Methods:
  `start(mode:)` constructs an AudioRecorder with the user's
  Settings-selected recognizer (Apple / EL / Hybrid) — mirror what
  `ChatViewModel.makeRecognizer` does. Hold onto the mode for the
  stop() branch.
- `Tide/AppEntry.swift`: instantiate one `DictationCoordinator` in
  `applicationDidFinishLaunching`. Wire two new
  `KeyboardShortcuts.onKeyDown/onKeyUp` observers. On key-down call
  `coordinator.start(mode: .raw)` (or `.polished`), on key-up
  `coordinator.stop()`.

**Refactor opportunity:** `ChatViewModel.makeRecognizer` is
currently a private method. Extract it into a free function
`Tide/Dictation/RecognizerFactory.swift` so both `ChatViewModel`
and `DictationCoordinator` can call it. Test-driven: add
`RecognizerFactoryTests` covering the four branches (apple, EL with
key, EL without key, hybrid).

**Verify:**
1. Set Settings → Dictation → Hotkey to e.g. `⌃⇧D`.
2. Hold the hotkey, say "hallo welt", release.
3. Console.app log under `swiss.weckherlin.tide:dictation` shows
   `coordinator received final text: 'Hallo Welt.'` (or similar).
4. No panel opens, no Tide window grabs focus.

**Commit message:**
> feat(dictation): coordinator skeleton + RecognizerFactory extract

---

## Phase C — DictationIndicator (menubar tint + floating pill)

**Goal:** user sees recording feedback even though text-injection is
not yet wired.

**Files:**

- `Tide/Dictation/MenubarTint.swift` (new). Tiny helper struct that
  swaps a status item's image and reverts. Owns no state besides the
  saved original `NSImage`.
- `Tide/Dictation/FloatingPill.swift` (new). NSPanel subclass,
  `220×36`, `nonactivatingPanel + borderless`, `level = .floating`,
  `canBecomeKey = false`. Content view: an `HStack` with a small red
  dot (`Circle().fill(.red).frame(width: 8, height: 8)`) and a
  `Text` bound to a `partial: String`. Position computed from
  `settings.dictationPillPosition` against the screen's
  `visibleFrame`, 16-pt margin.
- `Tide/Dictation/DictationIndicator.swift` (new) — combines both
  above. Driven by the coordinator: `show(initialText:)` /
  `update(partial:)` / `hide()`.
- `Tide/Dictation/DictationCoordinator.swift`: subscribe to the
  recognizer's `partialTranscript` stream and call
  `indicator.update(partial:)`. On `stop()` and before any
  text-handling, `indicator.hide()`.
- Pass the `NSStatusItem` from `MenubarController` into the
  coordinator (add an init param, wire in `AppEntry`).

**Verify:**
1. Hold dictation hotkey.
2. Menubar icon flips to red-filled wave glyph immediately.
3. Floating pill appears top-right, showing "● Aufnahme…" then live
   Apple partials as you speak.
4. Release. Icon reverts, pill fades out within 150ms.
5. Tide panel does NOT open. Source app keeps focus throughout.

**Commit message:**
> feat(dictation): visual indicator — menubar tint + floating pill

---

## Phase D — TextInjector + raw-mode end-to-end

**Goal:** raw dictation works end-to-end. Hold, speak, release, text
appears at the cursor of the frontmost app.

**Files:**

- `Packages/Selection/Sources/Selection/TextInjector.swift` (new — in
  the Selection package, since the AX + clipboard logic already
  lives next door). Implements the three-strategy injection from the
  spec. Returns `enum InsertResult { case axInsert, clipboardPaste,
  pasteboardOnly }`.
- `Packages/Selection/Sources/Selection/SelectionReplacer.swift`:
  extract the existing `replaceViaClipboard` helper into a free
  `func pasteViaClipboard(_ text: String, into pid: pid_t)` that
  both `SelectionReplacer` and the new `TextInjector` share. No
  behavior change for the existing replacer.
- `Packages/Selection/Tests/SelectionTests/TextInjectorTests.swift`:
  mock the AX layer, exercise the three branches.
- `Tide/Dictation/DictationCoordinator.swift`: on `.raw` mode,
  after recognizer.stop() returns non-empty text, call
  `textInjector.insert(text)`. Empty text → notify "Zu kurz
  aufgenommen", no insert.

**Verify:**
1. Open Spark, click in a Compose-Mail Body. Hold dictation hotkey,
   say "Hallo Markus, ich freue mich auf morgen.", release.
   Sentence appears in the mail body at the cursor.
2. Open Notion in a browser. Click in a paragraph. Same test —
   expect `clipboardPaste` strategy (AX usually fails for browsers).
3. Click on the Desktop (no focused text-field). Hold-speak-release.
   Notification "Diktat in Zwischenablage" appears; ⌘V pastes the
   text in the next app you focus.

**Commit message:**
> feat(dictation): raw-mode end-to-end via TextInjector

---

## Phase E — Polish mode through Claude

**Goal:** the second hotkey runs the transcript through Claude for
grammar + punctuation cleanup before injection.

**Files:**

- `Tide/Dictation/DictationPolisher.swift` (new, MainActor). Uses
  the existing `AnthropicProvider`. Constructs a non-streaming
  `LLMMessage` array: `[system: settings.dictationPolishPrompt,
  user: raw]`. Awaits the full response, returns the assistant text
  trimmed. 8-second timeout via `Task.detached + Task.sleep`-race.
- `Tide/Dictation/DictationCoordinator.swift`: on `.polished` mode,
  between `recognizer.stop()` and `textInjector.insert(...)`, call
  `polisher.polish(raw)`. On any throw — including timeout — log a
  warning, post a User Notification "Polish fehlgeschlagen,
  Rohtext eingefügt", and inject the raw text instead. Daily-Use
  must not block.
- `TideTests/DictationPolisherTests.swift`: stub the provider, verify
  prompt construction + happy path + timeout branch.

**Verify:**
1. Settings → Dictation → set Polish hotkey to `⌃⌥D`.
2. Hold polish-hotkey, say
   "äh also ich glaube wir sollten das morgen machen oder",
   release.
3. Pill stays a beat longer than raw mode (Claude latency); then
   "Ich glaube, wir sollten das morgen machen." appears at the
   cursor.
4. Disconnect from network, repeat. After ~8s, raw text
   appears + notification.

**Commit message:**
> feat(dictation): polish mode through Claude with raw fallback

---

## Phase F — Settings UI + edge-cases + rollout

**Goal:** users can configure both hotkeys + polish-prompt from
inside Tide; CHANGELOG bumped, version bumped, release ready.

**Files:**

- `Tide/Settings/DictationSection.swift` (new). Three sections per the
  spec: Hotkeys (two `KeyboardShortcuts.Recorder` widgets),
  Polish-System-Prompt (`TextEditor`, default-restore button),
  Floating-Pill-Position (`Picker` with three options).
- `Tide/Settings/SettingsWindow.swift`: add the new tab between Voice
  and QuickActions.
- `Tide/Dictation/DictationCoordinator.swift`: edge-case polish —
  empty transcript notification, polish-without-API-key snap-back to
  raw, mic-permission-revoked branch.
- `project.yml`: `MARKETING_VERSION: "0.3.0"`, bump
  `CURRENT_PROJECT_VERSION`.
- `CHANGELOG.md`: new `## [0.3.0] — Welle 4: Standalone Dictation`
  section covering all of the above. Add a brief "kompletter QA-Lauf
  vor Tag-Push" sub-section listing the four manual tests from
  Phase D + the polish-success and polish-fail tests from Phase E.
- `docs/RELEASE.md`: add a "Welle 4 manual QA" subsection mirroring
  the CHANGELOG list.

**Verify:**
1. All previous green tests still green.
2. Run the full QA list manually.
3. `xcodegen generate && xcodebuild build -scheme Tide
   -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` is green.
4. `./scripts/release.sh --skip-notarize` produces a sane DMG.

**Commit messages:**
> feat(settings): Dictation tab (hotkeys, polish prompt, pill position)
> feat(dictation): edge-case polish (empty / no-key / no-mic)
> chore(release): bump MARKETING_VERSION to 0.3.0 + CHANGELOG

Then:
```bash
git push origin main
git tag v0.3.0
git push origin v0.3.0
```

CI's release workflow handles the rest.

---

## Sub-agent strategy

This plan has six phases of moderate independence:

- **A + B** are coupled (B uses A's shortcut names). Single agent.
- **C** is UI-only, no dependency on D/E. Parallel-safe with D.
- **D + E** both touch DictationCoordinator's `stop()` path. Serial.
- **F** is rollout — sequential, last.

Recommended dispatch: A→B in one session, then a `dispatching-parallel-agents`
run with C and D, then E sequentially, then F. Each agent gets the
spec + this plan + the prior phase's commit hash to start from.

## Risk log

- **AX-Insert reliability across apps**: the existing
  SelectionReplacer's AX path works for native AppKit apps but not
  for Electron / web-views. Mitigation: clipboard-paste fallback
  already handles the common offenders.
- **Polish prompt drift**: users editing the default may get worse
  output. Mitigation: ship a "Restore default" button in Settings.
- **Mic ownership clash with PTT**: if both PTT and a dictation
  hotkey fire near-simultaneously, the second would race the
  AudioRecorder. Mitigation: the new `isActive` lock in the
  coordinator + an existing lock would need to coordinate. Add a
  cross-handler lock in Phase F: AppEntry holds a single
  `activeRecording: AudioOwner?` enum, both handlers consult it.
- **NotificationCenter authorization on macOS 14+**: needs
  `UNUserNotificationCenter.requestAuthorization` on first use.
  Mitigation: request lazily on first dictation, swallow denial
  (text-only fallback: nothing happens visibly when permission
  denied — log only).
