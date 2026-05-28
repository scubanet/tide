# Spec — Standalone Dictation (Tide v0.3.0)

Date: 2026-05-28
Status: approved — implementation pending
Predecessor: Welle 3 distribution pipeline shipped as v0.2.0+v0.2.1

## Problem

Tide today only knows one push-to-talk flow: hold hotkey → record →
transcribe → send to Claude → answer renders inside the Tide panel.
That's wrong for the most-frequent dictation use-case: I have a
text-field open in another app (Spark mail, Slack DM, a Notion doc, a
form in a browser), I want to dictate into it, and the LLM step
is irrelevant noise.

SuperWhisper and WisprFlow solve exactly this and have become my
muscle-memory tools. Tide already has the audio + transcription
pipeline; the missing piece is "transcribe and inject into the
frontmost app's text-cursor without ever opening Tide's own UI".

## Goals

1. Hold a dedicated dictation hotkey while a text-cursor is in
   any app → release → the transcribed text appears at that cursor.
2. The flow is **silent by default**: no Tide panel pops up, no
   focus is stolen from the source app. The only feedback is a
   menubar-icon tint change and a small floating pill in the corner
   that shows the live Apple-partial transcript.
3. Two hotkey variants:
   - **Dictate Raw** — STT result is inserted as-is.
   - **Dictate Polished** — STT result is run through Claude for
     grammar + punctuation polish (system prompt is user-editable
     in Settings) before insertion.
4. Existing push-to-talk-to-Claude flow stays untouched. Same audio
   stack, same recognizers, different coordinator.

## Non-goals

- Streaming dictation. Recording is push-to-talk only (sub-30s).
- Conversation history for dictation runs (each dictation is a
  one-shot, nothing is appended to any ConversationStore).
- Cross-platform. macOS only, same as Tide.
- Voice-activated start/stop. Hotkey-driven only.
- Auto-language detection per-dictation. ElevenLabs Scribe auto-
  detects, we don't need to specify.

## Architecture

```
TideAppDelegate
  ├─ PushToTalkHandler (existing) ── Panel + ChatViewModel
  └─ DictationHandler  (new)
       ├─ owns: DictationCoordinator
       │        ├─ AudioRecorder           (reuses existing)
       │        ├─ Recognizer pipeline     (reuses existing — Apple/EL/Hybrid)
       │        ├─ DictationIndicator      (new)
       │        │   ├─ MenubarTint         (mutates statusItem.button.image)
       │        │   └─ FloatingPill        (NSPanel, ~220x36)
       │        ├─ TextInjector            (new — wraps SelectionReplacer)
       │        └─ DictationPolisher       (new — LLMProvider call)
       └─ debounce / single-run lock (one dictation at a time)
```

### Module responsibilities

**`Tide/Dictation/DictationCoordinator.swift`** (new, MainActor)
Orchestrates a single dictation session start-to-finish. Mirrors the
shape of `ChatViewModel.startRecording` + `stopRecording` but routes
the final text to the injector instead of the LLM-stream.

Public API:
```swift
@MainActor
final class DictationCoordinator {
  func start(mode: DictationMode) async
  func stop() async   // returns nothing — text-injection happens here
  var isActive: Bool { get }
}

enum DictationMode { case raw, polished }
```

State machine:
```
idle → recording → transcribing → (polishing if .polished) → injecting → idle
                              ↘ (recognizer empty) ───────────────────↗
```

If a second `start(mode:)` is called while not-idle, it's silently
dropped (lock). Pending UX: brief notification "Diktat läuft schon"
is overkill for v1, log + ignore.

**`Tide/Dictation/DictationIndicator.swift`** (new, MainActor)
Combines two visual elements; the coordinator drives both as one.

- *Menubar tint*: swap the status-item's SF Symbol from
  `wave.3.right.circle` (template, black) to a red-filled
  `wave.3.right.circle.fill` while recording. Reverted on stop.
- *Floating pill*: a borderless `NSPanel`, 220×36, top-right of the
  primary screen with 16-pt margin. Shows a small red dot and the
  current `partialTranscript` truncated to ~30 chars with "…". Hides
  on stop with a 150ms fade.

```swift
@MainActor
final class DictationIndicator {
  init(statusItem: NSStatusItem)
  func show(initialText: String)
  func update(partial: String)
  func hide()
}
```

The pill is a separate window, *not* a child of the existing
`PanelWindow`. It's keyless (`canBecomeKey: false`), so the source
app never loses focus.

**`Tide/Dictation/TextInjector.swift`** (new, MainActor)
Inserts a string at the cursor of the frontmost app. Strategy:

1. **AX-Insert**: read the frontmost focused element via
   `AXUIElementCopyAttributeValue(kAXFocusedUIElementAttribute)`.
   If it supports `kAXSelectedTextAttribute`, set that — this replaces
   any selection with our text (or, if empty selection, just inserts
   at the cursor). Same as `Selection.SelectionReplacer` already does
   for replacement.
2. **Clipboard-Paste fallback**: if AX fails (Spark, Slack, browser
   text-fields), save the current pasteboard, set our text, send
   ⌘V to the frontmost app via `CGEvent`, then restore the previous
   pasteboard 200ms later. This is exactly what
   `SelectionReplacer.replaceViaClipboard` does today — split it out
   to be reusable.
3. **No focus / hard-fail fallback**: if neither works (no focus,
   sandboxed terminal, etc.), put the text in the pasteboard and
   post a User Notification "Diktat in Zwischenablage — ⌘V".

```swift
@MainActor
final class TextInjector {
  enum Result { case axInsert, clipboardPaste, pasteboardOnly }
  func insert(_ text: String) async -> Result
}
```

Returns the strategy used so the coordinator can log/telemetry.

**`Tide/Dictation/DictationPolisher.swift`** (new, MainActor)
For `.polished` mode: take the raw transcript, run it through the
existing `LLMProvider` (Anthropic) with a one-shot system prompt
from settings. Non-streaming — we wait for the full response.

```swift
@MainActor
final class DictationPolisher {
  init(provider: any LLMProvider, settings: AppSettings)
  func polish(_ raw: String) async throws -> String
}
```

Default system prompt (user-editable in Settings → Dictation):
```
Du bist ein Text-Editor. Korrigiere Grammatik und Punktuation im
folgenden Text. Behalte den Inhalt 1:1, kürze nichts, füge nichts
hinzu, gib KEINE Erklärungen. Antworte nur mit dem korrigierten Text.
```

Failures (no API key, network down, 5xx, timeout 8s): silently fall
back to the raw transcript and inject that, with a User Notification
"Polish-Modus fehlgeschlagen, Rohtext eingefügt".

### Hotkey wiring (`Packages/Hotkeys` + `AppEntry`)

Add two new shortcut definitions:

```swift
// Packages/Hotkeys/Sources/Hotkeys/KeyboardShortcuts+Names.swift
extension KeyboardShortcuts.Name {
  static let pushToTalk      = Self("tide.pushToTalk")
  static let dictateRaw      = Self("tide.dictateRaw",      default: nil)
  static let dictatePolished = Self("tide.dictatePolished", default: nil)
}
```

No default-binding for the new ones — user picks in Settings to avoid
collisions. Empty-by-default also means the feature is opt-in: nothing
fires until the user configures the shortcut.

`AppEntry.applicationDidFinishLaunching` adds two `KeyboardShortcuts.onKeyDown/Up`
observers for the new names, each wired to `dictationHandler.handleHold(.raw)`
/ `handleHold(.polished)`.

### Settings UI (`Tide/Settings/DictationSection.swift` — new)

A fourth top-level tab in the Settings window, between "Voice" and
"QuickActions". Sections:

1. **Hotkeys**: two `KeyboardShortcuts.Recorder` widgets (Dictate Raw,
   Dictate Polished).
2. **Polish-System-Prompt**: large `TextEditor` with the default
   string editable.
3. **Floating-Pill**: position picker (top-right / top-center /
   bottom-right). Default top-right.

## Settings additions

```swift
// AppSettings.swift
public var dictationPolishPrompt: String {
  get { defaults.string(forKey: Key.dictationPolishPrompt)
        ?? "Du bist ein Text-Editor. ... (default above)" }
  set { defaults.set(newValue, forKey: Key.dictationPolishPrompt) }
}
public var dictationPillPosition: String {   // "topRight" | "topCenter" | "bottomRight"
  get { defaults.string(forKey: Key.dictationPillPosition) ?? "topRight" }
  set { defaults.set(newValue, forKey: Key.dictationPillPosition) }
}
```

Hotkey persistence is owned by the KeyboardShortcuts library itself,
not our `AppSettings`.

## Edge cases

- **Tide panel currently focused** when hotkey fires: insert into
  the panel's TextField (treat as just another frontmost text-field).
  No special-casing needed — the AX-Insert path picks the panel's
  TextField as focused element.
- **No focused text-field** (Finder window, Desktop): TextInjector
  falls through to `pasteboardOnly` + notification.
- **Hotkey released before recognizer is ready** (sub-200ms hold):
  `recognizer.stop()` returns empty; log + show notification "Zu kurz
  aufgenommen, nichts zu transkribieren". Don't inject empty string.
- **Concurrent run**: second hold while first is still polishing →
  ignored. Coordinator's `isActive` is the single source of truth.
- **Polish mode but no Anthropic API key**: snap back to raw +
  notification "Kein API-Key — Rohtext eingefügt".
- **Mic permission revoked** between launches: AudioRecorder errors
  on `start()`; the coordinator catches and shows "Mikrofon-Zugriff
  fehlt — bitte in Systemeinstellungen erlauben" notification.
- **TextInjector clipboard restore race**: 200ms before restore. If
  the user manually copies something else in those 200ms, we'd
  overwrite their copy. Acceptable trade-off — same risk as today's
  SelectionReplacer fallback.
- **AppleScript-blocked apps** (1Password, some sandboxed apps): AX
  path fails; clipboard-paste also fails because the target blocks
  ⌘V; we land in `pasteboardOnly` and notify. Documented limitation,
  not a fixable bug.

## Backwards compatibility

- Push-to-talk-to-Claude flow: untouched. Same `KeyboardShortcuts.Name.pushToTalk`,
  same default `fn`, same `ChatViewModel.startRecording()`.
- AppSettings reads of new keys collapse to default on first launch.
- Existing v0.2.1 users get a no-op until they configure either
  dictation hotkey in Settings.

## Open questions — resolved during section approval

1. **Dictate-Hotkey default binding?** → None. Opt-in. User picks.
2. **Polish-Modus: client- vs server-side?** → Client (existing
   AnthropicProvider). No server, no extra infra.
3. **Multi-language polish?** → System prompt is text — user adapts
   per language themselves. No locale logic in code.
4. **Indicator on second monitor?** → Pill goes on the primary
   screen (the one with the menubar). Pragmatic, can revisit.
5. **Telemetry?** → No. Just `os_log` debug lines under
   `swiss.weckherlin.tide:dictation`.

## Testing strategy

- `DictationCoordinatorTests`: state machine through .raw and
  .polished happy paths, plus error branches (empty recognizer,
  polish failure).
- `TextInjectorTests`: mock the AX/clipboard paths, verify which
  branch is selected for various focused-element shapes. End-to-end
  AX manipulation isn't unit-testable.
- `DictationPolisherTests`: stub `LLMProvider`, verify the system
  prompt is injected and the raw text is passed as user-message.
  Timeout branch (8s).
- Manual QA checklist in `docs/RELEASE.md` (#Welle 4 section): run a
  raw dictation into Spark, into Notion-web, into a Terminal, into
  a 1Password field. Verify the four fallback paths.

## Roadmap downstream

After v0.3.0 ships:
- v0.3.1: Dictation history (last 10 raw transcripts, click to
  re-inject) — small, useful.
- v0.4.0: Welle 5 — Onboarding + Crash-Reporting (pushed back from
  original Welle 4 slot).
- Eventually: streaming dictation with continuous mode (toggle, not
  push-to-talk).
