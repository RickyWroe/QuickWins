import AppKit

/// Borderless utility panel that can take keyboard focus without turning QuickWins into a
/// foreground app.
///
/// `NSPanel` rather than `NSWindow` so it never appears in the window cycle or the Dock, and
/// `canBecomeKey` is overridden because a borderless window refuses key status by default —
/// without it the panel could be shown but not typed into.
final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    /// The mini HUD is a glance, not a place to type. Refusing key status keeps the user's
    /// keyboard focus in whatever app they were already working in.
    private let acceptsKey: Bool

    init(contentRect: NSRect, acceptsKey: Bool = true) {
        self.acceptsKey = acceptsKey
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        // Visible on every Space and alongside a full-screen app, without pulling the user out
        // of the space they are in.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { acceptsKey }
    /// Staying non-main keeps the previously active app's menu bar in place.
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
