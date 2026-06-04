# Tide — Hybrid-Lokal Recognizer — Design-Spec

**Datum:** 03. Juni 2026
**Status:** Design abgesegnet (Dominik), bereit für Implementation-Plan
**Herkunft:** Follow-up aus der WhisperKit-Welle — die Spec dort nannte Hybrid-Lokal explizit als „billiger Follow-up via Generalisierung von HybridRecognizer".

---

## Problem

`.whisperKit` (lokal) ist non-streaming → keine Live-Partials während der
Aufnahme (Pille zeigt nur „…"). Der bestehende `.hybrid` koppelt Apple-Live-
Partials mit einem genaueren Final-Text — aber nur via ElevenLabs (Cloud,
Key nötig). Es fehlt die Kombination **Apple-Live + WhisperKit-Final**:
sofortige Vorschau plus offline/privater, genauer Endtext.

## Ziel

Eine neue Recognizer-Wahl `.hybridLocal`: Apple liefert Live-Partials,
WhisperKit ersetzt am Ende mit der lokalen Transkription. Voll offline nach
Modell-Download, keine Cloud.

Nicht-Ziel: neue UI (Picker zeigt die Wahl automatisch), Streaming-WhisperKit.

## Befund

`HybridRecognizer` ist bereits strukturell generisch: `init(apple: any
SpeechRecognizer, eleven: any SpeechRecognizer)`. Die Logik (Apple-Partials
forwarden, `feed` an beide, auf `stop()` den secondary-Final nehmen, leer →
Apple behalten) funktioniert mit **jedem** zweiten Recognizer — inklusive
`WhisperKitRecognizer`. Nur der Parametername `eleven` und der Log-Text sind
ElevenLabs-spezifisch.

## Komponenten

### `HybridRecognizer` generalisieren
- `init(apple:secondary:)` — Parameter `eleven` → `secondary` umbenennen
  (private Property `eleven` → `secondary`).
- Log-Texte: „ElevenLabs" → „secondary".
- Logik unverändert. Rein kosmetische/Naming-Änderung; der bestehende
  `.hybrid`-Call-Site (Factory) übergibt dann `secondary:` statt `eleven:`.

### `SpeechRecognizerChoice.hybridLocal`
- Neuer Case `.hybridLocal`.
- `displayName`: „Hybrid Lokal (Apple live + WhisperKit final)".
- `requiresLocalModel = true` (der VoiceSection-No-Model-Guard greift dadurch
  automatisch — selbe Behandlung wie `.whisperKit`).
- `requiresElevenLabsKey = false`.

### `RecognizerFactory`
`.hybridLocal` muss **vor** dem `guard choice != .apple, key …`-Block behandelt
werden (sonst fällt es mangels EL-Key auf Apple zurück) — analog zum
bestehenden `.whisperKit`-Early-Return:

- `.hybridLocal` UND `localModelInstalled` UND `transcriber != nil` →
  `HybridRecognizer(apple: apple, secondary: WhisperKitRecognizer(transcriber:,
  modelName: localModelName, bufferProvider: { accumulator.exportWAV(...) },
  language: nil))`.
- `.hybridLocal` sonst → **Apple-Fallback** (geloggt), konsistent mit `.whisperKit`.

Der finale `switch` über die übrigen Choices bekommt `.hybridLocal` in den
Apple-Fallback-Arm (Exhaustiveness; unerreichbar wegen Early-Return). Der
bestehende `.hybrid`-Arm wechselt auf das `secondary:`-Label.

Vokabular geht weiter an die Apple-Hälfte (`contextualStrings` biast die
Live-Partials); der WhisperKit-Final nutzt es nicht (Polish-Pfad deckt Jargon ab).

### Prewarm (`AppEntry`)
Die Prewarm-Bedingung beim Start erweitern: Modell auch vorwärmen wenn
`speechRecognizer == .hybridLocal` (zusätzlich zu `.whisperKit`). Da beide auf
das lokale Modell angewiesen sind, dieselbe Vorwärm-Logik.

### UI
Keine neue UI. `VoiceSection`s Recognizer-Picker zeigt `.hybridLocal`
automatisch (`allCases`); der bestehende „kein lokales Modell"-Hinweis greift
über `requiresLocalModel`.

## Datenfluss

Hotkey → accumulator füllt sich → `stop()` → `HybridRecognizer.stop()`:
Apple-Final (sofort, aus Partials) + WhisperKit-Final (lokale Transkription
des akkumulierten WAV). WhisperKit-Final nicht-leer → ersetzt Apple; leer
(Modell-Fehler) → Apple behalten. → Artefakt-Filter → Insert/Transform.

## Fehlerbehandlung

- Kein Modell @ Factory → Apple-Fallback (kein Crash).
- WhisperKit-Final-Fehler → leerer String → `HybridRecognizer` behält Apple-
  Ergebnis (bestehendes Verhalten, Daily-Use blockiert nie).

## Tests

- `SpeechRecognizerChoiceTests` (erweitern): `.hybridLocal` in `allCases`,
  `requiresLocalModel == true`, `requiresElevenLabsKey == false`,
  `displayName` nicht leer.
- `HybridRecognizerTests` (anpassen): Konstruktor-Label `eleven:` → `secondary:`
  (Mocks, generisch — die Logik-Assertions bleiben unverändert).
- `RecognizerFactoryTests` (erweitern): `.hybridLocal` mit installiertem Modell
  + Mock-`Transcribing` → Ergebnis `is HybridRecognizer`; ohne Modell/Transcriber
  → `is AppleSpeechRecognizer`.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `Packages/Speech/Sources/TideSpeech/HybridRecognizer.swift` | `eleven` → `secondary` (Param + Property + Log) |
| `Packages/Speech/Sources/TideSpeech/Protocols/SpeechRecognizer.swift` | `.hybridLocal` Case + displayName + Flags |
| `Packages/Speech/Tests/TideSpeechTests/HybridRecognizerTests.swift` | Label-Rename |
| `Packages/Speech/Tests/TideSpeechTests/SpeechRecognizerChoiceTests.swift` | `.hybridLocal`-Assertions |
| `Tide/Dictation/RecognizerFactory.swift` | `.hybridLocal`-Branch + `.hybrid`-Label-Update |
| `TideTests/RecognizerFactoryTests.swift` | `.hybridLocal`-Branch-Tests |
| `Tide/AppEntry.swift` | Prewarm-Bedingung um `.hybridLocal` erweitern |
| `CHANGELOG.md` | Unreleased-Eintrag |
