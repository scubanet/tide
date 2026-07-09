import AppKit

/// Full-fidelity snapshot of the general pasteboard. Tide briefly
/// hijacks the clipboard (selection-read via ⌘C, injection via ⌘V);
/// restoring only the plain-text representation would silently destroy
/// images, file URLs, RTF or multi-item content the user had copied —
/// so we capture every item with all of its types.
struct PasteboardSnapshot {
  private let items: [[NSPasteboard.PasteboardType: Data]]

  @MainActor
  init(_ pasteboard: NSPasteboard) {
    items = (pasteboard.pasteboardItems ?? []).map { item in
      var byType: [NSPasteboard.PasteboardType: Data] = [:]
      for type in item.types {
        if let data = item.data(forType: type) {
          byType[type] = data
        }
      }
      return byType
    }
  }

  /// Replace the pasteboard's current content with the snapshot.
  /// An originally-empty clipboard restores to empty.
  @MainActor
  func restore(to pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    guard !items.isEmpty else { return }
    let restored = items.map { byType -> NSPasteboardItem in
      let item = NSPasteboardItem()
      for (type, data) in byType {
        item.setData(data, forType: type)
      }
      return item
    }
    pasteboard.writeObjects(restored)
  }
}
