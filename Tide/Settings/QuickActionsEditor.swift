import SwiftUI
import Core

struct QuickActionsEditor: View {
  @State private var library = QuickActionLibrary()
  @State private var customActions: [QuickAction] = []

  // New-action form state
  @State private var newLabel: String = ""
  @State private var newPrompt: String = ""

  var body: some View {
    Form {
      Section {
        ForEach(library.all().filter { $0.isBuiltIn }) { action in
          HStack {
            Text(action.label)
              .font(.system(size: 13))
            Spacer()
            Text(action.systemPrompt)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.tail)
              .frame(maxWidth: 280, alignment: .trailing)
          }
        }
      } header: {
        Text("Standard-Actions (nicht editierbar)")
      }

      Section {
        if customActions.isEmpty {
          Text("Noch keine eigenen Actions.")
            .font(.callout)
            .foregroundStyle(.secondary)
        } else {
          ForEach(customActions) { action in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(action.label)
                  .font(.system(size: 13, weight: .medium))
                Text(action.systemPrompt)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
              Spacer()
              Button(role: .destructive) {
                library.delete(id: action.id)
                refresh()
              } label: {
                Image(systemName: "trash")
              }
              .buttonStyle(.plain)
            }
          }
        }
      } header: {
        Text("Deine eigenen Actions")
      }

      Section {
        TextField("Label (z.B. „Reimen“)", text: $newLabel)
          .textFieldStyle(.roundedBorder)
        TextField("System-Prompt", text: $newPrompt, axis: .vertical)
          .lineLimit(2...4)
          .textFieldStyle(.roundedBorder)
        Button("Action hinzufügen") {
          let slug = newLabel
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
          let action = QuickAction(
            slug: slug.isEmpty ? UUID().uuidString : slug,
            label: newLabel,
            systemPrompt: newPrompt,
            isBuiltIn: false
          )
          library.add(action)
          newLabel = ""
          newPrompt = ""
          refresh()
        }
        .disabled(newLabel.isEmpty || newPrompt.isEmpty)
      } header: {
        Text("Neue Action")
      }
    }
    .formStyle(.grouped)
    .onAppear { refresh() }
  }

  private func refresh() {
    customActions = library.custom()
  }
}
