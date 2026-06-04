# Tide

Native macOS Menubar-KI-Assistent. Push-to-Talk an Claude mit Text-Selektions-Kontext aus jeder Vordergrund-App.

## Was Tide kann

- **Push-to-Talk via globalen Hotkey** — beliebige Taste festhalten (default `fn`), reden, loslassen sendet
- **Live-Streaming-Antworten** von Claude (Anthropic API, SSE-Streaming)
- **Streaming-TTS** via `AVSpeechSynthesizer` oder **ElevenLabs** (umschaltbar in Settings)
- **Spracherkennung umschaltbar**: Apple (on-device), ElevenLabs Scribe, Hybrid (Apple live + ElevenLabs final), Lokal (WhisperKit) und Hybrid-Lokal (Apple live + WhisperKit final)
- **Lokale Transkription** via WhisperKit/CoreML — offline, gratis, kein Audio verlässt den Mac (In-App Modell-Download in Settings → Lokal)
- **Standalone-Diktat** per eigenem Hotkey direkt an den Cursor der fokussierten App (ohne Panel): **Roh**, **Polished**, **Calmer** (Wut→ruhig), **Emoji**, **Bullets**, **Professional** — je eigener opt-in Hotkey + editierbarer Prompt
- **Custom-Vokabular** für Namen/Fachjargon — biast Apple-Erkennung + Polish-Schritt
- **Artefakt-Filter** verwirft zu kurze Aufnahmen / ASR-Halluzinationen
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
3. Beim ersten Start: Settings öffnen (Menubar-Icon → Cog) — Sidebar mit Gruppen (Allgemein / Sprache / Diktat / Erweitert). Anthropic-API-Key (Allgemein → API), Recognizer + Voice (Sprache → Stimme), Diktat-Hotkeys (Diktat → Hotkey)

## Architektur

```
Tide/                  Xcode-App-Target (Menubar + Panel-UI, Settings)
└── Packages/          5 Swift Packages
    ├── Core/          Models, Persistence, Settings, Keychain
    ├── LLM/           Anthropic-Provider, SSE-Parser, Tool-Use-Pfad
    ├── TideSpeech/    Apple + ElevenLabs + WhisperKit Speech-Provider, TTS, Hybrid-/Composite-Router
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
| 2 | ElevenLabs Scribe Hybrid (STT-Genauigkeit) | ✅ |
| 3 | Standalone-Diktat (Roh/Polished, direkt am Cursor) | ✅ |
| 4 | Artefakt-Filter + Custom-Vokabular | ✅ |
| 5 | Lokale Transkription (WhisperKit) + Hybrid-Lokal | ✅ |
| 6 | Diktat-Transform-Modi (Calmer/Emoji/Bullets/Professional) | ✅ |
| 7 | Settings-Sidebar | ✅ |
| 8 | Distribution (DMG, Notarization, GitHub-Releases via Sparkle) | 🔜 |
| 9 | Onboarding-Flow + Crash-Reporting | 🔜 |

## Anforderungen

- macOS 14.0+
- Anthropic API-Key
- Optional: ElevenLabs API-Key für ElevenLabs-TTS
- Berechtigungen: Mikrofon, Accessibility (für Selektion + Hotkey)

## Lizenz

Kein Public-Release-Lizenz-Statement bisher — Repo ist privat.

---

Konzept inspiriert von der Windows-App "2Key" (Sebastian Claes). Tide ist ein bewusster macOS-Konzept-Klon, kein Source-Port.
