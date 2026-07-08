import SwiftUI
import Core

/// First-run onboarding wizard. Stepped flow; `onClose` is invoked by the
/// final "Fertig" button (and is wired by MenubarController to close the
/// hosting window).
struct OnboardingView: View {
  let settings: AppSettings
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
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Schritt \(step.index + 1) von \(OnboardingStep.count)")
    }
  }

  @ViewBuilder
  private var content: some View {
    switch step {
    case .welcome:     WelcomeStep()
    case .apiKey:      ApiKeyStep(hasKey: $hasKey)
    case .permissions: PermissionsStep()
    case .hotkey:      HotkeyStep()
    case .voice:       VoiceStep(settings: settings)
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
