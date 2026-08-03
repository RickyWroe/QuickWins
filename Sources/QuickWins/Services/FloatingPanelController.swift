import AppKit
import Combine
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
    private var contentChangeObserver: AnyCancellable?
    /// Re-entrancy guard around every frame change, as in the HUD controller.
    private var isAdjustingFrame = false
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

        syncContentSize()
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

        let rootView = PanelRootView(
            model: model,
            height: contentHeight,
            dismiss: { [weak self] in self?.hide() }
        )
        let hosting = NSHostingController(rootView: rootView)
        // The controller owns the window size; SwiftUI never proposes one. Letting the content
        // drive the window while that content holds a ScrollView is what crashed the app when a
        // task was added — the scroll view and the window resized each other without settling.
        hosting.sizingOptions = []

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 320)
        )
        panel.contentViewController = hosting
        panel.onCancel = { [weak self] in self?.hide() }

        self.panel = panel
        self.hosting = hosting

        // The panel's height depends on how many tasks there are, so it has to be recomputed
        // whenever the model changes. `objectWillChange` fires before the change lands, so the
        // recalculation is deferred by one turn of the run loop.
        contentChangeObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.syncContentSize() }
        }

        return panel
    }

    // MARK: - Sizing

    /// The panel's height, derived from what it is about to show rather than measured from it.
    private var contentHeight: CGFloat {
        var height = Theme.panelHeaderHeight + Theme.panelDividerHeight
        height += model.focusTask == nil ? Theme.panelEmptyFocusHeight : Theme.panelActiveCardHeight

        let sections = [model.overdue.isEmpty, model.upcoming.isEmpty, model.completed.isEmpty]
            .filter { !$0 }
            .count
        let rows = model.overdue.count + model.upcoming.count + model.completed.count
        if rows > 0 {
            let content = CGFloat(sections) * Theme.panelSectionHeaderHeight
                + CGFloat(rows) * Theme.panelRowHeight
                + Theme.panelListBottomPadding
            height += min(Theme.maximumListHeight, content)
        }

        height += Theme.panelQuickAddHeight
        return min(max(height, Theme.panelMinimumHeight), Theme.panelMaximumHeight)
    }

    /// Applies the computed height. The only place the panel window's size is set.
    private func syncContentSize() {
        guard let panel, let hosting, !isAdjustingFrame else { return }
        let target = CGSize(width: Theme.panelWidth, height: contentHeight)

        // The view is told the same height, so it never wants a different one.
        if hosting.rootView.height != target.height {
            hosting.rootView = PanelRootView(
                model: model,
                height: target.height,
                dismiss: { [weak self] in self?.hide() }
            )
        }

        guard abs(target.height - panel.frame.height) > 0.5
                || abs(target.width - panel.frame.width) > 0.5 else { return }

        isAdjustingFrame = true
        // Keep the top edge where it is as the panel grows downward.
        let top = panel.frame.maxY
        panel.setContentSize(target)
        panel.setFrameOrigin(CGPoint(x: panel.frame.origin.x, y: top - panel.frame.height))
        isAdjustingFrame = false
    }

    // MARK: - Positioning

    private func position(_ panel: FloatingPanel, besideCursor: Bool) {
        let size = CGSize(width: Theme.panelWidth, height: panel.frame.height)

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
