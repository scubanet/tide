import SwiftUI
import Core
import TideSpeech

/// Settings tab for the local WhisperKit models: pick a model, download it
/// (with progress), see install state. Fully offline & free after download.
struct LocalModelSection: View {
  @State private var settings = AppSettings()
  @State private var store = WhisperModelStore()
  @State private var catalog: [WhisperModelInfo] = []
  @State private var selectedModel: String = ""
  @State private var downloading = false
  @State private var downloadProgress: Double = 0
  @State private var downloadError: String?

  var body: some View {
    Form {
      Section {
        Text("Vollständig offline & gratis nach dem Download. Wähle danach "
          + "‚Lokal (WhisperKit, offline)' als Recognizer unter Stimme.")
          .font(.caption)
          .foregroundStyle(.secondary)

        Picker("Modell:", selection: $selectedModel) {
          ForEach(catalog) { model in
            Text("\(model.displayName) · \(model.approxSizeMB) MB"
              + (model.isInstalled ? " ✓" : ""))
              .tag(model.id)
          }
        }
        .onChange(of: selectedModel) { _, newValue in
          settings.localModelName = newValue
          prewarmIfInstalled(newValue)
        }

        if let selected = catalog.first(where: { $0.id == selectedModel }) {
          if selected.isInstalled {
            Label("Installiert", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
              .font(.caption)
          } else if downloading {
            ProgressView(value: downloadProgress) {
              Text("Lädt … \(Int(downloadProgress * 100)) %").font(.caption)
            }
          } else {
            Button("Modell laden (\(selected.approxSizeMB) MB)") {
              download(selected.id)
            }
          }
        }

        if let downloadError {
          Text(downloadError).foregroundStyle(.red).font(.caption)
        }
      } header: { Text("Lokales Modell (WhisperKit)") }
    }
    .formStyle(.grouped)
    .task {
      catalog = store.catalog()
      selectedModel = settings.localModelName
      prewarmIfInstalled(selectedModel)
    }
  }

  private func refreshCatalog() {
    catalog = store.catalog()
  }

  private func prewarmIfInstalled(_ id: String) {
    guard store.isInstalled(id),
          let transcriber = LocalTranscriberHolder.shared.transcriber
            as? WhisperKitTranscriber else { return }
    Task.detached { try? await transcriber.prewarm(modelName: id) }
  }

  private func download(_ id: String) {
    downloading = true
    downloadProgress = 0
    downloadError = nil
    let store = self.store
    Task {
      do {
        try await store.download(id: id) { p in
          Task { @MainActor in downloadProgress = p }
        }
        await MainActor.run {
          downloading = false
          refreshCatalog()
          prewarmIfInstalled(id)
        }
      } catch {
        await MainActor.run {
          downloading = false
          downloadError = "Download fehlgeschlagen: \(error.localizedDescription)"
        }
      }
    }
  }
}
