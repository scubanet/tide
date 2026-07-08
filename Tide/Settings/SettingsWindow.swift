import SwiftUI
import Core

/// Settings window: a grouped sidebar (`NavigationSplitView`) replacing the
/// old `TabView`, which overflowed into a "» Navigation Tab Bar" dropdown
/// once the pane count passed what fit at 520 pt wide. The sidebar scales to
/// any number of panes; sections come from `SettingsTab.groups`.
struct SettingsWindow: View {
  /// The one shared settings instance (from the app delegate). Passed to the
  /// panes that edit settings so their writes reach the running app live.
  let settings: AppSettings
  @State private var selection: SettingsTab = .api

  var body: some View {
    NavigationSplitView {
      List(selection: $selection) {
        ForEach(SettingsTab.groups, id: \.title) { group in
          Section(group.title) {
            ForEach(group.tabs) { tab in
              Label(tab.label, systemImage: tab.systemImage)
                .tag(tab)
            }
          }
        }
      }
      .listStyle(.sidebar)
      .navigationSplitViewColumnWidth(min: 170, ideal: 185, max: 220)
    } detail: {
      detail(for: selection)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 620, idealWidth: 640, minHeight: 440, idealHeight: 470)
  }

  @ViewBuilder
  private func detail(for tab: SettingsTab) -> some View {
    switch tab {
    case .api:        ApiKeySection()
    case .model:      ModelSection(settings: settings)
    case .voice:      VoiceSection(settings: settings)
    case .vocabulary: VocabularySection(settings: settings)
    case .local:      LocalModelSection(settings: settings)
    case .hotkey:     HotkeySection()
    case .dictation:  DictationSection(settings: settings)
    case .actions:    QuickActionsEditor()
    }
  }
}
