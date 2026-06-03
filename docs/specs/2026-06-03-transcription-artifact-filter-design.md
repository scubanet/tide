# Tide — Transkriptions-Artefakt-Filter — Design-Spec

**Datum:** 03. Juni 2026
**Status:** Design abgesegnet (Dominik), bereit für Implementation-Plan
**Herkunft:** Idee portiert aus Blitztext (`TranscriptionQualityService`), angepasst an Tide-Architektur.

---

## Problem

Tide hat keinen Guard gegen ASR-Artefakte. Bei sehr kurzem Hotkey-Tipp,
versehentlichem Doppel-Druck oder Stille spuckt Apple-Speech / ElevenLabs
gelegentlich Halluzinations-Text aus ("Untertitel…", "Thank you", o.ä.).

Im **Standalone-Diktat** landet dieser Müll direkt am Cursor in der
Fremd-App — der größte Schmerz im Daily-Use. Im **PTT-Chat** erzeugt er
eine Müll-Bubble plus einen verschwendeten Claude-Call.

Aktuell prüft der Code nur `trimmed.isEmpty`. Das fängt leere Aufnahmen,
aber keine Halluzinationen mit Inhalt.

## Ziel

Eine reine, getestete Filter-Logik, die vor dem Insert (Diktat) bzw. vor
dem Senden (Chat) entscheidet, ob eine Transkription verworfen wird —
basierend auf Aufnahme-Dauer und Text-Charakteristik.

Nicht-Ziel: ML-basierte Erkennung, Konfigurierbarkeit der Schwellen im UI,
Sprach-Erkennung. (YAGNI — Schwellen sind Code-Konstanten.)

## Architektur

### Neue Komponente: `TranscriptionQuality`

`enum TranscriptionQuality` in `Packages/Speech/Sources/TideSpeech/`.
Reine Foundation-Logik, keine Instanz-State, statische Funktionen.

```
public enum TranscriptionQuality {
  static let minimumRecordingDuration: TimeInterval = 0.3

  static func shouldRejectRecording(duration: TimeInterval) -> Bool
  static func isLikelyArtifact(_ text: String, recordingDuration: TimeInterval) -> Bool
}
```

**Schwellen** (portiert aus Blitztext, als Konstanten — später tunebar):
- `shouldRejectRecording`: `duration < 0.3`
- `isLikelyArtifact`:
  - leerer/whitespace-only Text → `true`
  - 0 Buchstaben (nur Satzzeichen/Zahlen) → `true`
  - `duration < 0.55` UND (`wordCount >= 5` ODER `charCount >= 32`) → `true`
  - `duration < 0.8` UND `charCount >= 56` → `true`
  - sonst `false`

**Platzierung-Begründung:** Beide Consumer (`ChatViewModel`,
`DictationCoordinator`) importieren `TideSpeech` bereits. Die Logik gehört
semantisch zur Transkriptions-Qualität. `Core` wäre auch möglich, ist aber
weiter weg vom Speech-Domänenkontext.

### Duration-Quelle: `AudioBufferAccumulator.duration`

Der `AudioRecorder` trackt keine Aufnahme-Dauer. Der bereits vorhandene
`AudioBufferAccumulator` kennt aber `frameCount` und `inputFormat` →
Dauer ist ableitbar.

Neue computed property (lock-guarded, wie der Rest der Klasse):

```
public var duration: TimeInterval {
  // frameCount / inputFormat.sampleRate; 0 wenn kein Format gepuffert
}
```

Lesbar über `recorder.bufferAccumulator.duration` nach `stop()` — die
Chunks bleiben gepuffert bis zum nächsten `reset()` (das erst beim nächsten
`start()` passiert).

## Integration

### Diktat — `DictationCoordinator.stop()`

Nach dem Trimmen des `finalText`:

```
let duration = rec.bufferAccumulator.duration
let isReject = trimmed.isEmpty
  || TranscriptionQuality.shouldRejectRecording(duration: duration)
  || TranscriptionQuality.isLikelyArtifact(trimmed, recordingDuration: duration)
guard !isReject else {
  indicator?.flash("Nichts erkannt")
  return
}
```

Ersetzt die bisherige `TextInjector.notifyTranscriptTooShort()`-Notification
(Dominik wählte Pille-Hinweis statt Notification-Center-Toast).

### PTT-Chat — `ChatViewModel.stopRecording()`

Nach dem Trimmen, gleiche Prüfung. Bei Reject: **still verwerfen** — kein
`input = trimmed`, kein `send()`, nur das normale Cleanup (`isRecording =
false`, recorder/partialTask aufräumen). Kein Pille-Hinweis (Panel-Kontext,
der User sieht ohnehin das leere Eingabefeld).

## Pille-Flash (neu)

Der `DictationCoordinator` ruft `indicator?.hide()` bereits *vor* dem
`await rec.stop()`. Beim Reject ist die Pille also schon ausgefadet. Der
Flash muss sie kurz neu zeigen.

### `FloatingPill.flash(_ message: String, duration: TimeInterval = 1.2)`

Zeigt die Pille mit Hinweistext (grauer statt roter Punkt → kein
"Aufnahme läuft"-Eindruck), faded nach `duration` aus. Reuse der
bestehenden `hide()`-Fade-Mechanik.

### `PillViewState.isHint: Bool`

Neues Flag. `PillContents` schaltet darüber Punkt-Farbe (rot →
sekundär-grau) und unterdrückt den "Aufnahme…"-Platzhalter — der
Hint-Text wird immer gezeigt.

### `DictationIndicator.flash(_ message: String)`

Dünner Pass-through auf `pill.flash(message)`. Der Menubar-Tint bleibt
unberührt (war beim Reject schon deaktiviert).

## Fehlerbehandlung

- Kein neuer Fehlerpfad. Der Filter ist eine reine Boolean-Entscheidung.
- `duration == 0` (kein Audio gepuffert, z.B. Apple-only ohne Accumulator-
  Nutzung): `shouldRejectRecording(0)` → `true`. Konsistent mit "nichts
  aufgenommen". Apple-Recognizer pusht trotzdem in den Accumulator (der Tap
  läuft immer), also ist die Dauer auch im Apple-only-Pfad korrekt.

## Tests (TDD)

### `TranscriptionQualityTests` (neu, `TideSpeechTests`)
- `shouldRejectRecording`: knapp unter / über 0.3s
- `isLikelyArtifact`: leer, whitespace-only, nur-Satzzeichen (0 Buchstaben),
  kurz+viel-Text (0.5s/6 Wörter → reject), kurz+wenig (0.5s/2 Wörter → ok),
  mittel+lang (0.7s/60 chars → reject), lang+lang (1.5s/200 chars → ok)

### `AudioBufferAccumulatorTests` (erweitern, existiert)
- `duration`: kein Format → 0; bekannte frameCount/sampleRate → erwarteter Wert

### Integration (manuell, Daily-Use)
- Kurzer Hotkey-Doppel-Tipp im Diktat → Pille „Nichts erkannt", kein Insert
- Normale Aufnahme → unverändert eingefügt
- Kurzer Tipp im PTT-Chat → keine Bubble, kein Claude-Call

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `Packages/Speech/Sources/TideSpeech/TranscriptionQuality.swift` | neu |
| `Packages/Speech/Tests/TideSpeechTests/TranscriptionQualityTests.swift` | neu |
| `Tide/Recorder/AudioBufferAccumulator.swift` | `duration`-Property |
| `TideTests/AudioBufferAccumulatorTests.swift` | duration-Tests |
| `Tide/Dictation/DictationCoordinator.swift` | Reject-Guard + flash |
| `Tide/Dictation/FloatingPill.swift` | `flash()` + `isHint` |
| `Tide/Dictation/DictationIndicator.swift` | `flash()` pass-through |
| `Tide/Panel/ChatViewModel.swift` | Reject-Guard (still verwerfen) |
