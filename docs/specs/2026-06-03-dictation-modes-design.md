# Tide — Dictation-Modi — Design-Spec

**Datum:** 03. Juni 2026
**Status:** Design abgesegnet (Dominik), bereit für Implementation-Plan
**Herkunft:** Idee aus Blitztext (Workflow-„Personalities": Dampf ablassen, Emoji). Generalisiert tides bestehenden Polish-Modus.

---

## Problem

Standalone-Diktat hat heute zwei Modi: `raw` (verbatim) und `polished`
(Grammatik/Punktuation via Claude). Verschiedene Schreib-Absichten — eine
genervte Nachricht versachlichen, Gedanken zu Stichpunkten, casual →
formell — gehen nicht ohne den Text nachträglich von Hand umzuschreiben.

## Ziel

Vier neue Transform-Modi neben `raw`/`polished`, jeder mit eigenem opt-in
Hotkey und editierbarem System-Prompt: **Calmer** (Wut → ruhig), **Emoji**,
**Bullets** (Stichpunkte), **Professional** (formeller Ton).

Nicht-Ziel (YAGNI): user-definierbare Custom-Transforms (das wäre die
„Bibliothek"-Variante mit aktiver Auswahl statt Pro-Modus-Hotkey).

## Architektur

Alle Transform-Modi laufen über denselben Pfad wie `polished` heute —
`DictationPolisher` mit einem modus-spezifischen System-Prompt. `raw` bleibt
der Sonderfall (kein LLM, verbatim insert). Damit ist ein neuer Modus
= ein Hotkey + ein Default-Prompt + ein Settings-Override, ohne neue
Verarbeitungslogik.

### `DictationMode` (erweitern)

Von `{raw, polished}` zu:

```swift
enum DictationMode: String, CaseIterable {
  case raw, polished, calmer, emoji, bullets, professional
}
```

App-seitiger Helper (in `DictationCoordinator.swift` oder daneben):
- `var isRaw: Bool { self == .raw }`
- `var displayName: String` (für UI)
- `func basePrompt(from settings: AppSettings) -> String?` — `nil` für `.raw`,
  sonst der jeweilige Settings-Prompt (`settings.dictationPolishPrompt` für
  `.polished`, `settings.dictationCalmerPrompt` für `.calmer`, usw.).

### `DictationPolisher` generalisieren

Heute liest `polish(_ raw:)` intern `settings.dictationPolishPrompt` und baut
`systemPrompt = Self.systemPrompt(base: settings.dictationPolishPrompt,
vocabulary: settings.customVocabulary)`.

Ändern zu:

```swift
func polish(_ raw: String, basePrompt: String) async throws -> String
```

`systemPrompt` wird dann aus dem übergebenen `basePrompt` + Vokabular gebaut
(`Self.systemPrompt(base: basePrompt, vocabulary: settings.customVocabulary)`).
Alles andere (Timeout, Fallback, Streaming-Drain) unverändert. Der einzige
Aufrufer ist `DictationCoordinator`.

### `DictationCoordinator.stop()`

Der bestehende `switch currentMode { case .raw … case .polished … }` wird:

```swift
if currentMode.isRaw {
  insert(trimmed)
} else {
  let base = currentMode.basePrompt(from: settings) ?? ""
  do {
    let transformed = try await polisher.polish(trimmed, basePrompt: base)
    insert(transformed)
  } catch {
    insert(trimmed)          // bestehender Roh-Fallback
    notifyPolishFailed()     // bestehende Notification
  }
}
```

(Artefakt-Filter-Reject-Guard aus #1 bleibt davor unverändert.)

## Settings — 4 neue Prompts

`AppSettings`, je get/set mit Default (UserDefaults-Keys
`tide.dictation<Mode>Prompt`). Defaults sprachunabhängig formuliert
(„Reply in the SAME language as the input", wie der bestehende Polish-Default):

- **`dictationCalmerPrompt`** — „You are an editor. Rewrite the user's text as a
  calm, factual, professional message. Keep the core point but remove anger,
  insults and venting. Reply in the SAME language as the input. Output ONLY the
  rewritten message."
- **`dictationEmojiPrompt`** — „Add a few fitting emojis to the user's text to
  match its tone. Do not otherwise change the wording. Reply in the SAME
  language. Output ONLY the text with emojis."
- **`dictationBulletsPrompt`** — „Convert the user's spoken thoughts into a clean
  bullet-point list. Keep all key points, add nothing. Reply in the SAME
  language. Output ONLY the bullet list."
- **`dictationProfessionalPrompt`** — „Rewrite the user's text in a more formal,
  professional business tone. Keep the meaning, do not add or remove content.
  Reply in the SAME language. Output ONLY the rewritten text."

`dictationPolishPrompt` existiert bereits unverändert.

**Default-Prompts als single source:** je Default als `public static let
defaultCalmerPrompt` usw. auf `AppSettings`. Der Property-Getter fällt darauf
zurück (`defaults.string(forKey:) ?? Self.defaultCalmerPrompt`) UND
`DictationSection`s „Standard wiederherstellen" liest dieselbe Konstante — kein
Default-Drift zwischen Getter und UI. (Der bestehende
`DictationSection.defaultPolishPrompt`-Privatwert wandert mit auf AppSettings
als `defaultPolishPrompt`, damit alle fünf Defaults an einer Stelle liegen.)

## Hotkeys

4 neue `KeyboardShortcuts.Name` in `Packages/Hotkeys/Sources/Hotkeys/Names.swift`:
`dictateCalmer`, `dictateEmoji`, `dictateBullets`, `dictateProfessional` —
alle `default: nil` (opt-in, kein Auto-Binding, wie `dictateRaw`/`dictatePolished`).

`AppEntry`: 4 neue `onKeyDown`/`onKeyUp`-Paare, analog zu den bestehenden —
`onKeyDown → coordinator.start(mode: .calmer)` usw., `onKeyUp → coordinator.stop()`.

`HotkeySection`: 4 neue `KeyboardShortcuts.Recorder`-Widgets unter den
bestehenden zwei Diktat-Recordern.

## DictationSection UI (Picker → Editor)

Statt nur des Polish-Prompt-Editors: ein `Picker` „Modus" über die fünf
Transform-Modi (polished/calmer/emoji/bullets/professional — **nicht** raw,
das hat keinen Prompt). Darunter der `TextEditor` für den Prompt des gewählten
Modus + „Standard wiederherstellen" (setzt den jeweiligen Default). Beim
Modus-Wechsel lädt der Editor den Prompt des neuen Modus; Schreiben speichert
in den jeweiligen Settings-Key. Pille-Position-Section bleibt unverändert.

## Fehlerbehandlung

Kein neuer Pfad — jeder Transform-Modus erbt den bestehenden Polish-Fallback
(LLM-Fehler/Timeout/leere Antwort → Roh-Text insert + „Polish-Modus
fehlgeschlagen"-Notification). Leerer basePrompt (sollte nicht vorkommen, da
Defaults gesetzt) → Claude kriegt einen leeren System-Prompt; harmlos.

## Tests

### `AppSettingsTests` (CoreTests, erweitern)
- Default-Werte der 4 neuen Prompts (nicht leer, je der erwartete Default).
- Round-Trip der 4 neuen Prompts.

### `DictationModeTests` (neu, app-target `TideTests`)
- `basePrompt(from:)`: `.raw` → nil; jeder Transform-Modus → der passende
  Settings-Prompt (set distinct value per mode, assert match).
- `isRaw` nur für `.raw` true.
- `CaseIterable` enthält alle 6.

### `DictationPolisherTests` (TideTests, anpassen + erweitern)
- Bestehende Tests auf die neue Signatur `polish(_:basePrompt:)` umstellen
  (basePrompt explizit übergeben statt impliziter Settings-Lesung).
- Test: der übergebene `basePrompt` landet (mit Vokabular-Suffix) im an den
  Provider weitergereichten System-Prompt.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `Tide/Dictation/DictationCoordinator.swift` | `DictationMode` erweitern + `isRaw`/`displayName`/`basePrompt(from:)` + `stop()`-Switch generalisieren |
| `Tide/Dictation/DictationPolisher.swift` | `polish(_:basePrompt:)`-Signatur |
| `TideTests/DictationPolisherTests.swift` | Signatur anpassen + basePrompt-Test |
| `TideTests/DictationModeTests.swift` | **neu** |
| `Packages/Core/Sources/Core/Settings/AppSettings.swift` | 4 neue Prompt-Properties + Keys |
| `Packages/Core/Tests/CoreTests/AppSettingsTests.swift` | Default + Round-Trip Tests |
| `Packages/Hotkeys/Sources/Hotkeys/Names.swift` | 4 neue Namen |
| `Tide/AppEntry.swift` | 4 neue Hotkey-Wirings |
| `Tide/Settings/HotkeySection.swift` | 4 neue Recorder-Widgets |
| `Tide/Settings/DictationSection.swift` | Picker→Editor über 5 Modi |
| `CHANGELOG.md` | Unreleased-Eintrag |
