# Tide — Onboarding-Wizard — Design-Spec

**Datum:** 04. Juni 2026
**Status:** Design abgesegnet (Dominik), bereit für Implementation-Plan
**Roadmap:** Welle 9 (Onboarding-Flow)

---

## Problem

Erstnutzer öffnen Tide und sehen nichts — `LSUIElement`, kein Fenster, nur ein
Menubar-Icon. Es gibt keinen geführten Flow: API-Key, Berechtigungen (Mic,
Accessibility, Spracherkennung) und Hotkeys muss man selbst in Settings finden.
Diktat-Hotkeys sind opt-in (kein Default) → das Feature ist unsichtbar bis man
manuell bindet. Ohne Mic-/AX-Permission scheitern Diktat/Selektion still.

## Ziel

Ein gestufter Onboarding-Wizard (eigenes Fenster), der beim ersten Start
automatisch erscheint (wenn kein Anthropic-Key gesetzt) und durch die Erst-
Einrichtung führt. Manuell erneut aufrufbar über einen Button in Settings.

Nicht-Ziel: Account/Sync, Tutorial-Overlays, mehrsprachige Lokalisierung
(UI ist Deutsch wie der Rest).

## Befunde

- Menubar: Left-Click → Panel; **kein NSMenu**, kein sichtbares App-Menü.
- Permissions heute verstreut + lazy: AX via `AXIsProcessTrustedWithOptions`
  (SelectionReader), Speech via `SFSpeechRecognizer.requestAuthorization`
  (AppleSpeechRecognizer), Mic implizit über AVAudioEngine.
- Settings-Fenster existiert (`MenubarController.openSettings`, NSWindow +
  NSHostingController) — der Onboarding-Window-Lifecycle spiegelt das.

## Komponenten (neu, `Tide/Onboarding/`)

### `OnboardingStep` (enum)
`enum OnboardingStep: Int, CaseIterable` — `welcome, apiKey, permissions,
hotkey, voice, done`. Helpers: `next`/`previous` (clamped an die Grenzen),
`title`, Schritt-Index/Gesamtzahl für die Fortschrittsanzeige.

### `OnboardingView` (SwiftUI)
Wizard-Container. `@State step: OnboardingStep = .welcome`. Layout: Kopf mit
Titel + Fortschritts-Punkten, Mitte die aktuelle Step-Subview, Fuß mit
Zurück/Weiter (bzw. „Fertig" auf `.done`). „Weiter" auf `.apiKey` ist deaktiviert,
bis ein Key gespeichert ist. Schließt via `dismiss`/Window-Close-Callback.

Pro Schritt eine fokussierte Subview:
- **`WelcomeStep`** — was Tide ist + was eingerichtet wird.
- **`ApiKeyStep`** — `SecureField` + Speichern in Keychain (`anthropic.api_key`),
  Live-✓ bei vorhandenem Key. Wiederverwendet die Keychain-Logik der bestehenden
  `ApiKeySection` (gleiche Keys), als schlanke Wizard-Variante.
- **`PermissionsStep`** — drei Zeilen (Mic, Spracherkennung, Accessibility), je
  Status-Haken + „Erlauben"-Button. Nutzt `PermissionsService`. AX-Status pollt
  beim Erscheinen / per kurzem Timer (in-process nicht grantbar; Button öffnet
  den System-Dialog/-Einstellungen).
- **`HotkeyStep`** — `KeyboardShortcuts.Recorder` für `.pushToTalk` (Default
  Option+Return) + `.dictateRaw` (opt-in sichtbar machen).
- **`VoiceStep`** — schlanker Recognizer-Picker (`SpeechRecognizerChoice.allCases`)
  + TTS-Provider-Toggle. Schreibt in `AppSettings` (`speechRecognizer`,
  `ttsProvider`). Keine ElevenLabs-Key/Voice-Fetch-Tiefe hier (das bleibt der
  vollen `VoiceSection` in Settings vorbehalten — Hinweis-Text verlinkt drauf).
- **`DoneStep`** — „Fertig" + Hinweis „alles jederzeit in Settings änderbar".

### `PermissionsService` (neu)
Reine Status-/Request-Fassade, `@MainActor`:
```
enum PermissionStatus { case granted, denied, notDetermined }
struct PermissionsService {
  func microphone() -> PermissionStatus            // AVCaptureDevice.authorizationStatus(for: .audio)
  func requestMicrophone() async -> Bool           // AVCaptureDevice.requestAccess(for: .audio)
  func speech() -> PermissionStatus                // SFSpeechRecognizer.authorizationStatus()
  func requestSpeech() async -> Bool               // SFSpeechRecognizer.requestAuthorization
  func accessibility() -> Bool                     // AXIsProcessTrusted()
  func promptAccessibility()                        // AXIsProcessTrustedWithOptions(prompt:true)
}
```
Mapping von `AVAuthorizationStatus`/`SFSpeechRecognizerAuthorizationStatus` auf
`PermissionStatus` ist die testbare Logik (`.authorized→granted`,
`.denied/.restricted→denied`, `.notDetermined→notDetermined`).

## Window-Lifecycle

`MenubarController.openOnboarding()` — analog zu `openSettings()`: eigenes
`NSWindow` (`.titled, .closable`, ~560×460, zentriert, `isReleasedWhenClosed =
false`), `NSHostingController(rootView: OnboardingView(onClose:))`. Wiederholter
Aufruf bringt das bestehende Fenster nach vorn (single-instance Referenz wie
`settingsWindow`).

## Trigger

`AppEntry`, nach dem Controller-Setup im `Task { @MainActor }`: wenn
`KeychainHelper.get(key: "anthropic.api_key")` nil/leer → `controller.openOnboarding()`.
Kein separates Flag (Trigger ist der fehlende Key). „Fertig" schließt nur das
Fenster.

## Re-Run (Settings-Button + NotificationCenter)

`ApiKeySection` (Settings → Allgemein → API) bekommt unten einen Button
„Onboarding erneut starten". SwiftUI-Settings-Views haben keinen DI-Pfad zum
`MenubarController` → der Button postet `NotificationCenter.default.post(name:
.tideOpenOnboarding)`; `MenubarController` beobachtet die Notification (im init)
und ruft `openOnboarding()`. Entkoppelt, kein Singleton.

`Notification.Name.tideOpenOnboarding` als Konstante im App-Target.

## Fehlerbehandlung

- Permission verweigert → Zeile zeigt „verweigert" + Hinweis, dass es in den
  Systemeinstellungen änderbar ist; Wizard blockiert NICHT darauf (man kann
  weiter, Features scheitern dann eben bis nachgeholt). Nur `.apiKey` ist ein
  harter Gate für „Weiter".
- AX-Prompt öffnet Systemeinstellungen; Status wird beim Zurückkehren gepollt.

## Tests

- `OnboardingStepTests`: `allCases` Reihenfolge; `next` clamped auf `.done`,
  `previous` clamped auf `.welcome`; Index/Count für Progress stimmen.
- `PermissionsServiceTests`: das `AVAuthorizationStatus`/`SF…Status` →
  `PermissionStatus`-Mapping (pure-function-Teil; die System-Calls selbst nicht).
- Rest: Build + manueller Smoke (Erststart ohne Key → Wizard; jeder Schritt;
  Re-Run-Button; Permission-Haken aktualisieren live).

## Implementation-Qualität

`swiftui-pro`-Skill für Review der Wizard-Views (Navigation, State, moderne APIs).

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `Tide/Onboarding/OnboardingStep.swift` | **neu** — enum + Navigation/Progress |
| `Tide/Onboarding/OnboardingView.swift` | **neu** — Wizard-Container |
| `Tide/Onboarding/Steps/*.swift` | **neu** — Welcome/ApiKey/Permissions/Hotkey/Voice/Done |
| `Tide/Onboarding/PermissionsService.swift` | **neu** — Status/Request-Fassade |
| `Tide/Menubar/MenubarController.swift` | `openOnboarding()` + Notification-Observer + `onboardingWindow`-Ref |
| `Tide/AppEntry.swift` | Auto-Trigger bei fehlendem Key |
| `Tide/Settings/ApiKeySection.swift` | „Onboarding erneut starten"-Button (postet Notification) |
| `Tide/Support/Notifications.swift` (o.ä.) | `Notification.Name.tideOpenOnboarding` |
| `TideTests/OnboardingStepTests.swift` | **neu** |
| `TideTests/PermissionsServiceTests.swift` | **neu** |
| `README.md` / `CHANGELOG.md` | Roadmap-Welle 9 + Eintrag |
