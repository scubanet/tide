# Changelog — Tide

Format orientiert an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
Versionsschema folgt [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Aktuelle Phase: **pre-release, daily-use by author**, signiertes + notarisiertes DMG via Sparkle-Auto-Update.

---

## [0.2.1] — Diktiermodus (28.05.2026)

### Added

- **Settings → Push-to-Talk-Verhalten → "Nach Push-to-Talk automatisch senden"** — Toggle, default an. Wenn aus: transkribierter Text landet im Eingabefeld zum Editieren und manuellen Absenden via Return. Reiner Diktiermodus für längere oder zu polierende Texte
- `AppSettings.autoSendAfterPushToTalk` als persisted Preference (UserDefaults, default `true`, kompatibel mit Bestandsnutzern)

---

## [0.2.0] — Welle 2: ElevenLabs Scribe Hybrid + Distribution-Pipeline (28.05.2026)

### Added

- **ElevenLabs Scribe** als zweiter STT-Provider (`ElevenLabsRecognizer`)
- **Hybrid-Modus**: Apple liefert live partial-text während des Sprechens, ElevenLabs Scribe ersetzt nach 1-3s mit höher-genauer Transkription
- **Settings → Voice → Spracherkennung**: 3-Optionen-Picker (Apple / ElevenLabs / Hybrid), default Hybrid
- **AudioBufferAccumulator**: thread-safe Buffer für AVAudioPCMBuffer-Chunks, mit Resample auf 16kHz Mono Int16 + WAV-Encode
- **Multipart-Upload-Helper** in ElevenLabsClient für Scribe-API
- **Stop-Button für TTS** in der Top-Bar (`⌘.` Shortcut) — bricht laufende Sprachausgabe + leert die pending Sentence-Queue
- **Distribution-Pipeline** (Welle 3): Sparkle EdDSA-Key in Info.plist, `scripts/release.sh` (archive → sign → notarize → DMG), `scripts/sign_appcast.sh`, `.github/workflows/release.yml` (auto-publish bei `git tag v*`), Runbook in `docs/RELEASE.md`

### Fixed

- **Crash beim Aufnahme-Stop** im ElevenLabs/Hybrid-Modus — der `bufferProvider`-Closure rief `MainActor.assumeIsolated` aus dem async Executor von `ElevenLabsRecognizer.stop()` auf und triggerte `_dispatch_assert_queue_fail`. Fix: `AudioBufferAccumulator` wird in `ChatViewModel.startRecording` vorab erzeugt und an `makeRecognizer` + `AudioRecorder` durchgereicht — die Closure capturet ihn direkt, kein `self`, kein MainActor-Hop
- **Settings-Picker für Spracherkennung** ließ nur Hybrid markieren. `AppSettings.speechRecognizer` ist eine computed Property über `UserDefaults`, die der `@Observable`-Macro nicht trackt — SwiftUI re-renderte den Radio-Picker nie. Fix: `VoiceSection` spiegelt die Auswahl in lokalem `@State`, syncronisiert zu Settings via `onChange`

### Architektur-Entscheidungen

- **Non-streaming Scribe** statt streaming-Endpoint — Batch ist robust für Push-to-Talk (sub-30s recordings)
- **Apple-Fallback bei ElevenLabs-Fail** — Daily-Use darf nie blockieren. Bei Netz-Aus / Timeout / 5xx: leise Apple-Resultat behalten
- **Replace-Timing atomar** im `recognizedText`-State — kein direkter Buffer-Write, schützt User-Edits

### Tests

- `AudioBufferAccumulatorTests` — Resample + WAV-Header-Validierung
- `ElevenLabsClientTranscribeTests` — Mock-URL-Protocol Scribe-API-Roundtrip
- `HybridRecognizerTests` — Apple+ElevenLabs-Coordinator + Fallback-Path

### Bekannte Limits

- Word-Level Timestamps explizit deaktiviert (nicht benötigt)
- Language-Hint nicht gesetzt (Scribe auto-detected exzellent)
- Cost-Tracking-UI nicht implementiert (~$0.40/h, in Settings später)

---

## [Unreleased] — Welle 1 (28.05.2026)

### Added

- App-Icon-Set (10 macOS-Sizes von 16×16 bis 1024×1024)
- README mit Quick-Start, Architektur-Übersicht und Roadmap
- Dieses CHANGELOG

### Verified (keine Code-Änderung nötig)

- `⌘N` startet eine neue Conversation (in `PanelView.swift:38`)
- Selektion-Ersetzen ist UI-verdrahtet (`MessageList.swift:18`, Toggle in Voice-Settings)
- Alle 6 Default-QuickActions seeded beim ersten Start (`QuickActionLibrary.swift:54-68`)

---

## [0.1.0] — pre-release (Tide-Funktionsumfang vor Standalone-Repo-Extraction)

Tide wurde initial im Dispo-Monorepo (`apps/tide/`) entwickelt. Diese
Version fasst alle Feature-Commits zusammen, die vor dem Extrahieren ins
standalone Repo (`scubanet/tide`) gemacht wurden.

### Foundation

- **Modularer Aufbau** mit 5 Swift Packages: Core, LLM, TideSpeech, Selection, Hotkeys
- **App-Target** mit Menubar (`NSStatusItem`), Panel-Window, Settings-Window, `LSUIElement` (kein Dock-Icon)
- **Swift 6 strict concurrency** durchgängig
- macOS 14.0+ Deployment-Target
- **Test-Workflow** via GitHub Actions

### Push-to-Talk

- **Global Hotkey** via `KeyboardShortcuts`-Library — default `fn`, in Settings konfigurierbar
- **Hotkey-Druck öffnet Panel + startet Audio-Recording** in einem Schritt
- **Loslassen sendet** die Aufnahme an Speech-Recognizer
- `AudioRecorder` als `AVAudioEngine`-Wrapper, Render-Thread-sicher (`@Sendable` Tap-Closure)

### Speech-Recognition (STT)

- **Apple `SFSpeechRecognizer`** — on-device wenn verfügbar, sonst Cloud-Fallback (nicht gezwungen)
- Live partial-text in der Panel-UI während des Sprechens
- Stepwise Debug-Logging für Recognizer-State-Probleme

### Speech-Synthesis (TTS)

- **`AVSpeechSynthesizer`-Provider** (Apple) mit **sentence-boundary streaming TTS** — spricht parallel zum Claude-Streaming, ohne auf das Ende der Antwort zu warten
- **ElevenLabs-Provider** für natürlichere Stimmen
- **Composite-Synthesizer** — User wählt in Settings zwischen Apple und ElevenLabs, Live-Voice-Switching während laufender Synthese
- Reorder-Buffer im ElevenLabs-Synthesizer (Playback-Reihenfolge per Sequenz, nicht per Response-Zeit)

### Selection-Context

- **AX-Selection-Reader** liest markierten Text aus der frontmost-App via Accessibility API
- **Selection-Replacer** kann Claude-Antwort zurück in die Selection pasten (Toggle in Voice-Settings)
- **Clipboard-Copy-Fallback** für Apps ohne AX-Selection-Support (Spark, Slack, Browser): macht `Cmd+C` und liest Clipboard
- AX-Trust-Option-Key als String-Constant (Swift-6-strict-concurrency-konform)

### Conversation-Management

- **SwiftData-Persistence** für Conversations und Messages
- **Letzte Conversation läuft beim Panel-Open weiter** (sticky)
- **`⌘N`** startet eine neue Conversation
- **Send-Button** aktiv wenn Input ODER Selektion vorhanden ist (nicht nur Input)

### QuickActions

- **Library** mit 6 Built-In QuickActions:
  - Zusammenfassen
  - Übersetzen (DE → EN)
  - Verbessern (Stil + Grammatik)
  - Antwort entwerfen
  - Erklären (mit Beispielen)
  - Kürzer
- **Custom-Editor** in Settings — User kann eigene Actions mit eigenem System-Prompt definieren
- Persistenz via `UserDefaults` (JSON-encoded)

### LLM-Provider

- **Anthropic-Provider** mit Streaming-SSE-Parsing
- Provider-agnostisches Protocol (`LLMProvider`, `LLMMessage`, `LLMChunk`, `LLMError`, `LLMTool`)
- **Tool-Use-Pfad vorbereitet** für spätere Phase-2-Mac-App-Integration (kein Refactor nötig wenn Tools dazukommen)

### Settings-Window

- **5 Tabs:** API-Key, Hotkey, Model, Voice (incl. Recognizer-Toggle für später), QuickActions-Editor
- Eigenes `NSWindow` (kein Standard-macOS-Settings-Scene)
- Keychain-Storage für API-Keys

### Tests

- **7 Test-Suites:**
  - `CoreTests` (AppSettings, Conversation, ConversationStore, KeychainHelper, QuickActionLibrary)
  - `LLMTests` (AnthropicProvider, SSEParser, LLM-Protocol)
  - `SpeechTests` (Recognizers + Synthesizers + Composite-Router)
  - `SelectionTests` (Reader + Replacer)
  - `HotkeysTests` (PushToTalkHandler)
  - `TideAppTests` (App-Level)

### Distribution-Vorbereitung

- **Sparkle 2.6+** Integration im Bundle (Auto-Update-Framework)
- `SUFeedURL` zeigt auf `github.com/scubanet/tide/releases/download/appcast.xml`
- `SUPublicEDKey` noch Placeholder — wird in Welle 3 generiert

### Code-Module-Naming

- **`TideSpeech`** statt `Speech` — vermeidet Collision mit Apple's `Speech.framework`

### Bundle

- `swiss.weckherlin.tide`

---

## Roadmap — kommende Wellen

| Welle | Inhalt | Status |
|---|---|---|
| 1 | Polish + Verifications + README/CHANGELOG + Icon-Set | ✅ |
| 2 | ElevenLabs Scribe Hybrid (STT-Genauigkeits-Upgrade, Apple-Live + ElevenLabs-Final) | 🔜 |
| 3 | Distribution-Pipeline (Sparkle EdDSA-Key, DMG-Build, Code-Signing, Notarization, GitHub-Releases-Workflow) | 🔜 |
| 4 | UX-Polish (Onboarding-Flow, Crash-Reporting) | 🔜 |

### Out-of-Scope der aktuellen Roadmap (eigene spätere Wellen)

- History-Sidebar (DB-Schema vorhanden, UI fehlt)
- Multi-Provider (OpenAI, Gemini, Ollama)
- Tool-Use für Mac-App-Integration (AppleScript / App Intents / MCP-Client)
- Whisper-API für STT (Alternative zu ElevenLabs Scribe)
- Landing-Page
