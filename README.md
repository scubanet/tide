# Tide

Native macOS Menubar-KI-Assistent. Push-to-Talk an Claude mit Text-Selektions-Kontext aus jeder Vordergrund-App.

## Was Tide kann

- **Push-to-Talk via globalen Hotkey** — beliebige Taste festhalten (default `fn`), reden, loslassen sendet
- **Live-Streaming-Antworten** von Claude (Anthropic API, SSE-Streaming)
- **Streaming-TTS** via `AVSpeechSynthesizer` oder **ElevenLabs** (umschaltbar in Settings)
- **Lokale Transkription** via WhisperKit/CoreML — offline, gratis, kein Audio verlässt den Mac (Modell-Download in Settings → Lokal)
- **Selektion-Kontext** aus der gerade aktiven App via Accessibility API; Fallback via Clipboard-Swap für Apps ohne AX (Spark, Slack, Browser)
- **Selektion ersetzen** — Claudes Antwort kann zurück in die selektierte Stelle gepastet werden
- **6 Quick-Actions** (Zusammenfassen, Übersetzen, Verbessern, Antwort entwerfen, Erklären, Kürzer) + Custom-Editor
- **Conversations persistiert** lokal (SwiftData), letzte Conversation läuft beim Öffnen weiter, `⌘N` startet neu

## Status

**v0.1.0 — pre-release.** Tide wird vom Autor täglich genutzt. Keine signierten DMG-Releases. Wer ihn auf seinem Mac bauen will: siehe Quick-Start unten.

## Quick-Start (Eigenbau)

```bash
git clone https://github.com/scubanet/tide.git
cd tide
xcodegen generate
open Tide.xcodeproj
```

In Xcode:
1. Schema **Tide** wählen, Run-Destination **My Mac**
2. Cmd+R
3. Beim ersten Start: Settings öffnen (Menubar-Icon → Cog), Anthropic-API-Key eintragen, Hotkey wählen, Voice-Provider wählen

## Architektur

```
Tide/                  Xcode-App-Target (Menubar + Panel-UI, Settings)
└── Packages/          5 Swift Packages
    ├── Core/          Models, Persistence, Settings, Keychain
    ├── LLM/           Anthropic-Provider, SSE-Parser, Tool-Use-Pfad
    ├── TideSpeech/    Apple + ElevenLabs Speech-/TTS-Providers, Composite-Router
    ├── Selection/     AX-Selection-Reader + Replacer + Clipboard-Fallback
    └── Hotkeys/       Push-to-Talk via KeyboardShortcuts-Library
```

Geteilte Pakete sind alle local. Externe Dependencies: `KeyboardShortcuts`, `Sparkle` und `WhisperKit` (argmax-oss-swift, für lokale On-Device-Transkription).

Details siehe [`docs/design.md`](docs/design.md).

## Aktuelle Roadmap

Siehe [CHANGELOG.md](CHANGELOG.md) für Versions-History. Nächste Wellen:

| Welle | Was | Status |
|---|---|---|
| 1 | Polish + Verifications + Icon-Set | ✅ |
| 2 | ElevenLabs Scribe Hybrid (STT-Genauigkeits-Upgrade) | 🔜 |
| 3 | Distribution (Sparkle, DMG, Notarization, GitHub-Releases) | 🔜 |
| 4 | Onboarding-Flow + Crash-Reporting | 🔜 |

## Anforderungen

- macOS 14.0+
- Anthropic API-Key
- Optional: ElevenLabs API-Key für ElevenLabs-TTS
- Berechtigungen: Mikrofon, Accessibility (für Selektion + Hotkey)

## Lizenz

Kein Public-Release-Lizenz-Statement bisher — Repo ist privat.

---

Konzept inspiriert von der Windows-App "2Key" (Sebastian Claes). Tide ist ein bewusster macOS-Konzept-Klon, kein Source-Port.
