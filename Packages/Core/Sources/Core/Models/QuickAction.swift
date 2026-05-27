import Foundation

/// A reusable prompt template the user can invoke from the panel's
/// pills row. Built-in actions ship with the app and aren't editable;
/// user-defined actions are added via the Settings window.
public struct QuickAction: Sendable, Codable, Identifiable, Equatable, Hashable {
  public let id: UUID
  public var slug: String
  public var label: String
  public var systemPrompt: String
  public var isBuiltIn: Bool

  public init(
    id: UUID = UUID(),
    slug: String,
    label: String,
    systemPrompt: String,
    isBuiltIn: Bool
  ) {
    self.id = id
    self.slug = slug
    self.label = label
    self.systemPrompt = systemPrompt
    self.isBuiltIn = isBuiltIn
  }
}
