# Onboarding Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A stepped first-run onboarding wizard (Welcome → API-Key → Permissions → Hotkey → Voice → Done) that auto-opens when no Anthropic key is set, plus a Settings button to re-run it.

**Architecture:** New `Tide/Onboarding/` module: `OnboardingStep` enum (navigation), `PermissionsService` (mic/speech/AX fassade), `OnboardingView` container + six step subviews. `MenubarController.openOnboarding()` owns the window (mirrors `openSettings`); `AppEntry` triggers it on first launch; a Settings button re-runs it via `NotificationCenter`.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation/Speech/ApplicationServices (permissions), KeyboardShortcuts, XCTest. App build/test via `xcodebuild … CODE_SIGNING_ALLOWED=NO`. New files need `xcodegen generate` before xcodebuild sees them.

> Reminder: a running Tide instance kills the app-target test host UNLESS the XCTest-guard is present (it is, on main). Still, quit any dev Tide before full `xcodebuild test` to be safe.

---

## File Structure

| Datei | Verantwortung |
|---|---|
| `Tide/Support/Notifications.swift` | `Notification.Name.tideOpenOnboarding` |
| `Tide/Onboarding/OnboardingStep.swift` | enum + navigation/progress |
| `Tide/Onboarding/PermissionsService.swift` | mic/speech/AX status + request |
| `Tide/Onboarding/OnboardingView.swift` | wizard container |
| `Tide/Onboarding/Steps/OnboardingSteps.swift` | the six step subviews |
| `Tide/Menubar/MenubarController.swift` | `openOnboarding()` + notification observer |
| `Tide/AppEntry.swift` | auto-trigger on first launch |
| `Tide/Settings/ApiKeySection.swift` | "Onboarding erneut starten" button |
| `TideTests/OnboardingStepTests.swift` | enum/navigation tests |
| `TideTests/PermissionsServiceTests.swift` | status-mapping tests |
| `README.md`, `CHANGELOG.md` | docs |

**Branch:** Vor Task 1: `git checkout -b feat/onboarding-wizard`

---

## Task 1: `Notification.Name` + `OnboardingStep` + tests

**Files:**
- Create: `Tide/Support/Notifications.swift`, `Tide/Onboarding/OnboardingStep.swift`
- Test: `TideTests/OnboardingStepTests.swift`

- [ ] **Step 1: Write failing tests** — create `TideTests/OnboardingStepTests.swift`:

```swift
import XCTest
@testable import Tide

final class OnboardingStepTests: XCTestCase {
  func test_order() {
    XCTAssertEqual(OnboardingStep.allCases,
      [.welcome, .apiKey, .permissions, .hotkey, .voice, .done])
  }

  func test_next_clampsAtDone() {
    XCTAssertEqual(OnboardingStep.welcome.next, .apiKey)
    XCTAssertEqual(OnboardingStep.done.next, .done)
  }

  func test_previous_clampsAtWelcome() {
    XCTAssertEqual(OnboardingStep.apiKey.previous, .welcome)
    XCTAssertEqual(OnboardingStep.welcome.previous, .welcome)
  }

  func test_progress_indexAndCount() {
    XCTAssertEqual(OnboardingStep.welcome.index, 0)
    XCTAssertEqual(OnboardingStep.done.index, 5)
    XCTAssertEqual(OnboardingStep.count, 6)
  }

  func test_titlesNonEmpty() {
    for s in OnboardingStep.allCases { XCTAssertFalse(s.title.isEmpty) }
  }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `xcodegen generate && xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/OnboardingStepTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -12`
Expected: FAIL — `cannot find 'OnboardingStep'`.

- [ ] **Step 3: Implement**

Create `Tide/Support/Notifications.swift`:

```swift
import Foundation

extension Notification.Name {
  /// Posted by the Settings "Onboarding erneut starten" button; observed by
  /// MenubarController to (re)open the onboarding wizard.
  static let tideOpenOnboarding = Notification.Name("tide.openOnboarding")
}
```

Create `Tide/Onboarding/OnboardingStep.swift`:

```swift
import Foundation

/// The ordered steps of the first-run onboarding wizard.
enum OnboardingStep: Int, CaseIterable, Hashable {
  case welcome
  case apiKey
  case permissions
  case hotkey
  case voice
  case done

  static var count: Int { allCases.count }

  /// Zero-based position, for the progress indicator.
  var index: Int { rawValue }

  /// Next step, clamped at `.done`.
  var next: OnboardingStep {
    OnboardingStep(rawValue: rawValue + 1) ?? .done
  }

  /// Previous step, clamped at `.welcome`.
  var previous: OnboardingStep {
    OnboardingStep(rawValue: rawValue - 1) ?? .welcome
  }

  var title: String {
    switch self {
    case .welcome:     "Willkommen bei Tide"
    case .apiKey:      "Anthropic API-Key"
    case .permissions: "Berechtigungen"
    case .hotkey:      "Hotkeys"
    case .voice:       "Sprache & Stimme"
    case .done:        "Fertig"
    }
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/OnboardingStepTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -8`
Expected: `TEST SUCCEEDED` (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Tide/Support/Notifications.swift Tide/Onboarding/OnboardingStep.swift TideTests/OnboardingStepTests.swift
git commit -m "feat(onboarding): OnboardingStep enum + open-onboarding notification

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `PermissionsService` + tests

**Files:**
- Create: `Tide/Onboarding/PermissionsService.swift`
- Test: `TideTests/PermissionsServiceTests.swift`

- [ ] **Step 1: Write failing tests** — create `TideTests/PermissionsServiceTests.swift`:

```swift
import XCTest
import AVFoundation
import Speech
@testable import Tide

final class PermissionsServiceTests: XCTestCase {
  func test_avStatusMapping() {
    XCTAssertEqual(PermissionsService.map(AVAuthorizationStatus.authorized), .granted)
    XCTAssertEqual(PermissionsService.map(AVAuthorizationStatus.denied), .denied)
    XCTAssertEqual(PermissionsService.map(AVAuthorizationStatus.restricted), .denied)
    XCTAssertEqual(PermissionsService.map(AVAuthorizationStatus.notDetermined), .notDetermined)
  }

  func test_speechStatusMapping() {
    XCTAssertEqual(PermissionsService.map(SFSpeechRecognizerAuthorizationStatus.authorized), .granted)
    XCTAssertEqual(PermissionsService.map(SFSpeechRecognizerAuthorizationStatus.denied), .denied)
    XCTAssertEqual(PermissionsService.map(SFSpeechRecognizerAuthorizationStatus.restricted), .denied)
    XCTAssertEqual(PermissionsService.map(SFSpeechRecognizerAuthorizationStatus.notDetermined), .notDetermined)
  }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/PermissionsServiceTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -12`
Expected: FAIL — `cannot find 'PermissionsService'`.

- [ ] **Step 3: Implement**

Create `Tide/Onboarding/PermissionsService.swift`:

```swift
import Foundation
import AVFoundation
import Speech
import ApplicationServices

/// Tri-state permission status for the onboarding UI.
enum PermissionStatus: Equatable {
  case granted
  case denied
  case notDetermined
}

/// Thin fassade over the system permission APIs the onboarding wizard needs:
/// microphone, speech recognition, and Accessibility. The status→enum
/// mapping is the unit-tested part; the system calls themselves are not.
@MainActor
struct PermissionsService {

  // MARK: Mapping (pure, tested)

  static func map(_ s: AVAuthorizationStatus) -> PermissionStatus {
    switch s {
    case .authorized:    .granted
    case .denied:        .denied
    case .restricted:    .denied
    case .notDetermined: .notDetermined
    @unknown default:    .notDetermined
    }
  }

  static func map(_ s: SFSpeechRecognizerAuthorizationStatus) -> PermissionStatus {
    switch s {
    case .authorized:    .granted
    case .denied:        .denied
    case .restricted:    .denied
    case .notDetermined: .notDetermined
    @unknown default:    .notDetermined
    }
  }

  // MARK: Microphone

  func microphone() -> PermissionStatus {
    Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
  }

  func requestMicrophone() async -> Bool {
    await AVCaptureDevice.requestAccess(for: .audio)
  }

  // MARK: Speech recognition

  func speech() -> PermissionStatus {
    Self.map(SFSpeechRecognizer.authorizationStatus())
  }

  func requestSpeech() async -> Bool {
    await withCheckedContinuation { cont in
      SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
    }
  }

  // MARK: Accessibility (cannot be granted in-process)

  func accessibility() -> Bool {
    AXIsProcessTrusted()
  }

  /// Opens the system Accessibility prompt / Settings pane. The user must
  /// toggle Tide on there; poll `accessibility()` afterwards.
  func promptAccessibility() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild test -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' -only-testing:TideTests/PermissionsServiceTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -8`
Expected: `TEST SUCCEEDED` (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Tide/Onboarding/PermissionsService.swift TideTests/PermissionsServiceTests.swift
git commit -m "feat(onboarding): PermissionsService fassade + status mapping

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `OnboardingView` container + step subviews

**Files:**
- Create: `Tide/Onboarding/OnboardingView.swift`, `Tide/Onboarding/Steps/OnboardingSteps.swift`

No unit test — SwiftUI glue, build + manual smoke.

- [ ] **Step 1: Create the step subviews**

Create `Tide/Onboarding/Steps/OnboardingSteps.swift`:

```swift
import SwiftUI
import Core
import TideSpeech
import KeyboardShortcuts

// MARK: Welcome

struct WelcomeStep: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Tide ist deine immer-erreichbare KI in der Menubar.")
        .font(.title3).bold()
      Text("Dieser kurze Einrichtungs-Assistent verbindet deinen Anthropic-"
        + "API-Key, holt die nötigen Berechtigungen und richtet deine Hotkeys "
        + "ein. Alles ist später in den Einstellungen änderbar.")
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: API-Key

struct ApiKeyStep: View {
  /// Binding so the container can gate "Weiter" on a present key.
  @Binding var hasKey: Bool
  @State private var input = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Tide spricht mit Claude über die Anthropic-API. Den Key erstellst "
        + "du unter console.anthropic.com.")
        .foregroundStyle(.secondary)
      if hasKey {
        Label("API-Key gesetzt", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      }
      SecureField("sk-ant-…", text: $input)
        .textFieldStyle(.roundedBorder)
      Button("Speichern") {
        try? KeychainHelper.set(key: "anthropic.api_key", value: input)
        hasKey = KeychainHelper.get(key: "anthropic.api_key")?.isEmpty == false
        input = ""
      }
      .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
    }
  }
}

// MARK: Permissions

struct PermissionsStep: View {
  @State private var mic: PermissionStatus = .notDetermined
  @State private var speech: PermissionStatus = .notDetermined
  @State private var ax = false
  private let service = PermissionsService()

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Ohne diese Berechtigungen scheitern Diktat und Text-Selektion still.")
        .font(.caption).foregroundStyle(.secondary)
      permissionRow("Mikrofon", granted: mic == .granted) {
        _ = await service.requestMicrophone(); refresh()
      }
      permissionRow("Spracherkennung", granted: speech == .granted) {
        _ = await service.requestSpeech(); refresh()
      }
      permissionRow("Bedienungshilfen (Accessibility)", granted: ax) {
        service.promptAccessibility()
      }
      Text("Accessibility wird in den Systemeinstellungen aktiviert — der "
        + "Haken aktualisiert sich, sobald du zurückkommst.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .task { refresh() }
    .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
      refresh()
    }
  }

  private func refresh() {
    mic = service.microphone()
    speech = service.speech()
    ax = service.accessibility()
  }

  @ViewBuilder
  private func permissionRow(_ label: String, granted: Bool, action: @escaping () async -> Void) -> some View {
    HStack {
      Image(systemName: granted ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(granted ? .green : .secondary)
      Text(label)
      Spacer()
      if !granted {
        Button("Erlauben") { Task { await action() } }
          .controlSize(.small)
      }
    }
  }
}

// MARK: Hotkey

struct HotkeyStep: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Push-to-Talk öffnet das Panel und spricht mit Claude. Diktat fügt "
        + "Text direkt am Cursor der fokussierten App ein.")
        .font(.caption).foregroundStyle(.secondary)
      KeyboardShortcuts.Recorder("Push-to-Talk:", name: .pushToTalk)
      KeyboardShortcuts.Recorder("Diktieren (Roh):", name: .dictateRaw)
      Text("Weitere Diktat-Modi (Polished, Calmer, …) bindest du später unter "
        + "Einstellungen → Diktat → Hotkey.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}

// MARK: Voice / Recognizer

struct VoiceStep: View {
  @State private var settings = AppSettings()
  @State private var recognizer: SpeechRecognizerChoice = .default
  @State private var tts: String = "apple"

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Picker("Spracherkennung:", selection: $recognizer) {
        ForEach(SpeechRecognizerChoice.allCases, id: \.self) { c in
          Text(c.displayName).tag(c)
        }
      }
      .onChange(of: recognizer) { _, v in settings.speechRecognizer = v.rawValue }

      Picker("Vorlese-Stimme:", selection: $tts) {
        Text("Apple (System)").tag("apple")
        Text("ElevenLabs (Cloud)").tag("elevenLabs")
      }
      .pickerStyle(.segmented)
      .onChange(of: tts) { _, v in settings.ttsProvider = v }

      Text("ElevenLabs- und lokale-Modell-Details richtest du in "
        + "Einstellungen → Sprache ein.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .task {
      recognizer = SpeechRecognizerChoice(rawValue: settings.speechRecognizer) ?? .default
      tts = settings.ttsProvider
    }
  }
}

// MARK: Done

struct DoneStep: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Alles eingerichtet", systemImage: "checkmark.seal.fill")
        .font(.title3).bold()
        .foregroundStyle(.green)
      Text("Halte deinen Push-to-Talk-Hotkey und sprich mit Claude. Alle "
        + "Einstellungen findest du jederzeit über das Menubar-Icon → Zahnrad.")
        .foregroundStyle(.secondary)
    }
  }
}
```

- [ ] **Step 2: Create the container**

Create `Tide/Onboarding/OnboardingView.swift`:

```swift
import SwiftUI
import Core

/// First-run onboarding wizard. Stepped flow; `onClose` is invoked by the
/// final "Fertig" button (and is wired by MenubarController to close the
/// hosting window).
struct OnboardingView: View {
  let onClose: () -> Void

  @State private var step: OnboardingStep = .welcome
  @State private var hasKey = KeychainHelper.get(key: "anthropic.api_key")?.isEmpty == false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      Divider()
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      Divider()
      footer
    }
    .padding(24)
    .frame(width: 560, height: 460)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(step.title).font(.title2).bold()
      HStack(spacing: 6) {
        ForEach(OnboardingStep.allCases, id: \.self) { s in
          Circle()
            .fill(s.index <= step.index ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(width: 7, height: 7)
        }
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch step {
    case .welcome:     WelcomeStep()
    case .apiKey:      ApiKeyStep(hasKey: $hasKey)
    case .permissions: PermissionsStep()
    case .hotkey:      HotkeyStep()
    case .voice:       VoiceStep()
    case .done:        DoneStep()
    }
  }

  private var footer: some View {
    HStack {
      if step != .welcome {
        Button("Zurück") { step = step.previous }
      }
      Spacer()
      if step == .done {
        Button("Fertig") { onClose() }
          .keyboardShortcut(.defaultAction)
      } else {
        Button("Weiter") { step = step.next }
          .keyboardShortcut(.defaultAction)
          .disabled(step == .apiKey && !hasKey)
      }
    }
  }
}
```

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Tide/Onboarding/OnboardingView.swift Tide/Onboarding/Steps/OnboardingSteps.swift
git commit -m "feat(onboarding): wizard container + step views

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `MenubarController.openOnboarding()` + observer

**Files:** `Tide/Menubar/MenubarController.swift`

- [ ] **Step 1: Add the onboarding window property + opener + observer**

Read `Tide/Menubar/MenubarController.swift` first. Add a stored property next to `settingsWindow`:

```swift
  private var onboardingWindow: NSWindow?
```

In `init(...)`, after the existing setup (e.g. at the end of init), register the observer:

```swift
    NotificationCenter.default.addObserver(
      forName: .tideOpenOnboarding, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.openOnboarding() }
    }
```

Add the opener method (mirror `openSettings`):

```swift
  /// Open (or focus) the first-run onboarding wizard.
  func openOnboarding() {
    if let existing = onboardingWindow {
      existing.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Tide — Einrichtung"
    window.isReleasedWhenClosed = false
    let view = OnboardingView(onClose: { [weak window] in window?.close() })
    window.contentViewController = NSHostingController(rootView: view)
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    onboardingWindow = window
  }
```

(If `init` isn't `@MainActor`-isolated in a way that allows `assumeIsolated`, the class is already `@MainActor` — the observer closure hops to `.main` queue; `MainActor.assumeIsolated` is the correct bridge. If the compiler rejects it, use `Task { @MainActor in self?.openOnboarding() }` instead.)

- [ ] **Step 2: Build**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Tide/Menubar/MenubarController.swift
git commit -m "feat(onboarding): MenubarController.openOnboarding + notification observer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `AppEntry` auto-trigger on first launch

**Files:** `Tide/AppEntry.swift`

- [ ] **Step 1: Trigger when no API key**

Read `Tide/AppEntry.swift`. Inside `applicationDidFinishLaunching`'s `Task { @MainActor in … }`, after the `MenubarController` (`controller`) is created and assigned, add:

```swift
        // First-run onboarding: no Anthropic key yet → guide setup.
        let hasKey = KeychainHelper.get(key: "anthropic.api_key")?.isEmpty == false
        if !hasKey {
          controller.openOnboarding()
        }
```

(Place it after `self.menubarController = controller` so the controller exists. `KeychainHelper` is already imported via `Core`.)

- [ ] **Step 2: Build**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Tide/AppEntry.swift
git commit -m "feat(onboarding): auto-open wizard on first launch (no API key)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Settings re-run button

**Files:** `Tide/Settings/ApiKeySection.swift`

- [ ] **Step 1: Add the button**

Read `Tide/Settings/ApiKeySection.swift`. Add a second `Section` (or append to the existing one's footer) with a button that posts the notification. Place it after the existing API-key `Section`, before the `Form`/`body` closes:

```swift
      Section {
        Button("Onboarding erneut starten") {
          NotificationCenter.default.post(name: .tideOpenOnboarding, object: nil)
        }
      } footer: {
        Text("Öffnet den Einrichtungs-Assistenten (API-Key, Berechtigungen, "
          + "Hotkeys, Stimme) erneut.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
```

(Match the surrounding `Form { … }` structure — if the body is `Form { Section { … } }`, add this as a sibling `Section` inside the same `Form`.)

- [ ] **Step 2: Build**

Run: `xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manual smoke test**

Quit any running Tide. Build + run (Cmd+R). To exercise first-run: temporarily reset the key (Settings → Allgemein → API → "Zurücksetzen") and relaunch → wizard appears. Walk all 6 steps; permission rows update live; "Weiter" is blocked on the API-Key step until a key is saved. Re-run via the new Settings button. Re-add your key afterward.

- [ ] **Step 4: Commit**

```bash
git add Tide/Settings/ApiKeySection.swift
git commit -m "feat(settings): re-run onboarding button

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Docs

**Files:** `README.md`, `CHANGELOG.md`

- [ ] **Step 1: CHANGELOG** — under `## [Unreleased]` → `### Added`:

```markdown
- **Onboarding-Wizard** — beim ersten Start (kein Anthropic-Key) führt ein
  gestufter Assistent durch Einrichtung: Welcome → API-Key → Berechtigungen
  (Mic/Spracherkennung/Accessibility) → Hotkeys → Sprache & Stimme → Fertig.
  Jederzeit erneut startbar über Einstellungen → Allgemein → API.
```

- [ ] **Step 2: README roadmap** — change the Welle 9 row from 🔜 to ✅ (Onboarding-Flow done; Crash-Reporting bleibt offen — split the row if needed):

```markdown
| 9 | Onboarding-Flow | ✅ |
| 10 | Crash-Reporting | 🔜 |
```

(Adjust to the actual current table — Distribution stays 🔜.)

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: onboarding wizard changelog + roadmap

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** notification+step enum (T1), permissions service (T2), wizard container+steps (T3), window opener+observer (T4), auto-trigger (T5), re-run button (T6), docs (T7). All covered.
- **Type consistency:** `OnboardingStep` (6 cases, `next/previous/index/count/title`), `PermissionStatus`/`PermissionsService.map`, `.tideOpenOnboarding`, `OnboardingView(onClose:)`, `MenubarController.openOnboarding()`. Consistent across tasks.
- **DI:** re-run uses `NotificationCenter` (Settings view → MenubarController) — no singleton, matches the decoupling used elsewhere.
- **Permissions:** only `.apiKey` gates "Weiter"; permission steps never block (features degrade until granted). AX is out-of-process → polled.
- **Quality gate:** after Task 3, controller runs a `swiftui-pro` review on the wizard views.
- **Test host:** XCTest-guard on main keeps app-target tests runnable; still quit dev Tide before full `xcodebuild test`.
```
