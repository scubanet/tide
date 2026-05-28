# ElevenLabs Scribe Hybrid — Speech Recognition Upgrade

**Status:** Draft (User-Review pending)
**Date:** 2026-05-28
**Author:** Dominik Weckherlin (with Claude/Larry)
**Spec Owner:** Dominik
**Target Release:** Tide v0.2.0 — Welle 2

---

## 1. Kontext & Problem

### Heutiger Zustand

Tide nutzt Apple's `SFSpeechRecognizer` als einzigen STT-Provider. Vorteile:
- On-device, gratis, instant partial-results (Live-Feedback)
- Funktioniert offline

Nachteile:
- **Mittelmäßige Genauigkeit bei Tauch-Vokabular** ("Tarierung" → "Tarnung", "PADI" → "Patti")
- **Bricht bei DE-EN-Code-Switching** mitten im Satz
- Auf System-Locale begrenzt — Sprach-Switch braucht Re-Init
- iOS-Cloud-Fallback ist instabil

### Pain-Points

1. Dominik diktiert oft technische Texte (Tauch-Briefings, IDC-Materialien, AtollCard-Code-Reviews) — Apple's Erkennung produziert Tippfehler die er manuell fixen muss
2. Sätze wie "Ich brauche einen TypeScript-Hook für die Card-Inbox" werden inkonsistent transkribiert
3. Französisch-Schweizer Schüler, die später Tide nutzen könnten, hätten mit Apple's Recognizer keine gute Erfahrung

### Zielbild

ElevenLabs **Scribe** (ihr STT-Service, gelauncht Q4 2024) liefert:
- 99 Sprachen out-of-the-box
- Höhere Genauigkeit speziell bei technischem/Code-mixed Vokabular
- Saubere Code-Mixing-Behandlung (DE+EN+FR in einem Satz)

Tradeoffs:
- Non-streaming (~1-3s Latenz nach Hotkey-Release)
- Kostet ~$0.40/h (Dominik ist auf ElevenLabs-Paid-Tier für TTS)
- Braucht Netz

**Hybrid-Lösung:** Apple läuft parallel und liefert sofort partial-text (Live-Feedback wie heute), ElevenLabs läuft im Hintergrund und ersetzt den finalen Text nach 1-3s. Best-of-both.

---

## 2. Architektur-Entscheidung

**Drei Recognizer parallel, ein Coordinator.**

```
Audio (AVAudioEngine, existing)
  │
  ├─ AppleSpeechRecognizer (existing)
  │   └─ live partial-text → onPartialResult callback
  │       ↳ UI zeigt "was Apple hört" in echtzeit
  │
  └─ AudioBufferAccumulator (NEU)
      sammelt AVAudioPCMBuffer-Chunks während gesprochen wird
      │
      └─ on hotkey-release:
          ElevenLabsRecognizer (NEU)
            ├─ exportiert Buffer als WAV (16kHz mono Int16)
            ├─ POST https://api.elevenlabs.io/v1/speech-to-text
            ├─ parse response → final text
            └─ onPartialResult(finalText)  ←  ersetzt UI-Text atomar
```

**HybridRecognizer** ist ein dünner Coordinator, der beide Pfade orchestriert.

**Settings-Picker:** 3 Optionen — Apple / ElevenLabs / Hybrid. Default = **Hybrid**.

**Fallback bei ElevenLabs-Fail** (Netz weg, Timeout, 5xx, ungültige Antwort): leise Apple-Resultat behalten, kein Error-Toast. Daily-Use darf nicht blockieren.

**Replace-Timing:** sofort beim Eintreffen des ElevenLabs-Texts. Wenn User in der Zwischenzeit selber weiter-getippt hat → seine Edits bleiben, nur die nicht-editierten Teile werden ersetzt. Mechanik via `lastAppleText`-Vergleich im Coordinator.

---

## 3. ElevenLabs Scribe API

### 3.1 Endpoint

```
POST https://api.elevenlabs.io/v1/speech-to-text
Headers:
  xi-api-key: <key>
  Content-Type: multipart/form-data; boundary=...
```

### 3.2 Request-Body (multipart)

- `file`: WAV-Audio (16kHz mono PCM signed 16-bit)
- `model_id`: `"scribe_v1"` (default-stable)
- `tag_audio_events`: `"false"` (keine `[Lachen]`-Tags)
- `timestamps_granularity`: `"none"` (wir brauchen keine Word-Timestamps)
- `diarize`: `"false"` (Single-Speaker)

Optional NICHT gesetzt:
- `language_code` — Scribe auto-detected exzellent, kein Hint nötig

### 3.3 Response (JSON)

```json
{
  "text": "Vollständige Transkription als String.",
  "language_code": "de",
  "language_probability": 0.99,
  "words": []
}
```

Wir nutzen nur `text`, Rest verwerfen.

### 3.4 Audio-Format-Konvertierung

Tide's `AudioRecorder` zeichnet via `AVAudioEngine` auf — Format kommt vom Hardware-Input (oft 44.1kHz Float32 stereo). Vor dem Scribe-Upload muss `AudioBufferAccumulator`:

1. Buffer auf 16kHz Mono Int16 resamplen via `AVAudioConverter`
2. WAV-Header (RIFF + fmt + data chunks) voranstellen
3. Als `Data` zurückgeben

### 3.5 Timeout-Strategie

- HTTP-Timeout: **10 Sekunden**
- Bei >30s Audio (ungewöhnlich für Push-to-Talk) ist Scribe normalerweise <3s fertig
- Wenn Timeout greift → ElevenLabsRecognizer returnt leeren String → HybridRecognizer behält Apple-Result

---

## 4. Code-Struktur

### 4.1 Neue Files

```
Packages/Speech/Sources/TideSpeech/
├── ElevenLabs/
│   └── ElevenLabsRecognizer.swift        SpeechRecognizer-Conformer
└── HybridRecognizer.swift                 Coordinator

Packages/Speech/Tests/TideSpeechTests/
├── ElevenLabsRecognizerTests.swift        MockURLProtocol-Tests
└── HybridRecognizerTests.swift            Coordinator-Tests

Tide/Recorder/
└── AudioBufferAccumulator.swift           Buffer + 16kHz-Resample + WAV-Encode
```

### 4.2 Geänderte Files

```
Packages/Speech/Sources/TideSpeech/
├── ElevenLabs/ElevenLabsClient.swift      + transcribe(audioData:) Endpoint
└── Protocols/SpeechRecognizer.swift       + SpeechRecognizerChoice Enum

Packages/Core/Sources/Core/Settings/AppSettings.swift   + speechRecognizer-Property

Tide/
├── Settings/VoiceSection.swift            + Recognizer-Picker
├── Panel/ChatViewModel.swift              + Recognizer-Choice-Injection
└── Recorder/AudioRecorder.swift           + Tap an AudioBufferAccumulator
```

### 4.3 Key Interfaces

**`SpeechRecognizerChoice` (neu, Enum):**

```swift
public enum SpeechRecognizerChoice: String, Sendable, CaseIterable, Codable {
  case apple, elevenLabs, hybrid

  public static let `default`: Self = .hybrid

  public var displayName: String {
    switch self {
    case .apple:      "Apple (on-device, gratis)"
    case .elevenLabs: "ElevenLabs (höhere Genauigkeit)"
    case .hybrid:     "Hybrid (Apple live + ElevenLabs final)"
    }
  }
}
```

**`SpeechRecognizer` Protocol (existing, unverändert):**

```swift
public protocol SpeechRecognizer: Sendable {
  func startStreaming(onPartialResult: @escaping @Sendable (String) -> Void) async throws
  func stopStreaming() async -> String
}
```

**`ElevenLabsRecognizer` (neu):**

```swift
public final class ElevenLabsRecognizer: SpeechRecognizer {
  private let client: ElevenLabsClient
  private let buffer: AudioBufferAccumulator

  public init(client: ElevenLabsClient, buffer: AudioBufferAccumulator) {
    self.client = client
    self.buffer = buffer
  }

  public func startStreaming(onPartialResult: @escaping @Sendable (String) -> Void) async throws {
    // Scribe ist non-streaming — keine partials während des Sprechens.
    buffer.reset()
  }

  public func stopStreaming() async -> String {
    guard let wavData = buffer.exportWAV(sampleRate: 16000, channels: 1) else { return "" }
    do {
      return try await client.transcribe(audioData: wavData)
    } catch {
      return ""  // Fallback-Signal — Hybrid ignoriert das, behält Apple
    }
  }
}
```

**`HybridRecognizer` (neu):**

```swift
public final class HybridRecognizer: SpeechRecognizer {
  private let apple: AppleSpeechRecognizer
  private let eleven: ElevenLabsRecognizer

  public init(apple: AppleSpeechRecognizer, eleven: ElevenLabsRecognizer) {
    self.apple = apple
    self.eleven = eleven
  }

  public func startStreaming(onPartialResult: @escaping @Sendable (String) -> Void) async throws {
    try await eleven.startStreaming { _ in }   // never fires for ElevenLabs
    try await apple.startStreaming(onPartialResult: onPartialResult)
  }

  public func stopStreaming() async -> String {
    let appleFinal = await apple.stopStreaming()
    let elevenFinal = await eleven.stopStreaming()
    return elevenFinal.isEmpty ? appleFinal : elevenFinal
  }
}
```

**`ElevenLabsClient.transcribe(audioData:)` (neu in existing client):**

```swift
public extension ElevenLabsClient {
  func transcribe(audioData: Data) async throws -> String {
    let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 10

    let boundary = "Tide-\(UUID().uuidString)"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

    request.httpBody = multipartBody(boundary: boundary, fields: [
      "model_id":               "scribe_v1",
      "tag_audio_events":       "false",
      "timestamps_granularity": "none",
      "diarize":                "false",
    ], file: (name: "file", filename: "audio.wav",
             mime: "audio/wav", data: audioData))

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw ElevenLabsError.serverError(((response as? HTTPURLResponse)?.statusCode ?? -1))
    }

    let decoded = try JSONDecoder().decode(ScribeResponse.self, from: data)
    return decoded.text
  }
}

private struct ScribeResponse: Decodable {
  let text: String
  let language_code: String
  let language_probability: Double
}
```

---

## 5. Settings-UX

In `Tide/Settings/VoiceSection.swift`, neuer Block unter dem TTS-Picker:

```
┌──────────────────────────────────────────────────────┐
│ Spracherkennung                                       │
│                                                       │
│ ( ) Apple (on-device, sofortig, gratis)              │
│ ( ) ElevenLabs (höhere Genauigkeit, ~$0.40/h)        │
│ ●   Hybrid — Apple live + ElevenLabs final ersetzt   │
│     (empfohlen)                                       │
│                                                       │
│ ⚠ ElevenLabs API-Key wird aus Voice-Section          │
│   übernommen. Aktuell: [● gesetzt | ! fehlt]         │
└──────────────────────────────────────────────────────┘
```

### Validierung

Wenn User `elevenLabs` oder `hybrid` wählt aber kein API-Key in Voice-Section gesetzt ist:
- Selection wird sofort zurück auf `apple` korrigiert
- Inline-Hinweis: "⚠ ElevenLabs API-Key fehlt — siehe Voice-Provider oben"

---

## 6. Rollout-Plan

1. `SpeechRecognizerChoice` enum + `AppSettings.speechRecognizer` Property
2. `AudioBufferAccumulator` schreiben + Unit-Tests (WAV-Header, Resample)
3. `ElevenLabsClient.transcribe()` ergänzen + Test
4. `ElevenLabsRecognizer` implementieren + Test
5. `HybridRecognizer` implementieren + Test
6. `AudioRecorder` Tap zusätzlich an `AudioBufferAccumulator` weiterleiten
7. `ChatViewModel` — Recognizer-Choice aus Settings injizieren
8. `VoiceSection` — Picker einbauen + Validierung
9. CHANGELOG.md v0.2.0 Entry
10. Manueller Test:
    - Apple-Only: identisch zu heute
    - ElevenLabs-Only: 2-3s Lag, perfekter Text
    - Hybrid: sofortiger Apple-Text, nach 2-3s ersetzt durch ElevenLabs
    - Tauch-Slang-Test: "Tarierung in 18 Meter Tiefe bei Wreck-Dive"
    - Code-Mix-Test: "Ich brauche einen TypeScript-Hook für die Card-Inbox"

---

## 7. Out-of-Scope

- **Cost-Tracking-UI** ("Diese Woche: X Sekunden = $0.0X")
- **`language_code`-Hint** (wir lassen Scribe auto-detecten)
- **Scribe-Streaming-Endpoint** (existiert, aber Batch ist robust für sub-30s-Use)
- **Whisper als 3. Alternative** (separate Welle)
- **Audio-Event-Tags** (`[Lachen]`, `[Musik]`) — explizit deaktiviert
- **Word-Level-Timestamps** — nicht angefragt, nicht persisted

---

## 8. Open Risiken & Annahmen

1. **`AVAudioConverter` 44.1kHz → 16kHz** — Standard-Apple-API, Standard-Pattern. Mit echtem Mic-Input auf Dominiks MacBook verifizieren
2. **Scribe-Rate-Limits** — ElevenLabs Free-Tier hat sehr niedrige Limits; Dominik ist auf Paid-Tier (für TTS), genug Quota. Beim ersten Live-Test verifizieren
3. **Multipart-Upload via URLSession** — Helper-Funktion `multipartBody(boundary:fields:file:)` muss neu geschrieben werden. Standard-Pattern, ~30 Zeilen
4. **`recognizedText`-State-Race** — wenn ElevenLabs-Antwort kommt während User schon weiter-getippt hat: mitigiert durch `lastAppleText == currentRecognizedText`-Check im Hybrid-Coordinator. Wenn User editiert hat → nicht ersetzen
5. **API-Key-Reuse** — beide Endpoints (TTS + Scribe) nutzen denselben ElevenLabs-Account-Key. Kein neuer Settings-Eintrag nötig
6. **MockURLProtocol für Tests** — Pattern existiert schon im LLM-Package (`MockURLProtocol.swift`), wird in Speech-Tests übernommen

---

## 9. Akzeptanzkriterien

- [ ] `SpeechRecognizerChoice` ist persistiert in `AppSettings`
- [ ] Settings → Voice → Spracherkennungs-Picker mit 3 Optionen, default Hybrid
- [ ] Bei fehlendem API-Key + ElevenLabs/Hybrid-Auswahl → zurück auf Apple + Hinweis
- [ ] Apple-Only-Modus: identisch zu heute (kein Regression)
- [ ] ElevenLabs-Only-Modus: ~2-3s Lag, dann finaler Text in UI
- [ ] Hybrid: Apple-partial sofort sichtbar, nach ~2-3s ersetzt durch ElevenLabs (atomic swap)
- [ ] Bei ElevenLabs-Fail (Netz weg / Timeout): Hybrid behält Apple-Result, kein User-Visible-Error
- [ ] Tauch-Vokabular-Test: "Tarierung" wird korrekt erkannt
- [ ] DE+EN Code-Mixing in einem Satz sauber transkribiert
- [ ] Tests grün: `ElevenLabsRecognizerTests` + `HybridRecognizerTests` + `AudioBufferAccumulatorTests`

---

## 10. Referenzen

- [ElevenLabs Scribe Documentation](https://elevenlabs.io/docs/api-reference/speech-to-text/convert)
- Existing `Packages/Speech/Sources/TideSpeech/Apple/AppleSpeechRecognizer.swift`
- Existing `Packages/Speech/Sources/TideSpeech/ElevenLabs/ElevenLabsClient.swift` (TTS-Pattern als Referenz für Multipart)
- Existing `Packages/Speech/Sources/TideSpeech/CompositeSynthesizer.swift` (Composite-Pattern für Coordinator)
- Tide Design Spec `docs/design.md` §Speech-Recognition
