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
      Divider()
      HStack(spacing: 8) {
        if viewModel.isRecording {
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
        } else {
          TextField("Frag was…", text: $viewModel.input, axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
              Task { await viewModel.send() }
            }
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
        Button {
          Task { await viewModel.send() }
        } label: {
          Image(systemName: "paperplane.fill")
        }
        .disabled(!viewModel.canSend)
      }
      .padding(10)
    }
  }
}
