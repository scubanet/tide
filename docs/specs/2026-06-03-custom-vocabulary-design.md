# Tide — Custom-Vokabular — Design-Spec

**Datum:** 03. Juni 2026
**Status:** Design abgesegnet (Dominik), bereit für Implementation-Plan
**Herkunft:** Idee aus Blitztext (`customTerms`-Vocabulary-Hints). An Tide-Architektur angepasst — ElevenLabs Scribe kennt keine Keyword-Bias-API, daher zweigleisiger Ansatz.

---

## Problem

Domänen-Begriffe werden falsch transkribiert. Dominik = PADI Course Director:
„PADI", „SeaExplorers", „Rescue Diver", Eigennamen, Brands (AtollCal) landen
als „patty", „sea explorers" o.ä. am Cursor. Tide hat keinen Mechanismus, dem
Recognizer oder dem Polish-Schritt bekanntes Vokabular mitzugeben.

## Ziel

Eine vom User pflegbare Begriffsliste, die (A) die Apple-Spracherkennung
biast und (B) im Polish-Schritt an Claude weitergegeben wird, damit Jargon
korrekt geschrieben wird.

Nicht-Ziel: ElevenLabs-Scribe-Bias (API kennt keinen Keyterm-Parameter),
PTT-Chat-System-Prompt-Injektion (würde jeden Chat aufblähen), pro-Begriff-
Aussprache-Hints, Import/Export. (YAGNI.)

## Architektur-Befund

**ElevenLabs Scribe hat keine Keyword-Bias-API** (anders als OpenAI-Whisper,
das Blitztext nutzte — dort ging es via `prompt`-Param). Der vorhandene
`ElevenLabsClient.transcribe` sendet feste Felder, kein Bias-Feld existiert.
Daher zwei unabhängige Mechanismen statt einem:

- **A) Apple-Bias** über `SFSpeechAudioBufferRecognitionRequest.contextualStrings`
  — beeinflusst die Erkennung, wirkt aber nur dort wo der Apple-Recognizer
  läuft (Apple-Modus komplett; Hybrid nur die Live-Partials, nicht der
  ElevenLabs-Final-Text).
- **B) Polish-Prompt-Injektion** — die Begriffe werden dem System-Prompt der
  polished-Diktat-Sitzung angehängt. Claude korrigiert Jargon im Final-Text,
  unabhängig vom Recognizer.

### Abdeckungs-Matrix

| Recognizer | Raw-Diktat | Polished-Diktat | PTT-Chat |
|---|---|---|---|
| Apple | A | A + B | A (Live-Partials) |
| Hybrid | A (Live, nicht final) | B | A (Live-Partials) |
| ElevenLabs | — | B | — |

PTT-Chat profitiert nur von A (Live-Partials), nicht von B — bewusst, um den
Chat-System-Prompt nicht zu verwässern.

## Komponenten

### Speicherung — `AppSettings.customVocabulary: [String]`

Neuer UserDefaults-Key `tide.customVocabulary`, gespeichert als
newline-getrennter String. Bleibt in `Core` (nur Strings, keine
`TideSpeech`-Dependency — mirror des `speechRecognizer`-Patterns).

```swift
public var customVocabulary: [String] {
  get {
    (defaults.string(forKey: Key.customVocabulary) ?? "")
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }
  set {
    defaults.set(newValue.joined(separator: "\n"), forKey: Key.customVocabulary)
  }
}
```

Getter normalisiert (trim + Leerzeilen raus) — Konsumenten kriegen immer eine
saubere Liste. Default: leer → beide Mechanismen sind no-ops.

### A) Apple-Recognizer-Bias

- `AppleSpeechRecognizer.init(locale:contextualStrings: [String] = [])`. In
  `start()`: `req.contextualStrings = contextualStrings`.
- `RecognizerFactory.make(for:apiKey:accumulator:vocabulary:)` — neuer
  `vocabulary: [String]`-Parameter (default `[]` für Tests/Rückwärtskompat).
  Wird an den `AppleSpeechRecognizer()`-Konstruktor durchgereicht (auch im
  Hybrid-Zweig, dessen Apple-Hälfte die Live-Partials liefert).
- Call-Sites `DictationCoordinator.start` und `ChatViewModel.startRecording`
  übergeben `settings.customVocabulary`.

### B) Polish-Prompt-Injektion

- `DictationPolisher.polish` baut den System-Prompt: wenn
  `settings.customVocabulary` nicht leer, hänge eine Zeile an:

  ```
  \n\nDomain terms that may appear in the text — spell them exactly as
  written, correcting any phonetic mis-transcription: PADI, SeaExplorers, …
  ```

  (Begriffe komma-separiert.) Leeres Vokabular → kein Suffix, Prompt
  unverändert.
- Greift nur im polished-Diktat. Raw + PTT-Chat unberührt von B.

### UI — neuer Tab „Vokabular"

- `Tide/Settings/VocabularySection.swift`, eingehängt in `SettingsWindow`
  als `TabView`-Item: `Label("Vokabular", systemImage: "character.book.closed")`.
- Listen-Editor: eine `List` mit löschbaren Zeilen (`onDelete`) + ein
  TextField „Begriff hinzufügen" mit Add-Button. Bindet an
  `AppSettings.customVocabulary` (lokaler `@State [String]`-Spiegel, auf
  `customVocabulary` zurückgeschrieben bei Änderung — wie `DictationSection`
  ihren Prompt spiegelt).
- **Soft-Hinweis** ab >50 Begriffen: grauer Caption-Text „Apple empfiehlt
  unter 100 Begriffe; sehr lange Listen können die Erkennung verschlechtern."
  Kein Hard-Cap.

## Fehlerbehandlung

Kein neuer Fehlerpfad. Leeres/whitespace-Vokabular degradiert zu no-op in
beiden Mechanismen. Apple ignoriert unbekannte contextualStrings stillschweigend.

## Tests

### `AppSettingsTests` (erweitern, CoreTests)
- `customVocabulary` Round-Trip (set `["PADI","Nitrox"]` → get gleich)
- Newline-Parsing: roher String `"PADI\n\n  Nitrox  \n"` → `["PADI","Nitrox"]`
  (Leerzeilen raus, getrimmt)
- Default leer → `[]`

### `DictationPolisherTests` (erweitern)
- Bei gesetztem Vokabular enthält der an den Mock-Provider weitergereichte
  System-Prompt die Begriffe (der Mock captured `systemPrompt` bereits — siehe
  bestehender „System-Prompt-Forwarding"-Test).
- Bei leerem Vokabular ist der System-Prompt unverändert (== base prompt).

### Nicht getestet
- Apple `contextualStrings`-Effekt: `SFSpeechRecognizer` ist nicht
  unit-testbar (System-Service, kein Mock). Nur Compile-Wiring +
  `RecognizerFactory`-Parameter-Durchreichung.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `Packages/Core/Sources/Core/Settings/AppSettings.swift` | `customVocabulary` + Key |
| `Packages/Core/Tests/CoreTests/AppSettingsTests.swift` | Vocab-Tests |
| `Packages/Speech/Sources/TideSpeech/Apple/AppleSpeechRecognizer.swift` | `contextualStrings`-Param |
| `Tide/Dictation/RecognizerFactory.swift` | `vocabulary`-Param durchreichen |
| `Tide/Dictation/DictationPolisher.swift` | Vocab-Suffix im System-Prompt |
| `TideTests/DictationPolisherTests.swift` | Vocab-Injektion-Tests |
| `Tide/Dictation/DictationCoordinator.swift` | `settings.customVocabulary` an Factory |
| `Tide/Panel/ChatViewModel.swift` | `settings.customVocabulary` an Factory |
| `Tide/Settings/VocabularySection.swift` | **neu** — Editor-Tab |
| `Tide/Settings/SettingsWindow.swift` | Tab einhängen |
