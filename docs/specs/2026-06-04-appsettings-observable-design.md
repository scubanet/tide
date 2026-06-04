# Tide — AppSettings Observable-Redesign — Design-Spec

**Datum:** 04. Juni 2026
**Status:** Design abgesegnet (Dominik), bereit für Implementation-Plan
**Herkunft:** App-Audit (HIGH-design): `AppSettings` ist `@Observable`, aber
alle Properties sind Computed-über-`UserDefaults` → der Macro generiert **kein**
Change-Tracking. Views kompensieren mit `@State`-Mirrors + `onChange`-Bridges.

---

## Problem

`@Observable @MainActor final class AppSettings` hat ~16 Properties, jede ein
Getter/Setter über `UserDefaults` **ohne stored backing**. Der `@Observable`-
Macro trackt nur stored Properties → Mutationen lösen **keine** SwiftUI-
Invalidierung aus. Sechs Views umgehen das mit lokalen `@State`-Spiegeln (z.B.
`recognizerChoice`, `promptText`, `terms`, `selectedModel`) plus `onChange`-
Rückschreibern — Boilerplate, der nur existiert, weil das Tracking fehlt.

## Ziel

`AppSettings` echt observable machen (stored Properties, aus `UserDefaults`
initialisiert, `didSet` persistiert) — dann die jetzt redundanten Mirror-Hacks
in den sechs Views entfernen und direkt an `settings.foo` binden.

Nicht-Ziel (bewusst, war Scope-Entscheidung): geteilte Instanz via
`@Environment` (Cross-View-Live-Sync). Jede View behält ihre eigene
`AppSettings()`-Instanz — das beseitigt die Mirror-Boilerplate, nicht die
Cross-View-Staleness (separate, größere Änderung).

## Architektur

### AppSettings — Computed → Stored-Backing
Jede Property wird eine **stored var**, im `init` aus `UserDefaults` gelesen,
mit `didSet` der nach `UserDefaults` zurückschreibt:

```swift
public var selectedModel: String {
  didSet { defaults.set(selectedModel, forKey: Key.selectedModel) }
}

public init(defaults: UserDefaults = .standard) {
  self.defaults = defaults
  // Read once; assigning in init does NOT fire didSet, so no redundant
  // write-back at startup.
  self.selectedModel = defaults.string(forKey: Key.selectedModel) ?? "claude-sonnet-4-6"
  …  // every property, default semantics preserved 1:1
}
```

**Default-Semantik exakt erhalten** (sonst Verhaltensänderung):
- `voiceEnabled`, `autoSendAfterPushToTalk`: `defaults.object(forKey:) as? Bool ?? true`
- `replaceSelectionByDefault`: `defaults.bool(forKey:)` (nil→false)
- String-Properties: `defaults.string(forKey:) ?? <default>` (incl. die `Self.default…Prompt`-Konstanten)
- `customVocabulary`: stored `[String]`; init liest den newline-String und
  splittet/trimmt/filtert (wie heute der Getter), `didSet` joined mit `\n`.

**Unverändert:** alle Property-Namen + Typen + die `static let default…Prompt`-
Konstanten + der `Key`-Enum → **kein** Call-Site-Ripple in der App-Logik
(`ChatViewModel`, `DictationPolisher`, etc. lesen weiter `settings.foo`).

`@Observable` trackt die stored vars dann automatisch — jede Mutation
invalidiert beobachtende Views.

### Views — Mirrors entfernen, direkt binden
Pro View: die nur-fürs-Tracking existierenden lokalen `@State`-Spiegel und ihre
`onChange`-Rückschreiber entfernen; im Body `@Bindable var settings = settings`
deklarieren und Controls direkt an `$settings.foo` binden (bzw. bestehende
`Binding(get:set:)` durch `$settings.foo` ersetzen — sie funktionieren jetzt
zwar korrekt, aber `$settings.foo` ist die saubere Form).

Betroffene Views + ihre Mirrors:
- **`ModelSection`** — `Binding(get:set:)` → `$settings.selectedModel`.
- **`VoiceSection`** — `recognizerChoice`-`@State`-Mirror + dessen `onChange`/`.task`-Seed
  entfernen; Recognizer-Picker direkt an `$settings.speechRecognizer` (über eine
  kleine Bridge, da der Picker die typisierte `SpeechRecognizerChoice` nutzt —
  Binding-Adapter String↔enum). Die vielen `Binding(get:set:)` (voiceEnabled,
  ttsProvider, …) → `$settings.…`. **Der Key-fehlt-Hinweis-Mechanismus
  (showRecognizerKeyMissingHint / showLocalModelMissingHint) bleibt** — er ist
  echte Logik, kein Tracking-Workaround.
- **`DictationSection`** — `selectedMode` bleibt (echte UI-Wahl, kein Mirror),
  aber `promptText`/`pillPosition`-`@State`-Spiegel + deren `onChange`/`.task`
  entfernen; den Prompt-`TextEditor` direkt an eine `$settings`-abgeleitete
  Binding für den gewählten Modus binden, Pill-Position-Picker an
  `$settings.dictationPillPosition`. „Standard wiederherstellen" schreibt direkt
  `settings.…Prompt = default`.
- **`VocabularySection`** — `terms`-`@State`-Mirror entfernen; List/Add/Delete
  direkt gegen `settings.customVocabulary` (append/remove + Zuweisung). Soft-Limit-
  Hinweis bleibt.
- **`LocalModelSection`** — `selectedModel`-`@State`-Mirror entfernen; Picker an
  `$settings.localModelName`; `catalog`/`downloading`/`downloadProgress` bleiben
  (echter View-State, kein Settings-Spiegel). Prewarm-`onChange` auf
  `settings.localModelName` umstellen.
- **`OnboardingSteps` `VoiceStep`** — `recognizer`/`tts`-`@State`-Spiegel entfernen;
  Picker direkt an `$settings.speechRecognizer` (enum-Bridge) + `$settings.ttsProvider`.

**Wichtig:** Nur Spiegel entfernen, die ausschließlich Settings tracken. Echter
View-lokaler State (Download-Progress, Picker-Auswahl die KEINE Settings ist,
Hinweis-Flags) bleibt.

## Fehlerbehandlung

Kein neuer Pfad. Reiner Refactor.

## Tests

- **`AppSettingsTests`** (bestehend, viele) müssen **unverändert grün** bleiben —
  die Round-Trip-/Default-/Parsing-Semantik ist identisch (init liest, set
  schreibt). Sie konstruieren `AppSettings(defaults:)` immer *nach* dem Setzen
  der Test-Defaults → kompatibel mit read-in-init. KEINE Teständerung nötig;
  wenn ein Test die Defaults *nach* der Konstruktion derselben Instanz ändert
  und ein Live-Reflect erwartet (sollte es nicht), wird er angepasst.
- Views: kein Unit-Test (SwiftUI) → Build + manueller Smoke je View (jede
  Einstellung ändern → wirkt + persistiert über Neustart).

## Implementation-Qualität

`swiftui-pro` + `swift-best-practices` für Review (Observation-Korrektheit,
`@Bindable`-Idiom, keine verlorene Logik).

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `Packages/Core/Sources/Core/Settings/AppSettings.swift` | Computed → Stored-Backing + init |
| `Tide/Settings/ModelSection.swift` | direkt binden |
| `Tide/Settings/VoiceSection.swift` | recognizer-Mirror raus + direkt binden |
| `Tide/Settings/DictationSection.swift` | prompt/pill-Mirror raus + direkt binden |
| `Tide/Settings/VocabularySection.swift` | terms-Mirror raus |
| `Tide/Settings/LocalModelSection.swift` | selectedModel-Mirror raus |
| `Tide/Onboarding/Steps/OnboardingSteps.swift` | VoiceStep-Mirror raus |
| `CHANGELOG.md` | Eintrag |
