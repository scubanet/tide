import AppKit

/// Writes text back into the previous app's selection via `ClipboardPaste`.
public enum SelectionReplacer {
  /// Replaces the frontmost app's selection with `text`. Fire-and-forget:
  /// the async paste runs on the main actor; the result isn't awaited
  /// (replacement is best-effort and restores the clipboard either way).
  /// Caller must yield focus (e.g. `NSApp.hide`) first.
  @MainActor
  public static func replaceSelection(with newText: String) {
    Task { @MainActor in _ = await ClipboardPaste.paste(newText) }
  }
}
