import SwiftUI
import Core

/// Settings tab for the custom vocabulary (Tide custom-vocabulary wave).
///
/// Domain terms entered here bias the Apple speech recognizer
/// (`contextualStrings`) and are injected into the polished-dictation
/// system prompt so Claude spells jargon (PADI, SeaExplorers, …)
/// correctly. The list is mirrored into local `@State` and written back
/// to `AppSettings.customVocabulary` on every change — same pattern as
/// `DictationSection`'s prompt mirror.
struct VocabularySection: View {
  @State private var settings = AppSettings()
  @State private var terms: [String] = []
  @State private var newTerm: String = ""

  /// Above this count we surface a soft warning — Apple recommends fewer
  /// than 100 contextual strings, and very long lists can degrade
  /// recognition. Not a hard cap.
  private static let softLimit = 50

  var body: some View {
    Form {
      Section {
        Text("Begriffe (Namen, Fachjargon), die Tide korrekt erkennen und "
          + "schreiben soll. Beeinflusst die Apple-Erkennung und den "
          + "Polish-Schritt.")
          .font(.caption)
          .foregroundStyle(.secondary)

        if terms.isEmpty {
          Text("Noch keine Begriffe.")
            .font(.caption)
            .foregroundStyle(.tertiary)
        } else {
          List {
            ForEach(terms, id: \.self) { term in
              Text(term)
            }
            .onDelete { offsets in
              terms.remove(atOffsets: offsets)
              settings.customVocabulary = terms
            }
          }
          .frame(minHeight: 120)
        }

        HStack {
          TextField("Begriff hinzufügen", text: $newTerm)
            .textFieldStyle(.roundedBorder)
            .onSubmit(addTerm)
          Button("Hinzufügen", action: addTerm)
            .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        if terms.count > Self.softLimit {
          Text("Apple empfiehlt unter 100 Begriffe; sehr lange Listen "
            + "können die Erkennung verschlechtern.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } header: { Text("Vokabular") }
    }
    .formStyle(.grouped)
    .task {
      terms = settings.customVocabulary
    }
  }

  private func addTerm() {
    let trimmed = newTerm.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !terms.contains(trimmed) else { return }
    terms.append(trimmed)
    settings.customVocabulary = terms
    newTerm = ""
  }
}
