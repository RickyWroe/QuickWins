import AppKit
import QuickWinsCore
import SwiftUI

/// Shows and hides the compact cursor HUD.
///
/// Unlike the full panel this never takes key focus and never activates the app, so pressing the
/// shortcut mid-sentence does not interrupt typing. It closes itself after a few seconds, which
/// is what makes it a glance rather than another window to manage.
@MainActor
final class MiniHUDController {
    private let model: AppModel
    private let logger: DiagnosticLogging
    private let openPanel: () -> Void

    private var panel: FloatingPanel?
    private var autoHideTask: Task<Void, Never>?

    init(model: AppModel, logger: DiagnosticLogging, openPanel: @escaping () -> Void) {
        self.model = model
        self.logger = logger
        self.openPanel = openPanel

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        autoHideTask?.cancel()
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = ensurePanel()
        position(panel)
        // `orderFrontRegardless` rather than `makeKeyAndOrderFront`: the HUD appears without
        // pulling activation away from the app the user is in.
        panel.orderFrontRegardless()
        model.hudDidAppear()
        scheduleAutoHide()
    }

    func hide() {
        autoHideTask?.cancel()
        autoHideTask = nil
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        model.hudDidDisappear()
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        let seconds = model.settings.miniHUDAutoHideSeconds
        guard seconds > 0 else { return }
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func ensurePanel() -> FloatingPanel {
        if let panel { return panel }

        let rootView = MiniHUDView(model: model) { [weak self] in
            guard let self else { return }
            self.hide()
            self.openPanel()
        }
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 110, height: 30),
            acceptsKey: false
        )
        panel.contentViewController = hosting
        panel.onCancel = { [weak self] in self?.hide() }

        self.panel = panel
        return panel
    }

    private func position(_ panel: FloatingPanel) {
        panel.layoutIfNeeded()
        let size = CGSize(width: max(panel.frame.width, 80), height: max(panel.frame.height, 24))

        let cursor = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard let index = ScreenPositioning.screenIndex(containing: cursor, screens: screens.map(\.frame)) else {
            return
        }

        // The same placement rules as the full panel, so both surfaces appear in a consistent
        // spot relative to the pointer.
        let placement = ScreenPositioning.place(
            cursor: cursor,
            panelSize: size,
            visibleFrame: screens[index].visibleFrame
        )
        panel.setFrameOrigin(placement.origin)
    }

    @objc private func screenParametersChanged() {
        guard let panel, panel.isVisible else { return }
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        if let origin = ScreenPositioning.reposition(currentFrame: panel.frame, visibleFrames: visibleFrames) {
            panel.setFrameOrigin(origin)
        }
    }
}
