# Tide — Code Audit

**Datum:** 2026-07-08 · **Branch:** `feat/audit-fixes` · **Stand:** 8.594 LOC Swift, 106 Dateien (ohne `build/`)
**Build-Ground-Truth:** Clean Build mit Xcode 27.0 (Beta, macOS-27-SDK) — **0 Warnings, 0 Deprecations**.
**Methodik:** 3 parallele Audit-Agents (Concurrency, Dead Code/Hygiene, Bugs/Security/Performance) + SwiftUI-Expertenpass + manuelle Verifikation aller High-Findings.

**Gesamturteil:** Ungewöhnlich disziplinierte Codebase. Keine Critical-Findings. Kein aktiver Data Race, keine `print`/`TODO`/`try!`-Leichen, Secrets korrekt im Keychain, saubere Package-Grenzen. Die Findings unten sind überwiegend latente Risiken, Duplikation und Performance-Feinschliff — plus drei echte High-Bugs.

---

## Fix-Status (2026-07-09)

**Behoben und verifiziert (Build clean, 56 App-Tests + alle Package-Tests grün):**
§2.1–2.6, §3.1–3.4, §4.1, §4.2, §5.1–5.6, §6.1, §6.2, §7.1–7.7, §8.1–8.5, §9.1 (TTS als `SpeechPlayback` extrahiert), §9.2–9.5.

**Zusätzlich umgesetzt:** §4.3 App Intents (Diktat starten/stoppen mit Modus-Parameter, Panel öffnen; `AppShortcutsProvider` mit deutschen Siri-Phrasen); §4.4 Sparkle auf 2.9.4.

**Offen (bewusst):**
- §9.6 teilweise — `CompositeSynthesizer`-Tests + `isReject`-Tests neu; DictationCoordinator-E2E braucht erst eine Recorder-Injection-Naht (größerer Umbau).
- §9.7 SwiftLint/SwiftFormat — nicht eingerichtet (Low, Stil ist konsistent).
- macOS-27-Beta-Runtimetest (TCC, Injection, Sparkle-Update, Glass-Optik) — manuell nötig.

**Test-Suite-Nebenfund:** `kSecUseDataProtectionKeychain` (§6.2) liefert in unsignierten Kontexten (`swift test`) `errSecMissingEntitlement` — KeychainHelper probt Verfügbarkeit jetzt einmalig und fällt sauber aufs Legacy-Keychain zurück; signierte App nutzt DP-Keychain inkl. transparenter Migration.

---

## 1. Executive Summary

1. **[High] API-Key greift erst nach App-Neustart** — §5.1 — `Tide/AppEntry.swift:89-90`. Onboarding-Nutzer geben den Key ein und jede Anfrage schlägt trotzdem mit 401 fehl, bis sie die App neu starten.
2. **[High] `fatalError` bei nicht verfügbarem Speech-Recognizer** — §5.2 — `Packages/Speech/Sources/TideSpeech/Apple/AppleSpeechRecognizer.swift:42-44`. Harter Crash auf Systemen ohne de-DE-Erkennung.
3. **[High] Komplettes Diktat-Transkript landet unredigiert im Systemlog** — §6.1 — `Tide/Dictation/DictationCoordinator.swift:173`. `privacy: .public` hebelt die OSLog-Redaktion aus — sensibelste Daten der App.
4. **[Medium] Markdown-Reparse pro Streaming-Token** — §7.1 — `Tide/Panel/MessageBubble.swift:60-69`. O(n²) über lange Antworten, auf dem Main Actor, im heißesten Pfad.
5. **[Medium] Clipboard-Restore verliert Nicht-Text-Inhalte** — §5.4 — `Packages/Selection/Sources/Selection/ClipboardPaste.swift:17-19,40-43`. Bild/Datei im Clipboard → nach Diktat-Injektion weg.
6. **[Medium] Selection-Read blockiert Main Thread bis 200 ms** — §7.5 — `Packages/Selection/Sources/Selection/SelectionReader.swift:77-80`. Beachball-Risiko bei jedem Push-to-Talk in Electron/Web-Apps.
7. **[Medium] Recorder-Setup + Reject-Heuristik doppelt kopiert** — §9.2 — ChatViewModel vs. DictationCoordinator, byte-identisch.
8. **[Medium] Drei kopierte API-Key-Eingabe-Views mit divergentem Fehlerverhalten** — §9.3 — zwei davon verschlucken Keychain-Fehler still.
9. **[Medium] FloatingPill nutzt Legacy-Material statt Liquid Glass** — §8.4 — wirkt unter macOS 27 (einstellbare Glas-Opazität) veraltet.
10. **[Medium] Feste Font-Größen ignorieren Dynamic Type** — §8.1 — mehrere UI-Flächen skalieren nicht mit Bedienungshilfen.

---

## 2. Quick Wins (≤ 30 Minuten)

### 2.1 Transkript-Log auf `.private` stellen
- **Location:** `Tide/Dictation/DictationCoordinator.swift:173`
- **Action:** Transkript aus dem Log entfernen oder `privacy: .private`; nur Länge/Dauer loggen wie überall sonst. (Fix für §6.1.)

### 2.2 `default.profraw` löschen und ignorieren
- **Location:** Repo-Root
- **Action:** Datei löschen, `*.profraw` in `.gitignore` aufnehmen.

### 2.3 Einsamen `NSLog` durch `os.Logger` ersetzen
- **Location:** `Tide/AppEntry.swift:195`
- **Action:** Einziger `NSLog` der Codebase; auf kategorisierten `Logger(subsystem: "swiss.weckherlin.tide", …)` umstellen.

### 2.4 Veralteten „Phase B"-Doku-Header korrigieren
- **Location:** `Tide/Dictation/DictationCoordinator.swift:44-51, 58-63`
- **Action:** Header beschreibt die Datei als unfertig (kein Indikator, keine Injektion, kein Polish) — alles längst implementiert. Umschreiben.

### 2.5 Accessibility-Label für Dismiss-Button
- **Location:** `Tide/Panel/SelectionContextBadge.swift:20-24`
- **Action:** `xmark.circle.fill`-Button hat kein Label; `.accessibilityLabel("Selektion verwerfen")` ergänzen.

### 2.6 „Welle 4" aus der Settings-UI entfernen
- **Location:** `Tide/Settings/HotkeySection.swift:40`
- **Action:** Interner Milestone-Name als Section-Header sichtbar; durch nutzerverständlichen Titel ersetzen.

---

## 3. Concurrency

Basis: Clean Build mit `strict-concurrency: complete`, **null Compiler-Warnings**. Kein aktiver Data Race gefunden. Findings sind latente Hazards.

### 3.1 ElevenLabsSynthesizer mischt Isolation-Domänen
- **Location:** `Packages/Speech/Sources/TideSpeech/ElevenLabs/ElevenLabsSynthesizer.swift:72-83, 118-141, 144-148`
- **What:** `stop()`/`speak()`/`setVoice()` sind nonisolated, `deliver`/`playNext` sind `@MainActor`; der Player-Lebenszyklus spannt beide Domänen, abgesichert nur durch Lock + Konvention.
- **Why:** Ruft je ein zukünftiger Caller off-main auf, kann TTS nach `stop()` weiterspielen und `AVAudioPlayer` (nicht threadsafe) cross-thread angefasst werden. Typsystem erzwingt die heutige Sicherheit nicht.
- **Action:** Ganze Klasse `@MainActor`-isolieren (Playback ist inhärent main-thread) und Lock entfernen — eine Isolation-Domäne statt zwei.
- **Severity:** Medium

### 3.2 `speak()` startet untracked, nicht stornierbare Netzwerk-Tasks
- **Location:** `Packages/Speech/Sources/TideSpeech/ElevenLabs/ElevenLabsSynthesizer.swift:59-69`
- **What:** Jeder `speak()`-Aufruf spawnt einen Task ohne Handle; `stop()` verwirft via `generation` nur das Ergebnis, cancelt aber nie den laufenden HTTP-Request.
- **Why:** Nach `stop()` laufen Synthese-Requests zu Ende (Netz/CPU verschwendet), schnelles Speak/Stop hinterlässt mehrere verwaiste Requests.
- **Action:** Tasks speichern und in `stop()` canceln; Cancellation in `client.synthesize` propagieren.
- **Severity:** Low

### 3.3 Doppelte Lock-Acquisition + Allokation auf dem Audio-Tap-Thread
- **Location:** `Tide/Recorder/AudioRecorder.swift:86-90`, `Tide/Recorder/AudioBufferAccumulator.swift:31-37`, `Packages/Speech/Sources/TideSpeech/Apple/AppleSpeechRecognizer.swift:123-126`
- **What:** Jeder Tap-Callback macht Deep-Copy (Allokation + memcpy) unter Lock A, dann Lock B in `recognizer.feed(_:)`.
- **Why:** Heute sicher (Tap-Thread, nicht Render-Thread), aber heißester Cross-Thread-Pfad; darf nie auf einen Render-Callback migrieren.
- **Action:** Copy behalten (Lifetime nötig), kritische Abschnitte allokationsfrei halten, Constraint dokumentieren.
- **Severity:** Low

### 3.4 Mutabler Prozess-Global `LocalTranscriberHolder`
- **Location:** `Packages/Speech/Sources/TideSpeech/WhisperKit/LocalTranscriberHolder.swift:9-13`; gesetzt `Tide/AppEntry.swift:81`, gelesen `ChatViewModel.swift:414`, `DictationCoordinator.swift:117`, `LocalModelSection.swift:70`
- **What:** `@MainActor`-Singleton mit mutablem `var transcriber` als Service-Locator.
- **Why:** Race-sicher, aber Lesen vor dem Setzen (async Launch-Lücke) fällt still auf `nil` zurück.
- **Action:** Write-once machen oder Transcriber explizit injizieren.
- **Severity:** Low

---

## 4. API-Modernität / macOS 27

Build gegen macOS-27-SDK sauber; arm64-only (Intel/Rosetta-Wegfall in macOS 27 irrelevant); kein SiriKit (Deprecation irrelevant); kein `UIDesignRequiresCompatibility`-Opt-out gesetzt.

### 4.1 Legacy `DispatchQueue.main.asyncAfter` statt `Task.sleep`
- **Location:** `Tide/Settings/ApiKeySection.swift:33`, `Tide/Panel/MessageList.swift:39-43`
- **What:** Verzögerte UI-Arbeit per GCD; MessageList nested sogar `Task { @MainActor in … }` in der Dispatch-Closure.
- **Why:** Nicht cancellable, inkonsistent zum Rest (überall `Task.sleep`).
- **Action:** Auf `Task { try? await Task.sleep(...) }` umstellen, Dispatch+Task-Nesting kollabieren.
- **Severity:** Low

### 4.2 `Task.detached` + `try?` verschluckt Prewarm-Fehler
- **Location:** `Tide/AppEntry.swift:86`, `Tide/Settings/LocalModelSection.swift:71`
- **What:** Modell-Warm-up läuft detached mit `try?`.
- **Why:** `detached` unnötig (Ziel ist ein Actor); fehlgeschlagener Modell-Load ist unsichtbar.
- **Action:** Plain `Task {}` und Fehler loggen.
- **Severity:** Low

### 4.3 Keine App Intents (macOS-27-Chance, kein Blocker)
- **Location:** Projektweit (kein `import AppIntents`)
- **What:** Siri auf macOS 27 spricht Third-Party-Apps nur noch über App Intents an; SiriKit ist deprecated.
- **Why:** Verpasste Integration — „Starte Diktat"-Intent wäre für eine Diktier-App naheliegend (Siri, Shortcuts, Spotlight).
- **Action:** `AppIntent` für Diktat-Start/Stop und Panel-Toggle erwägen.
- **Severity:** Low

### 4.4 Sparkle 2.9.2 vor Golden-Gate-Release gegenprüfen
- **Location:** `project.yml` (Package-Pins)
- **What:** Sparkle-Version stammt aus der Tahoe-Ära.
- **Why:** Vermutlich kompatibel; Update-Mechanik ist aber der falsche Ort für Überraschungen.
- **Action:** Vor macOS-27-Release Sparkle-Changelog prüfen, ggf. anheben; Update-Flow auf 27-Beta einmal durchspielen.
- **Severity:** Low

---

## 5. Bugs / Logikfehler

### 5.1 API-Key wird einmalig beim Launch gelesen; Änderung erfordert Neustart
- **Location:** `Tide/AppEntry.swift:89-90` (Erzeugung), `Packages/LLM/Sources/LLM/Anthropic/AnthropicProvider.swift:8-14` (immutables `let apiKey`), `Tide/Panel/PanelView.swift:11, 22-25` (staler `hasKey`-Gate), `Tide/Onboarding/Steps/OnboardingSteps.swift:39-40`
- **What:** `AnthropicProvider` entsteht in `applicationDidFinishLaunching` mit dem damaligen Keychain-Stand; nichts baut ihn neu, wenn der Nutzer später in Onboarding/Settings einen Key speichert. Zusätzlich seeded `PanelView.hasKey` einmalig per `@State` und beobachtet nie wieder.
- **Why:** Erstnutzer durchlaufen das Onboarding, geben einen gültigen Key ein — und jeder Send schlägt mit 401 fehl bzw. das Panel zeigt weiter „Key eingeben", bis die App neu gestartet wird. Nur `ApiKeySection.swift:45` erwähnt den Neustart.
- **Action:** Key pro Request lazy aus dem Keychain lesen (Closure) oder Provider bei Key-Änderung neu injizieren; `hasKey`-Gate an beobachtbaren Zustand binden, den alle drei Eingabepfade schreiben. **Verifiziert.**
- **Severity:** High

### 5.2 `fatalError` bei nicht verfügbarem SFSpeechRecognizer-Locale
- **Location:** `Packages/Speech/Sources/TideSpeech/Apple/AppleSpeechRecognizer.swift:42-44`
- **What:** Init crasht hart, wenn `SFSpeechRecognizer(locale: de-DE)` `nil` liefert.
- **Why:** Auf Systemen ohne de-DE-Erkennung (möglich, da der Default-Hybrid-Recognizer Apple-Partials nutzt) stürzt die App statt sich zu erholen — direkt neben einem bereits existierenden throwing-Pfad (`guard recognizer.isAvailable`, Zeile 67-70).
- **Action:** Init failable/throwing machen, `SpeechRecognizerError.unavailable` durch `RecognizerFactory` hochreichen. **Verifiziert.**
- **Severity:** High

### 5.3 `exportWAV` behandelt nur Float-Buffer; Int16-Input ergibt Stille
- **Location:** `Tide/Recorder/AudioBufferAccumulator.swift:121-131`
- **What:** Die Konkatenation kopiert nur `floatChannelData`; der `int16ChannelData`-Zweig fehlt (anders als im Deep-Copy, Zeilen 47-57).
- **Why:** Liefert ein Gerät Int16-Buffer, geht eine Null-WAV an ElevenLabs Scribe → leere Transkription ohne Fehler.
- **Action:** Int16-Fall spiegeln oder Format explizit garden/asserten.
- **Severity:** Medium

### 5.4 Clipboard-Restore verliert alles außer Plain Text
- **Location:** `Packages/Selection/Sources/Selection/ClipboardPaste.swift:17-19,40-43`, `Packages/Selection/Sources/Selection/SelectionReader.swift:71,86-89`
- **What:** Snapshot/Restore behandeln nur `.string`; Bilder, Datei-URLs, RTF, Multi-Type-Inhalte gehen bei `clearContents()` verloren.
- **Why:** Stiller Datenverlust des Nutzer-Clipboards bei jeder Diktat-Injektion, wenn dort kein Plain Text lag.
- **Action:** Alle `pasteboardItems` (Types + Data) sichern und komplett wiederherstellen.
- **Severity:** Medium

### 5.5 SSE-`error`-Events werden nie als Rate-Limit behandelt
- **Location:** `Packages/LLM/Sources/LLM/Anthropic/AnthropicProvider.swift:86-90`; konsumiert `Tide/Panel/ChatViewModel.swift:264-271, 285-288`
- **What:** Jedes Mid-Stream-`error`-Event (auch `overloaded_error` ≈ 429) wird auf `LLMError.serverError(code: 0)` gemappt.
- **Why:** Der existierende 429-Backoff greift dafür nie; Nutzer sehen eine nicht-retrybare Fehlermeldung statt automatischem Retry.
- **Action:** Event-`type` inspizieren, `overloaded_error`/`rate_limit_error` auf `LLMError.rateLimit` mappen.
- **Severity:** Low

### 5.6 Assistant-Message wird mehrfach an die Conversation appended
- **Location:** `Tide/Panel/ChatViewModel.swift:210, 253, 261, 280`; `Packages/Core/Sources/Core/Persistence/ConversationStore.swift:100-110`; `Packages/Core/Sources/Core/Models/Conversation.swift:23-27`
- **What:** Placeholder wird appended, dann die gefüllte Message erneut via `Conversation.append` (unbedingtes `messages.append`); Error/Cancel-Pfade appenden ein drittes Mal.
- **Why:** Aktuell von SwiftData (Inverse-Relationship + unique id) wegkompensiert — fragil.
- **Action:** „Neu einfügen" von „Änderung persistieren" trennen (einmal append, danach nur `context.save()`).
- **Severity:** Low

---

## 6. Security

### 6.1 Volles Diktat-Transkript mit `privacy: .public` geloggt
- **Location:** `Tide/Dictation/DictationCoordinator.swift:173`
- **What:** `logger.debug(...'\(trimmed, privacy: .public)'...)` loggt den gesamten diktierten Text unredigiert — die einzige Stelle der App, die Inhalt statt Zeichenzahl loggt.
- **Why:** Diktate sind die sensibelsten Daten der App (Passwörter, private Nachrichten in beliebige Felder). `.public` deaktiviert die OSLog-Standard-Redaktion; `log stream --level debug` zeigt alles im Klartext.
- **Action:** Inhalt aus dem Log nehmen oder `.private`; nur Länge/Dauer loggen. **Verifiziert.** (Quick Win §2.1.)
- **Severity:** High

### 6.2 Keychain: `kSecUseDataProtectionKeychain` fehlt
- **Location:** `Packages/Core/Sources/Core/Security/KeychainHelper.swift:20-42`
- **What:** `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` ist gesetzt, aber ohne `kSecUseDataProtectionKeychain: true` ignoriert das Legacy-File-Keychain auf macOS das Accessibility-Attribut.
- **Why:** Die beabsichtigte Device-Bindung/Backup-Exklusion greift nicht. (Keine akute Exposure — Secret bleibt im Keychain.)
- **Action:** `kSecUseDataProtectionKeychain` in allen vier Queries ergänzen.
- **Severity:** Low

---

## 7. Performance

### 7.1 Markdown-Reparse pro Streaming-Token
- **Location:** `Tide/Panel/MessageBubble.swift:15, 60-69`
- **What:** `AttributedString(markdown:)` wird in `body` gebaut; die streamende Bubble re-evaluiert `body` pro Token-Append.
- **Why:** O(n) Parse pro Token → O(n²) über lange Antworten, auf dem Main Actor, im heißesten Pfad der App.
- **Action:** Parse aus `body` hoisten: `(content, AttributedString)`-Cache oder Debounce; während des Streams Rohtext rendern, Markdown erst bei Abschluss.
- **Severity:** Medium

### 7.2 `hasSelectionContext` sortiert die ganze Conversation pro Bubble-Render
- **Location:** `Tide/Panel/MessageBubble.swift:36, 79-88`; `Packages/Core/Sources/Core/Models/Conversation.swift:33-35`
- **What:** Computed Property ruft `orderedMessages` (Full-Sort) + Linear-Scan in `body` auf.
- **Why:** Kombiniert mit §7.1: Re-Sort des gesamten Verlaufs pro Token; Kosten wachsen mit Konversationslänge.
- **Action:** Flag einmal bei Message-Erzeugung berechnen bzw. aus `MessageList` durchreichen.
- **Severity:** Medium

### 7.3 QuickActions werden in `body` aus UserDefaults JSON-dekodiert
- **Location:** `Tide/Panel/ChatContainer.swift:16` → `ChatViewModel.swift:37` → `QuickActionLibrary.custom()`
- **What:** Jeder Zugriff dekodiert den Custom-Actions-Blob; gelesen in `ChatContainer.body`, das bei jedem Tastendruck re-rendert.
- **Why:** JSON-Decode pro Keystroke.
- **Action:** Einmal in State laden, nur bei Editor-Mutation refreshen.
- **Severity:** Medium

### 7.4 `appleVoices` enumeriert alle Systemstimmen in `body`
- **Location:** `Tide/Settings/VoiceSection.swift:15-19, 44`
- **What:** `AVSpeechSynthesisVoice.speechVoices()` + Filter + Sort als Computed Property im Picker.
- **Why:** Voller Katalog-Scan bei jeder Body-Evaluation der Section.
- **Action:** Einmal in `.task`/`.onAppear` laden.
- **Severity:** Low

### 7.5 Selection-Read blockiert Main Thread bis 200 ms
- **Location:** `Packages/Selection/Sources/Selection/SelectionReader.swift:77-80`; Callchain `Tide/Menubar/MenubarController.swift:168-171` → `Tide/AppEntry.swift:124`
- **What:** `readViaClipboardCopy` pollt das Pasteboard mit `Thread.sleep` auf dem Main Actor.
- **Why:** UI-Hang bei jedem Push-to-Talk, wenn der AX-Pfad fehlschlägt (Slack/Electron/Web — der Regelfall).
- **Action:** Selection-Read `async` machen, ⌘C-Landung nicht-blockierend abwarten.
- **Severity:** Medium

### 7.6 Scroll-Animation pro Token
- **Location:** `Tide/Panel/MessageList.swift:50-54`
- **What:** `.onChange(of: messages.last?.content)` feuert `withAnimation { scrollTo }` pro Content-Mutation.
- **Why:** Konkurrierende Animations-Transaktionen, ruckeliges Scrollen bei schnellen Streams.
- **Action:** Während des Streams ohne Animation scrollen (oder debouncen), Animation nur an Message-Grenzen.
- **Severity:** Low

### 7.7 Byte-weises SSE-Framing scannt Buffer pro Byte
- **Location:** `Packages/LLM/Sources/LLM/Anthropic/AnthropicProvider.swift:51-64`
- **What:** Ein Byte pro Iteration appenden + `Data.range(of:)` über den wachsenden Buffer.
- **Why:** O(m²) pro unterminierten Event-Block; geringer Impact, da Events klein sind.
- **Action:** Chunk-weise lesen, nur neu angehängte Daten auf Separator scannen.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 Feste Punktgrößen ignorieren Dynamic Type
- **Location:** `Tide/Panel/MessageBubble.swift:31,41`, `Tide/Panel/QuickActionsBar.swift:39`, `Tide/Panel/SelectionContextBadge.swift:14,16`, `Tide/Dictation/FloatingPill.swift:34`, `Tide/Settings/QuickActionsEditor.swift:17,23,42,45`, `Tide/Settings/DictationSection.swift:68`
- **What:** Diverse `.font(.system(size: 10–13))` für echten Content-Text.
- **Why:** Skaliert nicht mit den Textgrößen-Bedienungshilfen — Problem für sehschwache Nutzer.
- **Action:** Semantische Styles (`.caption`, `.footnote`, `.callout`) verwenden.
- **Severity:** Medium

### 8.2 QuickActions-Pills exponieren Auswahlzustand nicht an VoiceOver
- **Location:** `Tide/Panel/QuickActionsBar.swift:36-45`
- **What:** Auswahl nur visuell (Farbe/Gewicht); kein `.accessibilityAddTraits(.isSelected)`.
- **Why:** VoiceOver-Nutzer erkennen die aktive Action nicht.
- **Action:** `.isSelected`-Trait konditional setzen.
- **Severity:** Low

### 8.3 Icon-Button ohne Accessibility-Label
- **Location:** `Tide/Panel/SelectionContextBadge.swift:20-24`
- **What:** Dismiss-Button (`xmark.circle.fill`) unbenannt — im Kontrast zu den vorbildlich gelabelten TopBar-Buttons.
- **Action:** Label ergänzen. (Quick Win §2.5.)
- **Severity:** Low

### 8.4 FloatingPill: Legacy-Material statt Liquid Glass (macOS 27)
- **Location:** `Tide/Dictation/FloatingPill.swift:41, 98-106`; auch `Tide/Menubar/PanelWindow.swift`
- **What:** `.regularMaterial`-Rechteck in borderless `NSPanel` mit manuellem Schatten; nimmt an macOS 27s nutzer-einstellbarer Glas-Opazität (ultraclear→tinted) nicht teil.
- **Why:** Wirkt neben System-Glass-Flächen veraltet/inkonsistent; ignoriert Nutzer-Präferenz.
- **Action:** `glassEffect` mit Availability-Gate adoptieren (`.regularMaterial` als macOS-14-Fallback), Schatten/Blur dem OS überlassen; Panel-Fenster gleich mitbehandeln.
- **Severity:** Medium

### 8.5 Sprach-Mix und keine Lokalisierungs-Infrastruktur
- **Location:** `Tide/Settings/DictationSection.swift:20-27` (englische Mode-Namen in deutscher UI); UI-Layer generell ohne String Catalog
- **What:** „Polished/Calmer/Emoji/Bullets/Professional" in sonst deutscher UI; alle Strings hartkodiert.
- **Why:** Inkonsistent; Lokalisierung später teuer nachzurüsten.
- **Action:** Sprache der Mode-Namen vereinheitlichen; bei Lokalisierungsabsicht String Catalog einführen.
- **Severity:** Low

---

## 9. Dead Code / Duplikation / Refactoring

Bemerkenswert: **kein** `print`, `TODO`, `try!`, `as!`, kein auskommentierter Code, keine toten Typen oder Settings-Keys gefunden. Alle Findings hier sind Duplikation/Struktur.

### 9.1 ChatViewModel: fünf Verantwortlichkeiten in 509 Zeilen
- **Location:** `Tide/Panel/ChatViewModel.swift:11-509`
- **What:** LLM-Streaming + Retry, TTS-Management (100-117, 294-321, 385-388), Recording-Lifecycle (390-495), STT-Reject-Logik und History-CRUD in einer `@Observable`-Klasse.
- **Why:** Größte Datei der App; erschwert isoliertes Testen, begünstigt §9.2.
- **Action:** TTS-Manager und Recording-Controller extrahieren (letzterer geteilt mit DictationCoordinator); ChatViewModel orchestriert nur noch Chat + History.
- **Severity:** Medium

### 9.2 Recorder-Setup + Reject-Check byte-identisch dupliziert
- **Location:** `Tide/Panel/ChatViewModel.swift:402-419, 465-467` vs. `Tide/Dictation/DictationCoordinator.swift:106-122, 174-176`
- **What:** Der Block „Choice + apiKey + Accumulator + WhisperModelStore + RecognizerFactory + AudioRecorder" und die dreizeilige Reject-Prüfung existieren zweimal identisch.
- **Why:** Änderung an der Reject-Heuristik muss an zwei Stellen erfolgen.
- **Action:** Gemeinsame `makeRecordingSession(settings:)`-Factory + `TranscriptionQuality.isReject(text:duration:)`-Convenience.
- **Severity:** Medium

### 9.3 Drei kopierte API-Key-Eingabe-Views mit divergentem Fehlerverhalten
- **Location:** `Tide/Panel/ApiKeyPromptView.swift:4-36`, `Tide/Onboarding/Steps/OnboardingSteps.swift:23-46`, `Tide/Settings/ApiKeySection.swift:4`
- **What:** Dreimal SecureField + Speichern + Keychain-Write; nur die Panel-Variante zeigt Keychain-Fehler, die anderen zwei `try?`-verschlucken sie.
- **Why:** Behavior-Drift; Key-Validierungs-Fixes müssen dreifach erfolgen.
- **Action:** Ein wiederverwendbares `ApiKeyField` mit konsistenter Fehleranzeige.
- **Severity:** Medium

### 9.4 Keychain-Key-Strings als Magic Literals an ~15 Stellen
- **Location:** `"anthropic.api_key"`: `Tide/AppEntry.swift:89,113`, `ApiKeySection.swift:6,18,29`, `PanelView.swift:11`, `ApiKeyPromptView.swift:24`, `DictationPolisher.swift:74`, `OnboardingView.swift:12`, `OnboardingSteps.swift:39-40`; `"elevenlabs.api_key"`: `ChatViewModel.swift:101,404`, `VoiceSection.swift:8,56`, `DictationCoordinator.swift:107`
- **What:** Beide Keychain-Identifier handgetippt, kein gemeinsames Konstanten-Enum.
- **Why:** Tippfehler failen still (nil → „kein Key").
- **Action:** `enum KeychainKey` in Core, überall referenzieren.
- **Severity:** Medium

### 9.5 Duplizierter Notification-Helper
- **Location:** `Tide/Dictation/DictationCoordinator.swift:218-242` vs. `Packages/Selection/Sources/Selection/TextInjector.swift:193-214`
- **What:** Zwei fast identische UNUserNotification-Routinen (Authorization + Content + Request + Log).
- **Action:** Gemeinsamen `postTideNotification(body:idPrefix:)`-Helper extrahieren.
- **Severity:** Low

### 9.6 Testlücken bei zentralen Subsystemen
- **Location:** `Tide/Dictation/DictationCoordinator.swift` (0 Test-Referenzen), `Tide/Recorder/AudioRecorder.swift`, `Packages/Speech/.../CompositeSynthesizer.swift`, beide Synthesizer, `Tide/Menubar/MenubarController.swift`
- **What:** Die komplette Standalone-Diktat-Orchestrierung inkl. Polish-Fallback (157-208) ist ungetestet — während DictationPolisher, ChatViewModel, RecognizerFactory, TranscriptionQuality, AppSettings, ConversationStore gut abgedeckt sind.
- **Why:** Zentrales User-Facing-Verhalten mit Fallback-Pfad (Polish-Fail → Raw-Insert) ohne Netz.
- **Action:** DictationCoordinator-Test mit Stub-Provider/-Recognizer (Muster existiert in DictationPolisherTests); CompositeSynthesizer-Provider-Switch-Test.
- **Severity:** Medium

### 9.7 Kein SwiftLint/SwiftFormat
- **Location:** Repo-Root, `.github/workflows/tide-test.yml`
- **What:** Keine Linter-Config; CI läuft nur Tests.
- **Why:** Stil ist aktuell handkonsistent, nichts erzwingt ihn; Duplikate (§9.2–9.5) würden früher auffallen.
- **Action:** Minimale Config + CI-Lint-Step. Niedrige Priorität.
- **Severity:** Low

---

## 10. Querschnitts-Empfehlungen

1. **Key-Lifecycle zentralisieren:** §5.1, §9.3 und §9.4 haben dieselbe Wurzel — es gibt keinen einzelnen Ort, der „API-Key gesetzt/geändert" besitzt. Ein kleiner `CredentialsStore` (Observable, Keychain-backed) löst alle drei.
2. **Recording-Session als geteilte Abstraktion:** §9.1 + §9.2 zusammen angehen — ein `RecordingSession`-Typ, den ChatViewModel und DictationCoordinator konsumieren.
3. **„Nichts in `body` berechnen"-Pass:** §7.1–7.4 sind dasselbe Muster (Parse/Sort/Decode/Enumerate in `body`). Ein gezielter Sweep über alle Views lohnt.
4. **Ein-Isolation-Domäne-Regel für Playback:** §3.1 + §3.2 zusammen — Synthesizer komplett `@MainActor`, Tasks tracken.
5. **macOS-27-Beta-Runtime-Test:** Build ist sauber, aber TCC (Mikrofon, Accessibility, Speech), Text-Injektion und Sparkle-Update auf der Beta einmal manuell durchspielen (§4.4, §8.4).

---

## 11. Nicht auditiert

- WhisperKit-Interna und Modell-Qualität (Third-Party, Black Box).
- Algorithmen-Korrektheit der Transkriptions-Heuristiken (`TranscriptionQuality`-Schwellwerte).
- Laufzeit-Profiling (Instruments); Performance-Findings basieren auf Code-Lektüre.
- Release-Pipeline-Skripte (`scripts/release.sh`, `sign_appcast.sh`) — nur Existenz geprüft.
- Lokalisierungs-Wortlaut; Test-Assertions inhaltlich.
- macOS-27-Runtime-Verhalten (nur SDK-Build + Recherche, kein Beta-Testlauf).

---

## 12. Verifikation

- **§5.1** — `Tide/AppEntry.swift:89-90` geöffnet: Provider wird mit `KeychainHelper.get(...) ?? ""` einmalig gebaut; `AnthropicProvider.apiKey` ist `let`; kein Rebuild-Pfad existiert. Bestätigt.
- **§5.2** — `AppleSpeechRecognizer.swift:42-44` geöffnet: `guard let recognizer = SFSpeechRecognizer(locale:) else { fatalError(...) }`. Bestätigt.
- **§6.1** — `DictationCoordinator.swift:173` geöffnet: `'\(trimmed, privacy: .public)'` loggt das volle Transkript. Bestätigt.
- Build-Ground-Truth: `xcodebuild clean build` (Xcode 27.0, Scheme Tide, Debug) — 0 Projekt-Warnings; einziger Output: harmloser `appintentsmetadataprocessor`-Hinweis (kein AppIntents-Target).
