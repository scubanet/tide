import Foundation

/// A snapshot of text that was selected in another app at the moment the
/// user invoked Tide. Carries enough provenance to render a clear
/// "Selection from <App>" badge in the panel.
public struct SelectedText: Sendable, Codable, Equatable {
  public let text: String
  public let sourceAppBundleID: String
  public let sourceAppName: String

  public init(text: String, sourceAppBundleID: String, sourceAppName: String) {
    self.text = text
    self.sourceAppBundleID = sourceAppBundleID
    self.sourceAppName = sourceAppName
  }
}
