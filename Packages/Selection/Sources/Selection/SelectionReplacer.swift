import AppKit

/// Writes text back into the previous app's selection by swapping the
/// pasteboard, simulating ⌘V, and restoring the original clipboard.
///
/// The mechanical paste sequence (pasteboard swap + synthetic ⌘V +
/// restore) lives in `ClipboardPaste`; this enum keeps the
/// selection-replacement-shaped public API the rest of the app uses.
public enum SelectionReplacer {
  /// Replaces the current frontmost app's selection with `text`, then
  /// restores the original clipboard contents after a short delay.
  /// Caller is responsible for first calling `NSApp.hide(nil)` or
  /// otherwise yielding focus before invoking this.
  public static func replaceSelection(with newText: String) {
    ClipboardPaste.paste(newText)
  }
}
