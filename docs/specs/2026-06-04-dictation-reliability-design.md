# Tide — Diktat-Zuverlässigkeit — Design-Spec

**Datum:** 04. Juni 2026
**Status:** Design abgesegnet (Dominik), bereit für Implementation-Plan
**Herkunft:** 5-Subsystem-Audit (swift-best-practices). Behebt den Live-Bug
„Diktat-Text verschwindet im Nirvana" + die zugehörigen Concurrency-/Lifecycle-
Fehler im Diktat-Pfad.

---

## Problem

Diktat-Text wird intermittierend nicht eingefügt (schlimmer im Release-Build).
Root-Cause + Begleitfehler aus dem Audit:

1. **`ClipboardPaste.postCommandV`** postet 4 CGEvents ohne Delay → Modifier (⌘)
   rennt gegen V → ⌘V wird als nacktes „v" oder gar nicht interpretiert.
   Release-Build (optimiert) feuert schneller → Race kippt öfter.
2. **`TextInjector`** postet ⌘V ohne `AXIsProcessTrusted()`-Check und meldet
   `.clipboardPaste` (False-Success), wenn das Recht fehlt → Text nur in
   Zwischenablage, kein Feedback.
3. Diverse Concurrency-/Lifecycle-Fehler, die zu steckengebliebenen Aufnahmen,
   Leaks und Daten-Races führen (siehe Komponenten).

## Ziel

Diktat fügt **zuverlässig** ein (kein intermittierendes Versagen), scheitert
**sichtbar** statt still, und der Aufnahme-/Erkennungs-Pfad ist frei von den
im Audit gefundenen Races/Leaks.

Nicht-Ziel (eigene spätere Wellen): das `AppSettings`-`@Observable`-über-
UserDefaults-Redesign, die LLM-Stream-Error-Robustheit, KeychainHelper-Fehler-
unterscheidung, generelle Perf-Re-Decodes.

## Komponenten & Fixes

### A. Selection — Paste/Inject

**A1. `ClipboardPaste.paste` → `@MainActor`, async, robustes ⌘V.**
`postCommandV` setzt `.maskCommand` auf alle vier Events und postet sie mit
~8 ms `Task.sleep`-Abstand (Modifier registriert vor V), gibt `Bool` zurück
(CGEvent-Erstellung kann fehlschlagen). Pasteboard-Restore-Delay 400 → 800 ms
(async-Paste-Read von Electron/WebKit überholt sonst). Signatur:
`@MainActor static func paste(_ text: String) async -> Bool`.

**A2. `SelectionReader.sendCommandC`** (⌘C für Selektion via Clipboard-Swap):
gleiche Flag- + Inter-Event-Gap-Härtung. Bleibt synchron — der Caller-Pfad
(`MenubarController.capturePendingSelection`) ist sync; die ~24 ms `usleep`
sind gegen das bestehende 200-ms-Warten vernachlässigbar.

**A3. `TextInjector.insert` AX-Trust-Guard.** Vor Strategie-1 (Clipboard-⌘V):
wenn `AXIsProcessTrusted() == false` → **nicht** das tote ⌘V posten, sondern
direkt Pasteboard-only-Pfad + Notification:
„Bedienungshilfen-Recht fehlt — Diktat in der Zwischenablage (⌘V). Erteilen:
Einstellungen → API → Onboarding erneut starten." Kein Auto-Öffnen (Text ist
sicher, jarring vermeiden). Der AX-Check ist über einen Test-Seam
(`_isProcessTrusted: () -> Bool`, default `AXIsProcessTrusted`) injizierbar.
`insert` await-et die jetzt-async `ClipboardPaste.paste`; bei `paste == false`
(Event-Erstellung fehlgeschlagen) ebenfalls in den Pasteboard-only-Fallback.

**A4. Force-Cast-Crashes.** In `TextInjector.attemptAXInsert` und
`SelectionReader` den `focused as! AXUIElement` durch
`guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return … }`
ersetzen (fremder CFType crasht sonst).

### B. TideSpeech — Recognition-Concurrency

**B1. `AppleSpeechRecognizer` Daten-Race.** `NSLock` (bestehendes
`@unchecked Sendable`-Muster) um `request`, `task`, `lastFinalTranscript`.
Der `recognitionTask`-Callback (fremde Queue) schreibt unter Lock; `stop()`
liest unter Lock. `partialContinuation.finish()` in `stop()`. Stream +
Continuation **pro `start()` neu erzeugen** (Reusable-Contract des Protokolls),
nicht einmalig in `init`. Lock statt Actor, weil `feed(_:)` ein synchrones
Protokoll-Member ist.

**B2. `HybridRecognizer`.** `forwardTask` zu Beginn von `stop()` canceln
(vor den `await *.stop()`); Lock um `forwardTask`. Profitiert von B1-finish,
damit die Forward-Schleife terminiert.

**B3. `ElevenLabsSynthesizer` Sequence-Reset-Race.** Generation/Epoch-Token:
`speak()` taggt seine Tasks mit der aktuellen Generation; `stop()` erhöht die
Generation (statt Counter auf 0 zu resetten); Lieferungen einer alten
Generation werden verworfen → keine strandenden/kollidierenden Audio-Chunks.

### C. Dictation / Recorder / Panel

**C1. `AudioRecorder.start` Leak.** Wenn `engine.start()` (oder die Format-
Validierung) wirft, nachdem Tap installiert / Recognizer gestartet wurde:
`engine.inputNode.removeTap(onBus: 0)` + `try? await recognizer.stop()` vor
dem Rethrow. Format-Validierung möglichst **vor** `recognizer.start()`.

**C2. `DictationCoordinator.start` Interleave-Race.** Nach `await rec.start()`
prüfen, ob `self.recorder === rec` noch gilt; falls ein zwischenzeitliches
`stop()` `recorder` genullt hat → die gerade gestartete Engine/Tap sauber
abbauen (`try? await rec.stop()`), Indicator/partialTask nicht starten. Verhindert
das steckengebliebene, un-stoppbare Recording bei schnellem Tap.

**C3. `FloatingPill` un-cancelled Tasks.** Generation-Token (`Int`) +
gespeicherte Cleanup-`Task`-Referenz. `show`/`flash`/`hide` erhöhen den Token
und canceln die Pending-Task; die verzögerten Bodies (`orderOut`, `isHint`-Reset)
prüfen den Token und no-op-en, wenn eine neuere Session begonnen hat.

**C4. `ChatViewModel.startRecording` Retain.** `let stream = recorder.partialTranscript`
vor dem `Task` binden und über `stream` iterieren (statt `recorder` stark zu
halten); `partialTask?.cancel()` vor `self.recorder = nil` im Fehlerpfad,
`liveTranscript = ""` zurücksetzen.

## Fehlerbehandlung

- AX untrusted → Pasteboard-only + actionable Notification (A3).
- CGEvent-Erstellung schlägt fehl → Pasteboard-only-Fallback.
- Alle bestehenden Fallbacks (leeres Transkript, Reject-Filter, Polish-Failure)
  bleiben unverändert.

## Tests

- **`ClipboardPasteTests`** (neu, wenn `postCommandV`-Bool/Flag-Logik ohne echte
  Events testbar — sonst Build-only): Bool-Rückgabe bei Source-Fehler.
- **`TextInjectorTests`** (erweitern): mit `_isProcessTrusted = { false }` →
  Ergebnis `.pasteboardOnly`, Transkript auf Pasteboard, kein False-`.clipboardPaste`.
  Force-Cast-Guard: nicht direkt unit-testbar (System-AX) → Build/Compile.
- **`AppleSpeechRecognizer`**: Stream-Reuse soweit ohne SFSpeech mockbar; sonst
  Build + manueller Smoke. (`SFSpeechRecognizer` ist System-API.)
- **`HybridRecognizerTests`** (bestehend): weiter grün nach B2.
- **Manueller Smoke (entscheidend):** 10× hintereinander diktieren in TextEdit/
  Spark — **jedes Mal** Paste, kein Flackern, keine stuck Aufnahme; bei
  entzogenem AX-Recht → Notification + Text in Zwischenablage statt Nirvana.

## Implementation-Qualität

`swift-best-practices` + `swift-concurrency-pro` für Review der B/C-Fixes
(Lock-Korrektheit, Sendable, Continuation-Lifecycle, Generation-Token).

## Betroffene Dateien

| Datei | Fix |
|---|---|
| `Packages/Selection/Sources/Selection/ClipboardPaste.swift` | A1 |
| `Packages/Selection/Sources/Selection/SelectionReader.swift` | A2, A4 |
| `Packages/Selection/Sources/Selection/TextInjector.swift` | A3, A4 |
| `Packages/Selection/Sources/Selection/SelectionReplacer.swift` | await async paste (A1-Ripple) |
| `Packages/Selection/Tests/.../TextInjectorTests.swift` | A3-Test |
| `Packages/Speech/Sources/TideSpeech/Apple/AppleSpeechRecognizer.swift` | B1 |
| `Packages/Speech/Sources/TideSpeech/HybridRecognizer.swift` | B2 |
| `Packages/Speech/Sources/TideSpeech/ElevenLabs/ElevenLabsSynthesizer.swift` | B3 |
| `Tide/Recorder/AudioRecorder.swift` | C1 |
| `Tide/Dictation/DictationCoordinator.swift` | C2 |
| `Tide/Dictation/FloatingPill.swift` | C3 |
| `Tide/Panel/ChatViewModel.swift` | C4 |
| `CHANGELOG.md` | Eintrag |
