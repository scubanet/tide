# Tide — WhisperKit Lokale Transkription — Design-Spec

**Datum:** 03. Juni 2026
**Status:** Design abgesegnet (Dominik), bereit für Implementation-Plan
**Herkunft:** Idee aus Blitztext (`LocalTranscriptionService` mit WhisperKit/CoreML). An Tide-Architektur (protokoll-getriebenes `TideSpeech`-Package) angepasst.

---

## Problem

Tide transkribiert nur via Apple-Speech (on-device, aber eingeschränkt) oder
ElevenLabs Scribe (Cloud — Audio verlässt den Mac, kostet, braucht Netz). Es
fehlt eine **vollständig lokale, offline, kostenlose** STT-Option mit hoher
Genauigkeit. Für privacy-sensible Diktate (oder im Flugzeug) gibt es heute
keinen Pfad ausser Apple-Speech.

## Ziel

Ein lokaler WhisperKit/CoreML-Recognizer als neue Recognizer-Wahl. Modelle
werden in-App heruntergeladen (Fortschritt sichtbar) und in App-Support
gespeichert. Vollständig offline nach Download, null API-Kosten.

Nicht-Ziel (bewusst draussen, YAGNI / spätere Wellen):
- Hybrid-Lokal (Apple-live + WhisperKit-final) — Follow-up via Generalisierung
  von `HybridRecognizer`.
- WhisperKit-Streaming (echte Live-Partials).
- Explizite Sprach-Wahl (MVP: Auto-Detect).
- Modell-Löschen-UI (optional, nicht kerngefordert).

## Befunde

- App ist **nicht sandboxed** (`com.apple.security.app-sandbox = false`) +
  `network.client = true` → WhisperKit-Download und App-Support-Schreibzugriff
  funktionieren ohne Container-Hürden.
- WhisperKit transkribiert aus einem **Datei-Pfad** (`pipeline.transcribe(audioPath:)`),
  nicht aus einem Live-Buffer → non-streaming, exakt das Muster von
  `ElevenLabsRecognizer` (accumulator → WAV → transcribe).
- Kein App-Support-Pfad-Helper im Repo vorhanden → neu.

## Dependency

`Packages/Speech/Package.swift` bekommt `https://github.com/argmaxinc/WhisperKit`
(Produkt `WhisperKit`), gepinnt auf eine konkrete Version (`.upToNextMajor`
ab der zur Implementierungszeit aktuellen). Bricht die README-Aussage „keine
externen Dependencies ausser KeyboardShortcuts/Sparkle" — bewusst, README wird
aktualisiert.

## Komponenten (alle in `TideSpeech`)

### 1. `WhisperModelStore` (actor)

Modell-Verwaltung, kein transienter State.

- Statischer **Katalog** der 3 kuratierten Modelle (Reihenfolge = UI-Reihenfolge):
  - `openai_whisper-small_216MB` — „Whisper Small" (~216 MB), **Default**, schnell.
  - `openai_whisper-large-v3-v20240930_turbo_632MB` — „Whisper Large v3 Turbo" (~632 MB), schnell + genau.
  - `openai_whisper-large-v3-v20240930_626MB` — „Whisper Large v3" (~626 MB), genaueste.
  - Repo: `argmaxinc/whisperkit-coreml`.
- Injizierbare **Base-Directory** (default `applicationSupport/Tide/models/whisperkit`),
  damit Tests gegen eine Temp-Dir laufen.
- `modelsDirectory: URL`, `modelURL(id:) -> URL`.
- `isInstalled(_ id: String) -> Bool` — prüft ob `AudioEncoder.mlmodelc`,
  `MelSpectrogram.mlmodelc`, `TextDecoder.mlmodelc` im Modell-Ordner existieren
  (analog Blitztext `isUsableModel`).
- `installedCatalog() -> [WhisperModelInfo]` — Katalog mit `isInstalled`-Flag pro Eintrag.
- `download(id:progress:) async throws -> URL` — `WhisperKit.download(variant:downloadBase:from:)`
  in einen Temp-Ordner, Validierung (`isUsable`), atomares Move in den Ziel-Ordner,
  Temp-Cleanup. Wirft `WhisperModelError.downloadIncomplete` bei unvollständigem Modell.

`WhisperModelInfo`: `struct { id, displayName, approxSizeMB, isInstalled }`.

### 2. `WhisperKitTranscriber` (actor) + `Transcribing` Protokoll

```swift
public protocol Transcribing: Sendable {
  func transcribe(wav: Data, language: String?) async throws -> String
}
```

`WhisperKitTranscriber: Transcribing` — **ein actor, eine geteilte Instanz**
(in `AppEntry` gebaut, an die Call-Sites durchgereicht). Hält die geladene
`WhisperKit`-Pipeline actor-isoliert (`loadedModelName` + Pipeline), lädt neu
wenn ein anderer Modell-Name angefragt wird. Weil es **eine** Instanz ist,
wirkt Prewarm auch fürs spätere Diktat — die Pipeline verlässt nie ihren Actor
(wichtig unter Swift-6-strict-concurrency: `WhisperKit` ist non-Sendable, darf
nicht über Actor-Grenzen gereicht werden — ein prozess-weiter Cache-Actor wäre
hier unsauber).
- `init(store: WhisperModelStore)`.
- `prewarm(modelName:) async throws` — lädt/cached die Pipeline.
- `transcribe(wav:language:modelName:)` — schreibt `wav` in eine Temp-`.wav`,
  lädt/cached die Pipeline für `modelName`, ruft `pipeline.transcribe(audioPath:decodeOptions:)`
  mit `DecodingOptions(task: .transcribe, language: language)` (language `nil` =
  Auto-Detect), joined + trimmt das Ergebnis, löscht die Temp-Datei (defer).
  Wirft `WhisperModelError.modelMissing` wenn das Modell nicht installiert ist.

`Transcribing`-Protokoll-Signatur: `func transcribe(wav: Data, language: String?, modelName: String) async throws -> String`.

### 3. `WhisperKitRecognizer` (`SpeechRecognizer`)

Non-streaming, spiegelt `ElevenLabsRecognizer`:
- `init(transcriber: any Transcribing, modelName: String, bufferProvider: @escaping @Sendable () -> Data?, language: String?)`.
- `start()`/`feed(_:)` = no-op (Buffer kommt app-seitig via `AudioBufferAccumulator`).
- `partialTranscript` = sofort-leerer Stream (keine Live-Partials).
- `stop()` — `bufferProvider()` → nil ⇒ `""`; sonst `transcriber.transcribe(wav:language:)`.
  Bei Fehler: loggen, `""` zurück (Fallback-freundlich, greift in die Reject-Pille).

### 4. `SpeechRecognizerChoice` (erweitern)

- Neuer Case `.whisperKit`.
- `displayName`: „Lokal (WhisperKit, offline)".
- Neues Flag `requiresLocalModel: Bool` (true nur für `.whisperKit`).
- `requiresElevenLabsKey` bleibt false für `.whisperKit`.

## Wiring (App-Layer)

### `AppSettings`
- `localModelName: String` — default `"openai_whisper-small_216MB"`. UserDefaults-Key `tide.localModelName`.

### `RecognizerFactory`
Neue Parameter `localModelName: String` (default `""`) + `transcriber: (any Transcribing)?`
(default `nil` — hält die geteilte Instanz; Tests/Apple-Pfade brauchen sie nicht).
Plus `localModelInstalled: Bool` (synchroner Check, vom Call-Site via
`WhisperModelStore().isInstalled(localModelName)` ermittelt — hält die Factory
synchron + testbar). Branch:
- `.whisperKit` UND `localModelInstalled` UND `transcriber != nil` →
  `WhisperKitRecognizer(transcriber:, modelName: localModelName, bufferProvider:, language: nil)`.
- `.whisperKit` sonst → **Apple-Fallback** (geloggt), Vokabular geht an Apple.
- Bestehende Branches (apple/elevenLabs/hybrid) unverändert.

Die Call-Sites (`DictationCoordinator.start`, `ChatViewModel.startRecording`)
halten die geteilte `WhisperKitTranscriber`-Instanz (via Init durchgereicht aus
`AppEntry`) und übergeben sie + `settings.localModelName` + den
`store.isInstalled(...)`-Bool an die Factory.

### Prewarm
- **App-Start** (`AppEntry`): die eine `WhisperKitTranscriber`-Instanz wird hier
  gebaut. Wenn `speechRecognizer == .whisperKit` UND `localModelName` installiert
  → `Task { try? await transcriber.prewarm(modelName: settings.localModelName) }`.
  Lädt CoreML im Hintergrund, damit das erste Diktat keinen 1-3s-Spike hat.
  Wird nicht geladen, wenn Local nicht aktiv (kein CoreML-Overhead für Nicht-Nutzer).
- **Tab-/Modell-Wechsel**: `LocalModelSection` triggert `prewarm(modelName:)` für
  das gewählte (installierte) Modell beim Erscheinen + nach Modell-Wechsel.
  (Braucht Zugriff auf die geteilte Instanz — siehe „Wiring der geteilten Instanz".)

### Wiring der geteilten Transcriber-Instanz
`AppEntry` baut `let transcriber = WhisperKitTranscriber(store: WhisperModelStore())`
und reicht sie an `MenubarController` (→ `ChatViewModel`) und `DictationCoordinator`.
`LocalModelSection` (ein Settings-View ohne direkten DI-Pfad) erhält die Instanz
über einen schmalen `@MainActor`-Holder (z.B. `LocalTranscriberHolder.shared`,
in `AppEntry` gesetzt) — Settings-Views werden von SwiftUI ohne Konstruktor-DI
erzeugt, daher der Holder. Implementierungsdetail im Plan.

### UI — neuer Tab „Lokal" (`LocalModelSection.swift`)
- Picker über die 3 Katalog-Modelle, je mit Installiert-Badge + Grössenangabe,
  bindet an `settings.localModelName`.
- Pro nicht-installiertem gewähltem Modell: „Laden"-Button → `download(id:progress:)`,
  `ProgressView(value:)` mit Live-Prozent; bei Fertig: Installiert-✓.
- Fehlertext bei Download-Fehler.
- Hinweis-Caption: „Vollständig offline & gratis nach dem Download. Wähle
  ‚Lokal' als Recognizer unter Stimme."
- `VoiceSection`-Recognizer-Picker zeigt `.whisperKit` automatisch (`allCases`);
  wird `.whisperKit` ohne installiertes Modell gewählt → analog zum
  EL-Key-Hinweis zurückschnappen auf Apple + Hinweis „lade erst ein Modell im
  Lokal-Tab".

### App-Support-Pfad
Kleiner Helper in `TideSpeech` (z.B. statisch auf `WhisperModelStore`):
`FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask …)`
→ `…/Tide/models/whisperkit`, mit `createDirectory(withIntermediateDirectories:)`.

## Datenfluss (Standalone-Lokal-Diktat)

Hotkey → `AudioRecorder`-Tap füllt `AudioBufferAccumulator` → `stop()` →
`RecognizerFactory` baute `WhisperKitRecognizer` → `recognizer.stop()` →
`bufferProvider()` = `accumulator.exportWAV(16k mono)` → `WhisperKitTranscriber`
schreibt Temp-WAV → `WhisperKit.transcribe(audioPath:)` → Text →
`TranscriptionQuality`-Filter → Insert (bzw. Polish → Insert).

## Fehlerbehandlung

- Modell nicht installiert @ Factory-Zeit → Apple-Fallback (Log, kein Crash).
- Download-Fehler → UI-Fehlertext + Temp-Cleanup; bestehende Modelle unberührt.
- Transcribe-/Pipeline-Load-Fehler → Recognizer fängt, gibt `""` → bestehende
  Empty/Reject-Behandlung (Pille „Nichts erkannt").
- Prewarm-Fehler → still geloggt (Diktat lädt dann eben lazy).

## Tests

### Unit (Package `TideSpeechTests`)
- `WhisperModelStore` (Temp-Base-Dir injiziert):
  - Katalog hat 3 Einträge in fester Reihenfolge, small zuerst.
  - `modelURL(id:)` unter der Base-Dir.
  - `isInstalled` = false für leere Dir; true wenn die 3 `.mlmodelc`-Marker
    (als leere Ordner/Dateien angelegt) existieren.
  - `installedCatalog()` setzt `isInstalled`-Flags korrekt.
- `WhisperKitRecognizer` mit **Mock-`Transcribing`**:
  - bufferProvider liefert Data → gibt Mock-Text zurück.
  - bufferProvider nil → `""`, Transcriber nie aufgerufen.
  - Transcriber wirft → Recognizer gibt `""`.
- `SpeechRecognizerChoice`: `.whisperKit` displayName + `requiresLocalModel == true`,
  `requiresElevenLabsKey == false`; `allCases` enthält `.whisperKit`.

### Nicht testbar (manuell / integration)
- Echte WhisperKit-Transkription (CoreML + reales Modell).
- `WhisperKit.download` (Netz + HuggingFace).
- Manueller Smoke-Test: Modell laden (Progress), Recognizer „Lokal" wählen,
  diktieren offline → Text am Cursor; ohne Modell → Apple-Fallback.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `Packages/Speech/Package.swift` | WhisperKit-Dependency |
| `Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperModelStore.swift` | **neu** |
| `Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperKitTranscriber.swift` | **neu** (+ `Transcribing`) |
| `Packages/Speech/Sources/TideSpeech/WhisperKit/WhisperKitRecognizer.swift` | **neu** |
| `Packages/Speech/Sources/TideSpeech/Protocols/SpeechRecognizer.swift` | `.whisperKit` Case + Flag |
| `Packages/Speech/Tests/TideSpeechTests/WhisperModelStoreTests.swift` | **neu** |
| `Packages/Speech/Tests/TideSpeechTests/WhisperKitRecognizerTests.swift` | **neu** |
| `Packages/Speech/Tests/TideSpeechTests/SpeechRecognizerChoiceTests.swift` | **neu/erweitert** |
| `Packages/Core/Sources/Core/Settings/AppSettings.swift` | `localModelName` |
| `Packages/Core/Tests/CoreTests/AppSettingsTests.swift` | localModelName-Test |
| `Tide/Dictation/RecognizerFactory.swift` | `.whisperKit`-Branch + Fallback |
| `Tide/Dictation/DictationCoordinator.swift` | `localModelName` an Factory |
| `Tide/Panel/ChatViewModel.swift` | `localModelName` an Factory |
| `Tide/AppEntry.swift` | Prewarm-Hook beim App-Start (wenn `.whisperKit` aktiv + Modell installiert) |
| `Tide/Settings/LocalModelSection.swift` | **neu** — Download/Picker-Tab |
| `Tide/Settings/VoiceSection.swift` | `.whisperKit`-No-Model-Hinweis |
| `Tide/Settings/SettingsWindow.swift` | Tab einhängen |
| `README.md` | WhisperKit-Dependency + lokaler Modus dokumentieren |
| `CHANGELOG.md` | Unreleased-Eintrag |
