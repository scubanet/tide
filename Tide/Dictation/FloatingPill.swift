import AppKit
import Observation
import SwiftUI

/// View-state object bridging `FloatingPill.update(partial:)` calls into
/// the SwiftUI hierarchy. Marked `@Observable` so SwiftUI re-renders
/// `PillContents` whenever `partial` changes — without us needing to
/// rebuild the hosting controller or replace the root view.
@MainActor
@Observable
final class PillViewState {
  var partial: String = ""
  /// When true, the pill renders a transient hint (e.g. "Nichts erkannt")
  /// rather than live-recording state: grey dot instead of red, and the
  /// text is shown verbatim with no "Aufnahme…" placeholder fallback.
  var isHint: Bool = false
}

/// The small "● Aufnahme…" / live-partial overlay shown in the corner of
/// the screen while a dictation session is in flight.
///
/// Layout: a red dot + a single-line truncated `Text`. The truncation
/// keeps the pill width stable (32 chars max, ellipsis-prefixed) so long
/// partials don't cause the window to grow horizontally.
struct PillContents: View {
  @Bindable var state: PillViewState

  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(state.isHint ? Color.secondary : Color.red)
        .frame(width: 8, height: 8)
      Text(displayText)
        .font(.system(size: 12))
        .foregroundStyle(.primary)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
  }

  private var displayText: String {
    if state.isHint { return state.partial }
    return state.partial.isEmpty ? "Aufnahme…" : truncated(state.partial)
  }

  private func truncated(_ s: String) -> String {
    s.count > 32 ? "…" + String(s.suffix(31)) : s
  }
}

/// A borderless, non-activating floating overlay that displays the live
/// dictation transcript without stealing focus from the user's source
/// app.
///
/// Key properties:
/// - `nonactivatingPanel` + `canBecomeKey == false` so clicking the pill
///   (or simply having it appear) never pulls keyboard focus away from
///   wherever the user is typing.
/// - `.floating` window level so it sits above ordinary app windows.
/// - Transparent background, rounded corners, drop shadow — all the
///   visual chrome lives in the SwiftUI `PillContents` view via
///   `.regularMaterial`.
///
/// Positioning is computed against the screen that owns the menubar
/// (`NSScreen.screens.first ?? .main`), using `visibleFrame` so the pill
/// respects notch / Dock insets, with a 16-pt margin from the edges.
@MainActor
final class FloatingPill: NSPanel {
  private static let pillSize = NSSize(width: 220, height: 36)

  /// AppSettings string: "topRight" | "topCenter" | "bottomRight".
  /// Re-read on each `show(...)` so that user changes in Settings take
  /// effect on the next dictation without an app restart.
  private var position: String
  private let viewState = PillViewState()

  /// Monotonic token bumped on every `show`/`flash`/`hide`. The delayed
  /// cleanup bodies (fade-out order-out, hint reset) capture the value at
  /// scheduling time and no-op if a newer call has since superseded them —
  /// so a flash's fade can never order-out or clobber a freshly-shown
  /// recording pill.
  private var generation = 0
  /// The currently-pending delayed cleanup body, cancelled whenever a new
  /// `show`/`flash`/`hide` arrives.
  private var cleanupTask: Task<Void, Never>?

  init(position: String) {
    self.position = position
    super.init(
      contentRect: NSRect(origin: .zero, size: Self.pillSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    self.level = .floating
    self.backgroundColor = .clear
    self.isOpaque = false
    self.hasShadow = true
    self.isMovableByWindowBackground = false
    self.hidesOnDeactivate = false
    // Prevent the pill from showing up in Mission Control / Cmd-Tab
    // and keep it across Spaces while it's visible.
    self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    let host = NSHostingController(rootView: PillContents(state: viewState))
    self.contentViewController = host
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  /// Update the position string from settings. Called by
  /// `DictationIndicator.show()` so the latest user choice takes effect
  /// on the next session.
  func updatePosition(_ position: String) {
    self.position = position
  }

  /// Make the pill visible at the configured corner of the menubar
  /// screen. Resets `alphaValue` to 1.0 so a previously-faded pill is
  /// fully opaque again.
  func show(initialText: String) {
    // A freshly-shown pill must invalidate any pending fade/reset from a
    // prior flash/hide so they can't order it out or clobber its state.
    generation += 1
    cleanupTask?.cancel()
    viewState.isHint = false
    viewState.partial = initialText
    repositionForCurrentScreen()
    self.alphaValue = 1.0
    // `orderFrontRegardless` so the pill appears even when the app is
    // not active — which is the entire point: the user is dictating
    // *into another app*, Tide must not become frontmost.
    self.orderFrontRegardless()
  }

  /// Show a transient hint (e.g. "Nichts erkannt") at the configured
  /// corner, then fade out after `duration`. Used when a dictation
  /// session produced no usable transcript. Re-positions and re-shows
  /// the pill even if it was already faded out by a prior `hide()`.
  func flash(_ message: String, duration: TimeInterval = 1.2) {
    generation += 1
    let gen = generation
    cleanupTask?.cancel()
    viewState.isHint = true
    viewState.partial = message
    repositionForCurrentScreen()
    self.alphaValue = 1.0
    self.orderFrontRegardless()
    cleanupTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
      // A newer show/flash/hide superseded this flash — leave the new
      // session's pill alone. Checked before every side effect below so a
      // late-arriving session can't be clobbered mid-sequence.
      guard let self, self.generation == gen else { return }
      // Inline the fade (rather than calling hide(), which would bump the
      // generation and cancel this very task) so the whole flash sequence
      // stays one coherent token-guarded body.
      self.fadeOutAnimation()
      try? await Task.sleep(nanoseconds: 160_000_000)
      guard self.generation == gen else { return }
      self.orderOut(nil)
      // Reset hint state after the fade so the next live session starts
      // with the red recording dot.
      try? await Task.sleep(nanoseconds: 200_000_000)
      guard self.generation == gen else { return }
      self.viewState.isHint = false
    }
  }

  /// Live partial transcript update. SwiftUI re-renders via `@Observable`.
  func update(partial: String) {
    viewState.partial = partial
  }

  /// Fade out over 150ms, then `orderOut(nil)`. Safe to call when not
  /// visible — `orderOut` on an already-hidden panel is a no-op.
  ///
  /// Uses a detached `Task` for the post-animation order-out rather than
  /// `runAnimationGroup`'s completionHandler so the cleanup stays on the
  /// MainActor without bouncing through a `@Sendable` callback (Swift 6
  /// strict-concurrency friendly).
  func hide() {
    generation += 1
    let gen = generation
    cleanupTask?.cancel()
    fadeOutAnimation()
    cleanupTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 160_000_000)
      guard let self, self.generation == gen else { return }
      self.orderOut(nil)
    }
  }

  /// Animate the pill's alpha to zero over 150ms. Factored out so both
  /// `hide()` (sync context) and `flash`'s cleanup task (async context)
  /// invoke the synchronous `runAnimationGroup` overload unambiguously.
  private func fadeOutAnimation() {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      self.animator().alphaValue = 0.0
    }
  }

  /// Compute the pill's origin against the menubar screen's
  /// `visibleFrame`. `NSScreen.screens.first` is the screen that owns
  /// the menubar; falling back to `.main` covers the (rare) case where
  /// `screens` is empty during early app startup.
  private func repositionForCurrentScreen() {
    let screen = NSScreen.screens.first ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return }
    let size = Self.pillSize
    let margin: CGFloat = 16
    let origin: NSPoint
    switch position {
    case "topCenter":
      origin = NSPoint(
        x: visible.midX - size.width / 2,
        y: visible.maxY - size.height - margin
      )
    case "bottomRight":
      origin = NSPoint(
        x: visible.maxX - size.width - margin,
        y: visible.minY + margin
      )
    default: // "topRight"
      origin = NSPoint(
        x: visible.maxX - size.width - margin,
        y: visible.maxY - size.height - margin
      )
    }
    self.setFrame(NSRect(origin: origin, size: size), display: true)
  }
}
