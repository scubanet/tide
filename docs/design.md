# Tide — macOS-KI-Assistent — Design-Spec

*Working name: Tide. Konzept inspiriert von der Windows-App „2Key".*

**Datum:** 22. Mai 2026
**Status:** Design abgesegnet, bereit für Implementation-Plan
**Autor:** Larry (in Brainstorming-Session mit Dominik)
**Vorgänger-Dokument:** `2026-05-22-2key-macos-concept.md` (Konzept-Extraktion aus YouTube-Video)

---

## Was wir bauen

Eine native macOS-Menubar-App, inspiriert vom Konzept der Windows-App „2Key" (Sebastian Claes, YouTube-Video „Claude Code hat meinen Computer zur Super-KI gemacht"). Bewusster **Konzept-Klon**, kein Source-Port — die Original-UI war im Video nicht ausreichend detailliert sichtbar, und der Quellcode liegt nicht vor. Die finale App fühlt sich daher nicht 1:1 wie 2Key an, sondern nach Mac.

**Ein-Satz-Pitch:** Eine immer-erreichbare KI in der Menubar, die per Push-to-Talk-Hotkey kurze Fragen beantwortet oder längere Konversationen führt, dabei Text-Selektionen aus anderen Apps als Kontext nutzt und Antworten gleichzeitig streamend anzeigt und vorliest.

**Name:** **Tide**. Passt zu Dominiks ozeanigem Brand-Umfeld (AtollCal, AtollCard) und funktioniert gleichzeitig als eigenständiges Produkt — kurz, ein Silbe, evoziert Rhythmus und Fluss (passend zu Voice-Konversationen).

---

## Bestätigte Design-Entscheidungen

Diese sind in der Brainstorming-Session festgenagelt und treiben alles andere:

1. **Window-Pattern: Menubar + Panel.** `NSStatusItem` in der Menubar, klick (oder Hotkey) öffnet ein Panel direkt darunter. Kein Dock-Icon (`LSUIElement = true`). Kein Hauptfenster. Settings ist ein separates NSWindow.
2. **Push-to-Talk: Ein einziger Hotkey, halten zum Sprechen.** Default-Vorschlag: `fn` (oder konfigurierbar in Settings). Drücken öffnet Panel UND startet Aufnahme. Loslassen sendet.
3. **Input-Modell: Voice primary, Text als Fallback.** Standard ist Sprache, aber das Panel hat ein Textfeld für längere/präzisere Prompts.
4. **Output-Modell: Streamender Text + automatisches Vorlesen** (TTS via `AVSpeechSynthesizer`, toggelbar in Settings).
5. **Persistenz-Modell: Letzte Konversation läuft weiter.** Panel öffnet immer mit der aktiven Konversation. `⌘N` startet eine neue. Lokal in SwiftData persistiert. Keine History-Sidebar in v1 — DB-Schema unterstützt sie aber.
6. **Selected-Text-Integration: Aktiviert.** Beim Hotkey-Druck liest die App den markierten Text in der frontmost App via Accessibility API. Selection wird als Kontext an Claude geschickt. Antwort kann optional zurück in die Selektion ersetzt werden.
7. **Quick-Action-Templates: Defaults + User-Custom.** ~6 vordefinierte Actions (Zusammenfassen, Übersetzen, Verbessern, Antwort entwerfen, Erklären, Kürzer machen) als Pills im Panel. User kann eigene definieren mit eigenem System-Prompt.
8. **API: Anthropic-only in v1.** OpenAI/Gemini/Local kommen später, das LLM-Package ist provider-agnostisch designt.
9. **Tool-Use-Pfad ist von Anfang an im LLM-Package.** v1 registriert keine Tools, aber der gesamte Streaming + Tool-Result-Code-Pfad existiert, damit die geplante Phase-2-Erweiterung (Mac-App-Integration) kein Refactor im LLM-Modul auslöst.
10. **Architektur-Ansatz: Modular mit Swift Packages** (analog zu AtollCal/AtollCard mit AtollCore/AtollDesign).

---

## Architektur — Modul-Struktur

### Layout

Das Repo besteht aus einem dünnen Xcode-App-Target und fünf Swift Packages. Das App-Target enthält ausschließlich SwiftUI-UI und Composition-Root-Code. Sämtliche Business-Logik wohnt in den Packages.

```
tide/
├── App/                          # Xcode-Target (.app bundle, Tide.app)
│   ├── App.xcodeproj
│   ├── App/
│   │   ├── AppEntry.swift        # @main, LSUIElement, Sparkle wire-up
│   │   ├── Menubar/
│   │   │   ├── MenubarController.swift   # NSStatusItem + Panel lifecycle
│   │   │   └── HotkeyController.swift    # Bridge Hotkeys → Recorder
│   │   ├── Panel/
│   │   │   ├── PanelView.swift           # Root container
│   │   │   ├── TopBar.swift              # ⌘N, status, settings cog
│   │   │   ├── QuickActionsBar.swift     # Horizontal pill row
│   │   │   ├── SelectionContextBadge.swift
│   │   │   ├── MessageList.swift         # Chat bubbles
│   │   │   ├── InputBar.swift            # Text field + mic + recording state
│   │   │   └── BubbleActionsRow.swift    # Copy / Replace / TTS toggle
│   │   ├── Settings/
│   │   │   ├── SettingsWindow.swift      # Separate NSWindow
│   │   │   ├── ApiKeySection.swift
│   │   │   ├── HotkeySection.swift
│   │   │   ├── ModelSection.swift
│   │   │   ├── VoiceSection.swift
│   │   │   └── QuickActionsEditor.swift
│   │   ├── Recorder/
│   │   │   └── AudioRecorder.swift       # AVAudioEngine wrapper
│   │   └── Composition/
│   │       └── AppContainer.swift        # DI / wiring
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
└── Packages/
    ├── Core/
    │   ├── Sources/Core/
    │   │   ├── Models/{Conversation,Message,QuickAction,LLMTool}.swift
    │   │   ├── Persistence/{ConversationStore,QuickActionLibrary}.swift
    │   │   ├── Settings/AppSettings.swift
    │   │   └── Security/KeychainHelper.swift
    │   └── Tests/CoreTests/
    ├── LLM/
    │   ├── Sources/LLM/
    │   │   ├── Protocols/{LLMProvider,LLMMessage,LLMChunk,LLMError}.swift
    │   │   └── Anthropic/{AnthropicProvider,SSEParser,RequestBuilder}.swift
    │   └── Tests/LLMTests/  (mit MockURLProtocol)
    ├── Speech/
    │   ├── Sources/Speech/
    │   │   ├── Protocols/{SpeechRecognizer,Synthesizer}.swift
    │   │   └── Apple/{AppleSpeechRecognizer,AppleSynthesizer}.swift
    │   └── Tests/SpeechTests/
    ├── Selection/
    │   ├── Sources/Selection/
    │   │   ├── SelectionReader.swift     # AXUIElement copy from frontmost
    │   │   └── SelectionReplacer.swift   # Paste back via CGEvent
    │   └── Tests/SelectionTests/
    └── Hotkeys/
        ├── Sources/Hotkeys/
        │   ├── Protocols/GlobalHotkey.swift
        │   ├── KeyboardShortcutsImpl.swift  # using KeyboardShortcuts lib
        │   └── PushToTalkHandler.swift      # press/release detection
        └── Tests/HotkeysTests/
```

### Abhängigkeitsgraph

- `App` hängt an allen Packages.
- `Core` hat keine internen Dependencies.
- `LLM` hängt nur an `Core` (für `LLMMessage` und `LLMTool`).
- `Speech`, `Selection`, `Hotkeys` haben keine internen Dependencies.
- Externe: Anthropic API (HTTP), Apple Speech.framework, AVFoundation, SwiftData, Sparkle, `sindresorhus/KeyboardShortcuts` (Swift Package).

### Warum diese Schnitte

- `LLM` als Protocol-driven: zukünftige Provider (OpenAI, Gemini, Ollama) sind eigene Impls im selben Package, ohne dass App-Code etwas merkt.
- `Speech` und `Selection` separat: brauchen unterschiedliche Permissions (Mic vs. Accessibility). Saubere Trennung macht den Permission-Flow im UI nachvollziehbar.
- `Hotkeys` einzeln: arbeitet mit CGEventTap und Carbon-APIs, „Quirky Stuff" — gehört isoliert.
- `Core` ist die einzige Stelle mit Persistenz und Settings — verhindert dass Data-Layer-Logik durch die ganze Codebase versickert.

---

## Komponenten im Detail

### App-Target

- **MenubarController** — instanziiert `NSStatusItem` mit einem Template-Image-Icon. Klick öffnet/schließt das Panel. Auf `applicationDidFinishLaunching` registriert es sich beim `HotkeyController` als Listener.
- **HotkeyController** — abstrahiert die globale Tastatur-Logik. Stellt zwei Streams bereit: `onPress: () -> Void` und `onRelease: () -> Void`. Übersetzt diese zu `Recorder.start()` und `Recorder.stop()` Aufrufen.
- **PanelView** — Root-SwiftUI-View, kombiniert die Subviews. Reagiert auf `ConversationStore.activeConversation` und auf `Recorder.state`. Größe: `width: 400`, `maxHeight: 560`, scrollt intern.
- **QuickActionsBar** — horizontale `ScrollView` mit Pills aus `QuickActionLibrary.all()`. Tap = setzt die zugehörige System-Prompt-Variante für die nächste Nachricht. Aktive Action wird visuell hervorgehoben.
- **SelectionContextBadge** — sichtbar wenn die letzte User-Message eine `selectionContext: SelectedText?` ungleich nil hat. Zeigt Quelle (App-Name) und Längen-Info.
- **MessageList** — `ScrollView` mit `LazyVStack`, scrollt automatisch auf den neuesten Token. Streaming-Bubble hat einen blinkenden Cursor am Ende.
- **InputBar** — drei Zustände: Idle (Textfeld + Mic-Button), Recording (Live-Waveform + „fn loslassen zum Senden"), Thinking (Disabled, Spinner).
- **SettingsWindow** — separater `NSWindow`, durch Klick aufs Settings-Zahnrad im Panel geöffnet. Fünf Sektionen: API-Key, Hotkey, Modell, Voice (TTS Toggle + Sprach-Auswahl), Quick-Actions-Editor.
- **AudioRecorder** — wrapped `AVAudioEngine`. Startet Mic-Capture auf `start()`, sendet Audio-Buffers an den injizierten `SpeechRecognizer`. Stop liefert finale Transkription.
- **AppContainer** — Composition-Root, instanziiert alle Services beim Launch und injiziert sie in die Views via Environment.

### Core-Package

- **Conversation** — `@Model class Conversation`: `id, title, createdAt, updatedAt, messages: [Message]`. Title wird beim ersten Message-Exchange aus den ersten 40 Zeichen der User-Message abgeleitet.
- **Message** — `@Model class Message`: `id, role, content, createdAt, conversation: Conversation?, selectionContext: SelectedTextSnapshot?, toolCalls: [ToolCall]`. Role ist `user | assistant | tool`.
- **QuickAction** — `struct QuickAction`: `id, slug, label, systemPrompt, isBuiltIn`. Defaults sind hartkodiert im Bundle, Custom-Actions persistiert in SwiftData.
- **LLMTool** — `struct LLMTool`: `name, description, inputSchema (JSON)`. Liegt im Core damit Future-Phase-2 nicht restrukturieren muss.
- **ConversationStore** — facade über SwiftData. Stellt bereit: `activeConversation()`, `startNew()`, `append(message:)`, `recent(limit:)`, `delete(id:)`.
- **QuickActionLibrary** — kombiniert Built-Ins mit User-Custom. CRUD für Custom-Actions.
- **AppSettings** — `UserDefaults`-Wrapper mit publishierten Properties: `hotkeyKeyCode`, `selectedModel`, `voiceEnabled`, `voiceIdentifier`, `replaceSelectionDefault`.
- **KeychainHelper** — `set(key:, value:)`, `get(key:)`, `delete(key:)` für API-Keys.

### LLM-Package

- **LLMProvider** Protocol:
  ```swift
  protocol LLMProvider {
    func streamChat(
      messages: [LLMMessage],
      tools: [LLMTool],
      model: String,
      systemPrompt: String?
    ) -> AsyncThrowingStream<LLMChunk, Error>
  }
  ```
- **AnthropicProvider** — implementiert das Protocol via `URLSession` mit `messages` Endpoint, parsed SSE-Events (`content_block_delta`, `tool_use`, `message_stop`, `error`), liefert `LLMChunk.text(String)`, `LLMChunk.toolUse(...)`, `LLMChunk.done`.
- **LLMChunk** Enum mit Cases: `text(String)`, `toolUse(id:name:input:)`, `error(LLMError)`, `done`.
- **LLMError** — `network`, `unauthorized`, `rateLimit(retryAfter:)`, `serverError(code:message:)`, `decoding`.

### Speech-Package

- **SpeechRecognizer** Protocol: `start() async throws`, `feed(_ buffer: AVAudioPCMBuffer)`, `stop() async throws -> String`. Liefert während des Streams Zwischen-Transcripts via Combine-Publisher `partialResults: AnyPublisher<String, Never>`.
- **AppleSpeechRecognizer** — wrapped `SFSpeechRecognizer`. Bevorzugt on-device-Modus wenn verfügbar (`requiresOnDeviceRecognition`).
- **Synthesizer** Protocol: `speak(_ text: String)`, `stop()`. Mit Property `isSpeaking: Bool`.
- **AppleSynthesizer** — wrapped `AVSpeechSynthesizer`. Unterstützt inkrementelles `speak()`: nimmt Text-Chunks während des Streamings und queued sie als Utterances.

### Selection-Package

- **SelectionReader.readFromFrontmostApp() async throws -> SelectedText?** — liest via `AXUIElementCopyAttributeValue` (`kAXSelectedTextAttribute`). Gibt `SelectedText(text: String, sourceAppBundleID: String, sourceAppName: String)` zurück oder nil wenn nichts selektiert.
- **SelectionReplacer.replaceSelection(with text: String) async throws** — simuliert ⌘V mit dem neuen Text via Clipboard-Swap-Trick (Original-Clipboard sichern, neuer Text rein, ⌘V via `CGEvent`, Original wiederherstellen).

### Hotkeys-Package

- **GlobalHotkey** Protocol: `register(keyCombo:, onPress:, onRelease:)`, `unregister()`.
- **KeyboardShortcutsImpl** — Wrapper über `sindresorhus/KeyboardShortcuts`. Konfigurierbarer User-Key via deren Native-Settings-View, in unsere Settings einbettbar.
- **PushToTalkHandler** — entkoppelt rohes Press/Release vom Recording: debounced kurze Tipper (< 100ms = Klick statt PTT), startet/stoppt den Recorder.

---

## Datenfluss

### Flow A — Quick-Action mit Selektion

1. User markiert Text in Mail, hält die `fn`-Taste.
2. `HotkeyController.onPress` feuert. **Kritisch:** Bevor das Panel öffnet, ruft der Controller `SelectionReader.readFromFrontmostApp()` auf — sonst hat die Quell-App den Fokus schon verloren.
3. Panel slidet auf, `SelectionContextBadge` erscheint mit der erkannten Selektion (Quelle und Wortzahl).
4. `Recorder.start()` startet die Mic-Aufnahme. `AppleSpeechRecognizer` transkribiert live, Zwischenergebnis erscheint im `InputBar`.
5. User lässt `fn` los. `HotkeyController.onRelease` ruft `Recorder.stop()`. Der finale Prompt-Text wird zusammen mit dem Selection-Snippet als User-Message an `ConversationStore.append` übergeben.
6. App ruft `AnthropicProvider.streamChat(messages:, tools: [], model:, systemPrompt:)` auf. Der `systemPrompt` ist der aktuell gewählte Quick-Action-Prompt (Default: ohne, generischer Chat-Modus).
7. `LLMChunk.text(...)`-Events ploppen rein: jeder Chunk wird an die Assistant-Message angehängt UND an `AppleSynthesizer.speak()` weitergegeben (falls Voice aktiv). UI rendert.
8. `LLMChunk.done` schließt den Stream, `ConversationStore.append` persistiert die finale Assistant-Message.
9. Optional: User klickt „Ersetzen" in der `BubbleActionsRow`. `SelectionReplacer.replaceSelection(with:)` schreibt die Antwort zurück in die Quell-App.

### Flow B — Reines Conversational

1. User klickt das Menubar-Icon (oder triggert den Hotkey kurz, < 100ms).
2. `MenubarController` öffnet das Panel. `ConversationStore.activeConversation()` lädt die letzte Conversation; ihre Messages erscheinen in der `MessageList`.
3. User tippt eine Frage ins Textfeld oder hält den Hotkey zum Sprechen. Bei Tippen: Return sendet.
4. App ruft `AnthropicProvider.streamChat` mit der vollen Message-History auf.
5. Wie in Flow A: Tokens streamen rein, werden parallel angezeigt und vorgelesen.
6. Persist via Store. Panel bleibt offen.
7. User stellt Folgefragen — Loop zurück zu Schritt 4 mit erweiterter History.
8. User drückt Esc oder klickt außerhalb. Panel hidet aber bleibt am gleichen Konversationsstand.
9. Beim nächsten Open: Conversation setzt fort. `⌘N` startet eine neue.

### Future-Phase-2 — Tool-Use für Mac-App-Integration

Bereits jetzt im LLM-Package vorbereitet. Wenn der `tools`-Parameter in `streamChat` nicht leer ist, kann Claude `tool_use`-Content-Blocks im Stream zurückgeben. Die App reagiert mit:

1. Tool-Use-Chunk erkennen, Tool-Call extrahieren (`name`, `input`)
2. Lokale Tool-Implementierung aufrufen (AppleScript / App Intents / MCP-Client)
3. Result als `tool_result` in einer neuen User-Message zurück an Claude
4. Stream fortsetzen

Das ist Multi-Turn-innerhalb-einer-Konversation und macht den Mac-Access ohne Refactor möglich.

---

## Error-Handling

| Kategorie | Trigger | Verhalten |
|---|---|---|
| **Permission fehlt** (Mic, AX) | Feature wird zum ersten Mal benutzt | Banner im Panel + Settings-Sektion mit „Erlauben" Button. Feature disabled, App bleibt nutzbar. |
| **Netzwerk weg** | Während SSE-Stream bricht ab | Stream abbrechen, Teil-Antwort behalten, Inline-Banner „Verbindung weg · ↻ Wiederholen". |
| **Rate-Limit (429)** | Anthropic-API antwortet 429 | Toast „Rate-Limit · in X Sek erneut versuchen", Auto-Retry mit exponentiellem Backoff (max 3 Versuche). |
| **Auth-Fehler (401)** | API-Key ungültig | Modal „API-Key prüfen" das direkt zur Settings-Section springt. |
| **STT failed** | Keine Sprache erkannt, Lärm, Mic blockiert | Toast „Nichts verstanden · nochmal versuchen". Text-Input bleibt benutzbar. |
| **TTS failed** | Synth crashed (selten) | Stiller Fallback, Text bleibt sichtbar. Im Log notiert. |
| **Selection-Read failed** | AX-Call schlägt fehl | Selection-Badge erscheint einfach nicht, Quick-Action funktioniert ohne Kontext. Kein UI-Error. |
| **Tool-Call fehlerhaft** (Phase 2) | Lokale Tool-Impl wirft | Fehler wird als `tool_result` mit `is_error: true` zurück an Claude geschickt, der erklärt's dem User. |
| **SwiftData-Migrationsfehler** | Schema-Mismatch nach App-Update | Defensive: alte DB als `.bak` archivieren, frischer Start, Toast „Verlauf wurde archiviert nach: ~/Library/Application Support/Tide/backup-YYYY-MM-DD.sqlite". |

**Cross-cutting:**

- Alle Errors sind recoverable — kein Error zwingt zum App-Restart.
- Errors loggen in den OSLog-Subsystemen `swiss.weckherlin.tide.llm`, `.speech`, `.selection`, `.hotkeys`, `.ui` für `log show --predicate ...`-Debugging.
- User-facing Error-Strings sind in deutscher Sprache, mit Fallback auf Englisch via Localization.

---

## Testing

### Unit-Tests pro Package (XCTest)

- **Core:** Domain-Models-Codable, ConversationStore mit in-memory SwiftData container, QuickActionLibrary-Defaults laden, KeychainHelper round-trip (mocked Security framework).
- **LLM:** AnthropicProvider mit `MockURLProtocol` — SSE-Stream-Parsing, Tool-Use-Schema-Detection, Retry-Logik mit Exponential Backoff, vollständige Error-Mapping-Tabelle. Keine echten API-Calls in Unit-Tests.
- **Speech:** Mocked SFSpeechRecognizer und AVSpeechSynthesizer (Protocol-Conformance prüfen, State-Maschine, Cancellation).
- **Selection:** Mock-AXUIElement-Wrapper, testet Reader/Replacer-Logik ohne echtes UI.
- **Hotkeys:** PushToTalkHandler-Debouncing, Press/Release-Threshold-Logic.

### Integration-Tests im App-Target

- Conversation-Flow End-to-End mit `MockLLMProvider` (gibt vorberechnete Async-Streams zurück) — verifiziert User-Input → Store → UI-Update-Pfad.
- HotkeyController mit simulierten Press/Release-Events durch direkte Method-Calls.
- Settings-Save-and-Load roundtrip via `UserDefaults` + Keychain.

### UI-Tests (XCUITest, sparsam)

- **Smoke-Test:** App startet, Menubar-Icon erscheint, Klick öffnet Panel.
- **Critical-Path:** Panel offen → Text in Input → Send → Mock-Response erscheint und wird gespeichert.

### Was bewusst NICHT getestet wird

- Echte Anthropic-API-Calls (zu instabil für CI, kostet Geld).
- Echte `SFSpeechRecognizer`-Output (Audio-Capture im headless CI unmöglich).
- macOS-Permission-Prompts (User-Interaction-only, nicht automatisierbar).

### CI-Setup

`xcodebuild test -workspace Tide.xcworkspace -scheme Tide` via GitHub Actions auf `macos-14`. Coverage-Target 70 % in Packages, weniger im App-Target.

---

## Default-Konfiguration

Damit die App nach dem ersten Start sinnvolle Defaults hat:

- **Modell:** `claude-sonnet-4-6` (aktuelles Sonnet-Modell, gutes Speed/Quality-Verhältnis)
- **Hotkey:** `fn` (User-konfigurierbar in Settings via KeyboardShortcuts-Library)
- **System-Prompt (Default):** Kurz und nüchtern: „Du bist ein präziser Assistent für einen deutschsprachigen Nutzer. Antworte direkt und ohne Floskeln. Wenn Text-Selektion mitgegeben wurde, beziehe dich darauf."
- **TTS:** Eingeschaltet, mit System-Stimme `de-DE` (User kann andere Stimme wählen).
- **Quick-Action-Defaults (6 Stück):**
  - „Zusammenfassen" — System-Prompt: „Fasse den folgenden Text in 2–3 Sätzen zusammen."
  - „Übersetzen" — System-Prompt: „Übersetze den folgenden Text ins Englische. Nur die Übersetzung ausgeben."
  - „Verbessern" — System-Prompt: „Verbessere Stil, Grammatik und Klarheit des folgenden Textes ohne den Sinn zu ändern."
  - „Antwort entwerfen" — System-Prompt: „Entwirf eine knappe, höfliche Antwort auf die folgende Nachricht."
  - „Erklären" — System-Prompt: „Erkläre das folgende Konzept einfach und mit Beispielen."
  - „Kürzer" — System-Prompt: „Kürze den folgenden Text um etwa die Hälfte ohne wichtige Punkte zu verlieren."

---

## Open Questions — vor Implementation-Start zu klären

Diese Punkte sind im Design absichtlich offen gelassen — wir entscheiden sie bei Bedarf während der Plan-Phase oder per Quick-Frage:

1. ~~**App-Name.**~~ ✅ **Tide.**
2. **Bundle-ID.** Empfehlung: `swiss.weckherlin.tide` (eigenständiges Produkt, nicht im Atoll-Namespace).
3. **Repo-Standort.** Empfehlung: standalone in `~/Desktop/Developer/Tide/` — Tide ist thematisch keine Atoll-App. Atoll-OS-Monorepo wäre nur sinnvoll wenn `AtollDesign` geteilt werden soll, was hier nicht der Fall ist (Tide hat eigene visuelle Sprache).
4. **Hotkey-Default.** `fn` ist die naheliegende Wahl (Walkie-Talkie-Feel), aber auf manchen Macs durch System-Funktionen belegt. Alternative: `right ⌥` (Option-Right) oder `⌃Space`. Sollte beim ersten Start im Onboarding bestätigt werden.
5. **macOS-Min-Version.** Vorschlag: macOS 14 (Sonoma) für solide SwiftData + async/await. macOS 26 würde Liquid Glass freischalten, aber den User-Pool stark einschränken.
6. **Sparkle-Update-Feed.** Wo wird der `appcast.xml` gehostet? GitHub Releases (kostenlos, public) oder eigene Subdomain `tide.weckherlin.com/appcast.xml`?
7. **Code-Signing-Zertifikat.** Falls bereits ein Apple Developer ID Application Cert (von AtollCal/AtollCard) existiert: wiederverwendbar — gleicher Team-ID (`XK8V89P2QV`).
8. **TTS-Qualität.** Apples System-Stimmen sind teils sehr robotisch. Phase-2-Option: ElevenLabs-Integration für deutlich natürlichere Voices (kostenpflichtig).

---

## Future Scope — Phase 2 & später (explizit nicht v1)

- **Mac-App-Integration via Tool-Use:** AppleScript/JXA-Wrappers für Mail, Notes, Calendar, Reminders, Messages, Music, Finder, Safari. App Intents für Shortcuts.app-Integration (öffnet damit indirekt alle Apps die App Intents unterstützen). Optional MCP-Client für lokale MCP-Server (Filesystem, Git, etc.). Das LLM-Package ist dafür schon vorbereitet.
- **Multi-Provider:** OpenAI, Google Gemini, lokales Ollama als zusätzliche LLM-Provider-Impls.
- **Whisper-API für STT:** Bessere Erkennung bei Fachvokabular und mehrsprachigen Eingaben. Optionaler Provider, fallback bleibt Apple-native.
- **ElevenLabs für TTS:** Natürlichere Stimmen.
- **History-Sidebar:** Browsable Recent Conversations, Search, Pin/Archive.
- **Sharing:** Konversation als Markdown exportieren, als Link teilen (mit selbst-gehostetem Backend).
- **iOS-Sibling:** Mit den Packages `Core`, `LLM`, `Speech` (iOS-Variante via SiriKit) direkt teilbar.

---

## Nächster Schritt

Nach User-Approval dieses Specs: Übergang zur Implementation-Plan-Phase via `superpowers:writing-plans`. Der Plan zerlegt den Build in konkrete Tasks mit Reihenfolge, Estimaten, Abhängigkeiten und Definition-of-Done — dann kann die Implementierung starten.
