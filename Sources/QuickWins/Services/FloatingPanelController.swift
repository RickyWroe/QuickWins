import AppKit
import QuickWinsCore
import SwiftUI

/// Owns the panel's lifecycle: where it appears, when it closes, and who gets focus afterwards.
@MainActor
final class FloatingPanelController {
    static let panelWidth: CGFloat = 340

    private let model: AppModel
    private let logger: DiagnosticLogging

    private var panel: FloatingPanel?
    private var hosting: NSHostingController<PanelRootView>?
    private var outsideClickMonitor: Any?
    /// The app to hand focus back to when the panel closes.
    private weak var previouslyActiveApp: NSRunningApplication?

    init(model: AppModel, logger: DiagnosticLogging) {
        self.model = model
        self.logger = logger

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - Presentation

    func toggle() {
        isVisible ? hide() : show()
    }

    /// Shows the panel, positioning it beside the pointer when the user has that enabled.
    func show(besideCursor: Bool? = nil) {
        let panel = ensurePanel()
        let useCursor = besideCursor ?? model.settings.openPanelBesideCursor

        if !panel.isVisible {
            previouslyActiveApp = NSWorkspace.shared.frontmostApplication
        }

        position(panel, besideCursor: useCursor)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitor()
        model.panelDidAppear()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        removeOutsideClickMonitor()
        panel.orderOut(nil)
        model.panelDidDisappear()

        // Hand focus back rather than leaving the user in a menu-bar app with no window.
        if let previouslyActiveApp, previouslyActiveApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previouslyActiveApp.activate()
        }
        self.previouslyActiveApp = nil
    }

    /// Brings the panel forward for an escalated alert, drawing attention without stealing typing.
    func surfaceForAlert() {
        show(besideCursor: model.settings.openPanelBesideCursor)
        panel?.orderFrontRegardless()
    }

    // MARK: - Construction

    private func ensurePanel() -> FloatingPanel {
        if let panel { return panel }

        let rootView = PanelRootView(model: model, dismiss: { [weak self] in self?.hide() })
        let hosting = NSHostingController(rootView: rootView)
        // Lets the SwiftUI content drive the window height as the task list grows.
        hosting.sizingOptions = [.preferredContentSize]

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 320)
        )
        panel.contentViewController = hosting
        panel.onCancel = { [weak self] in self?.hide() }

        self.panel = panel
        self.hosting = hosting
        return panel
    }

    // MARK: - Positioning

    private func position(_ panel: FloatingPanel, besideCursor: Bool) {
        // No `layoutIfNeeded()`: the hosting controller sizes the window from its content, so
        // forcing a window layout pass re-enters NSWindow's resize constraints and recurses
        // until the stack is exhausted. The height falls back to a sane minimum instead.
        let size = CGSize(width: Self.panelWidth, height: max(panel.frame.height, 120))

        guard besideCursor else {
            centerOnActiveScreen(panel, size: size)
            return
        }

        let cursor = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let frames = screens.map(\.frame)
        guard let index = ScreenPositioning.screenIndex(containing: cursor, screens: frames) else {
            centerOnActiveScreen(panel, size: size)
            return
        }

        let placement = ScreenPositioning.place(
            cursor: cursor,
            panelSize: size,
            visibleFrame: screens[index].visibleFrame
        )
        panel.setFrameOrigin(placement.origin)

        if placement.clamped {
            logger.info("panel", "Panel clamped to fit screen \(index).")
        }
    }

    private func centerOnActiveScreen(_ panel: FloatingPanel, size: CGSize) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let origin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        panel.setFrameOrigin(ScreenPositioning.clamp(origin: origin, size: size, into: visible))
    }

    @objc private func screenParametersChanged() {
        guard let panel, panel.isVisible else { return }
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        if let origin = ScreenPositioning.reposition(currentFrame: panel.frame, visibleFrames: visibleFrames) {
            logger.info("panel", "Display configuration changed; panel moved back on screen.")
            panel.setFrameOrigin(origin)
        }
    }

    // MARK: - Dismissal

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            // A click elsewhere dismisses the panel, unless a sheet is mid-edit; losing an
            // unsaved title to a stray click would be worse than an extra Escape press.
            guard !self.model.isEditingModally else { return }
            Task { @MainActor in self.hide() }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }
}
