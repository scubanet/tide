import SwiftUI
import AppKit
import Core
import Hotkeys
import KeyboardShortcuts
import LLM
import TideSpeech

@main
struct TideApp: App {
  @NSApplicationDelegateAdaptor(TideAppDelegate.self) var delegate

  var body: some Scene {
    Settings { EmptyView() }
  }
}

final class TideAppDelegate: NSObject, NSApplicationDelegate {
  @MainActor private var menubarController: MenubarController?
  @MainActor private var conversationStore: ConversationStore?
  @MainActor private var pushToTalk: PushToTalkHandler?
  @MainActor private var dictationCoordinator: DictationCoordinator?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Single-instance enforcement: if another Tide is already running
    // (e.g. a leftover Xcode-built one while the user double-clicks the
    // shipped /Applications copy, or vice versa) we hand control back
    // to it and terminate this one. Two instances would otherwise both
    // register the same global push-to-talk hotkey, both stick a status
    // item in the menubar, and fight over the microphone.
    if let bundleID = Bundle.main.bundleIdentifier {
      let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0 != NSRunningApplication.current }
      if let existing = others.first {
        existing.activate(options: [])
        NSApp.terminate(nil)
        return
      }
    }

    Task { @MainActor in
      do {
        let store = try ConversationStore()
        self.conversationStore = store

        // Build settings + LLM provider once and share them across all
        // collaborators that need them. Welle 4 adds the dictation
        // coordinator, which needs the same configuration the
        // MenubarController's ChatViewModel uses — keep them on a
        // single instance so user-tweaks in Settings propagate to both
        // flows without a restart.
        let settings = AppSettings()

        // WhisperKit local transcription: build the one shared transcriber
        // and publish it via the holder so the recognizer factory + the
        // Local settings tab can reach it. Prewarm the model in the
        // background if the user already runs Local — avoids a cold-start
        // spike on the first dictation. No CoreML cost when Local is off.
        let localStore = WhisperModelStore()
        let transcriber = WhisperKitTranscriber(store: localStore)
        LocalTranscriberHolder.shared.transcriber = transcriber
        if settings.speechRecognizer == SpeechRecognizerChoice.whisperKit.rawValue,
           localStore.isInstalled(settings.localModelName) {
          let modelName = settings.localModelName
          Task.detached { try? await transcriber.prewarm(modelName: modelName) }
        }

        let apiKey = KeychainHelper.get(key: "anthropic.api_key") ?? ""
        let provider = AnthropicProvider(apiKey: apiKey)

        let controller = MenubarController(
          conversationStore: store,
          settings: settings,
          provider: provider
        )
        self.menubarController = controller
        self.pushToTalk = PushToTalkHandler(
          onPress: { [weak controller] in
            guard let controller else { return }
            // Capture selection BEFORE bringing Tide to the front —
            // otherwise the prior app loses focus and AX can't read its
            // selection any more.
            controller.capturePendingSelection()
            controller.openPanel()
            Task { @MainActor in
              await controller.chatViewModel.startRecording()
            }
          },
          onRelease: { [weak controller] in
            guard let controller else { return }
            Task { @MainActor in
              await controller.chatViewModel.stopRecording()
            }
          }
        )

        // Welle 4 — standalone dictation. Two new hotkeys, opt-in
        // (no default binding). On press we start a background
        // recording that bypasses the Tide panel entirely; on
        // release the transcript is logged (Phase B) and later
        // injected into the frontmost app's cursor (Phase D).
        let dictation = DictationCoordinator(
          settings: settings,
          provider: provider
        )
        self.dictationCoordinator = dictation
        // Phase C: pair the dictation coordinator with the menubar's
        // existing status item so it can tint the icon red and show a
        // floating pill while a session is in flight. The indicator
        // never steals focus — the pill is a non-activating panel and
        // we only mutate the status item's image, not its window state.
        let indicator = DictationIndicator(
          statusItem: controller.menubarStatusItem,
          settings: settings
        )
        dictation.attachIndicator(indicator)
        KeyboardShortcuts.onKeyDown(for: .dictateRaw) {
          Task { @MainActor in await dictation.start(mode: .raw) }
        }
        KeyboardShortcuts.onKeyUp(for: .dictateRaw) {
          Task { @MainActor in await dictation.stop() }
        }
        KeyboardShortcuts.onKeyDown(for: .dictatePolished) {
          Task { @MainActor in await dictation.start(mode: .polished) }
        }
        KeyboardShortcuts.onKeyUp(for: .dictatePolished) {
          Task { @MainActor in await dictation.stop() }
        }
      } catch {
        NSLog("Tide: failed to init store: \(error)")
      }
    }
  }
}
