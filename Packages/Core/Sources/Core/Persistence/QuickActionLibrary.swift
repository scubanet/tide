import Foundation

/// Provides the user's quick-action set: 6 built-in actions plus any
/// custom ones the user has added. Custom actions are persisted as
/// JSON in `UserDefaults`. Order in `all()`: built-ins first, then
/// custom actions in insertion order.
@MainActor
public final class QuickActionLibrary {
  private let defaults: UserDefaults
  private let key = "tide.customQuickActions"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// All actions, built-ins first.
  public func all() -> [QuickAction] {
    builtIns + custom()
  }

  /// Just the custom actions (no built-ins).
  public func custom() -> [QuickAction] {
    guard let data = defaults.data(forKey: key),
          let actions = try? JSONDecoder().decode([QuickAction].self, from: data)
    else { return [] }
    return actions
  }

  /// Append a new custom action.
  public func add(_ action: QuickAction) {
    var current = custom()
    current.append(action)
    save(current)
  }

  /// Replace an existing custom action (matched by id). No-op for built-ins.
  public func update(_ action: QuickAction) {
    guard !action.isBuiltIn else { return }
    var current = custom()
    if let idx = current.firstIndex(where: { $0.id == action.id }) {
      current[idx] = action
      save(current)
    }
  }

  /// Delete a custom action by id. No-op for built-in ids.
  public func delete(id: UUID) {
    let current = custom().filter { $0.id != id }
    save(current)
  }

  // MARK: - Built-ins

  private var builtIns: [QuickAction] {
    [
      QuickAction(slug: "summarize", label: "Zusammenfassen",
        systemPrompt: "Fasse den folgenden Text in 2–3 Sätzen zusammen.", isBuiltIn: true),
      QuickAction(slug: "translate", label: "Übersetzen",
        systemPrompt: "Übersetze den folgenden Text ins Englische. Nur die Übersetzung ausgeben.", isBuiltIn: true),
      QuickAction(slug: "improve", label: "Verbessern",
        systemPrompt: "Verbessere Stil, Grammatik und Klarheit des folgenden Textes ohne den Sinn zu ändern.", isBuiltIn: true),
      QuickAction(slug: "reply", label: "Antwort entwerfen",
        systemPrompt: "Entwirf eine knappe, höfliche Antwort auf die folgende Nachricht.", isBuiltIn: true),
      QuickAction(slug: "explain", label: "Erklären",
        systemPrompt: "Erkläre das folgende Konzept einfach und mit Beispielen.", isBuiltIn: true),
      QuickAction(slug: "shorter", label: "Kürzer",
        systemPrompt: "Kürze den folgenden Text um etwa die Hälfte ohne wichtige Punkte zu verlieren.", isBuiltIn: true),
    ]
  }

  // MARK: - Persistence

  private func save(_ list: [QuickAction]) {
    if let data = try? JSONEncoder().encode(list) {
      defaults.set(data, forKey: key)
    }
  }
}
