import SwiftUI
import Core

struct ChatContainer: View {
  @Bindable var viewModel: ChatViewModel

  var body: some View {
    VStack(spacing: 0) {
      if let selection = viewModel.pendingSelection {
        SelectionContextBadge(
          selection: selection,
          onDismiss: { viewModel.pendingSelection = nil }
        )
      }
      QuickActionsBar(
        actions: viewModel.availableActions,
        selectedSlug: $viewModel.selectedActionSlug
      )
      Divider()
      MessageList(messages: viewModel.messages)
      if let error = viewModel.lastError {
        errorBanner(error)
      }
      if let hint = viewModel.sttHint {
        Text(hint)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
      }
      Divider()
      inputBar
    }
  }

  private var inputBar: some View {
    HStack(spacing: 8) {
      if viewModel.isRecording {
        recordingIndicator
      } else {
        TextField("Frag was…", text: $viewModel.input, axis: .vertical)
          .lineLimit(1...4)
          .textFieldStyle(.roundedBorder)
          .disabled(viewModel.isStreaming)
          .onSubmit { viewModel.beginSend() }
      }
      Button {
        Task {
          if viewModel.isRecording {
            await viewModel.stopRecording()
          } else {
            await viewModel.startRecording()
          }
        }
      } label: {
        Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.fill")
          .foregroundStyle(viewModel.isRecording ? Color.red : Color.accentColor)
      }
      .accessibilityLabel(viewModel.isRecording ? "Aufnahme stoppen" : "Aufnahme starten")
      // While a response streams, the send button becomes a Stop button so
      // the user can cancel an over-long or wrong answer (keeps partial text).
      if viewModel.isStreaming {
        Button { viewModel.cancelStreaming() } label: {
          Image(systemName: "stop.circle.fill").foregroundStyle(.red)
        }
        .help("Antwort stoppen (⌘.)")
        .accessibilityLabel("Antwort stoppen")
      } else {
        Button {
          viewModel.beginSend()
        } label: {
          Image(systemName: "paperplane.fill")
        }
        .disabled(!viewModel.canSend)
        .accessibilityLabel("Senden")
      }
    }
    .padding(10)
  }

  private var recordingIndicator: some View {
    HStack(spacing: 6) {
      Image(systemName: "waveform")
        .foregroundStyle(Color.accentColor)
      Text(viewModel.liveTranscript.isEmpty ? "Höre zu…" : viewModel.liveTranscript)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color.accentColor.opacity(0.08))
    .clipShape(.rect(cornerRadius: 8))
  }

  @ViewBuilder
  private func errorBanner(_ error: ChatViewModel.ChatError) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(error.message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Spacer(minLength: 4)
      if case .unauthorized = error {
        Button("API-Key prüfen") {
          NotificationCenter.default.post(name: .tideOpenOnboarding, object: nil)
        }
        .controlSize(.small)
      } else if error.isRetryable {
        Button("Wiederholen") { viewModel.beginRetry() }
          .controlSize(.small)
      }
      Button { viewModel.lastError = nil } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Fehler ausblenden")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color.orange.opacity(0.10))
  }
}
