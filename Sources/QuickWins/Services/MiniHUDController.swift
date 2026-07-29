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
    /// Roughly display rate. Fast enough that the HUD reads as attached to the pointer rather
    /// than trailing it.
    private static let followInterval: TimeInterval = 1.0 / 60.0
    /// Sub-pixel jitter is not worth a window-server round trip.
    private static let movementThreshold: CGFloat = 0.5

    private let model: AppModel
    private let logger: DiagnosticLogging
    private let openPanel: () -> Void

    private var panel: FloatingPanel?
    private var autoHideTask: Task<Void, Never>?
    private var followTimer: DispatchSourceTimer?
    private var lastCursor: CGPoint?
    /// Size at the last placement, so the timer only re-reads the frame when it actually changes.
    private var lastSize: CGSize = .zero

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
        followTimer?.cancel()
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let follows = model.settings.miniHUDFollowsPointer
        let panel = ensurePanel(followsPointer: follows)

        // A window glued to the pointer must not intercept clicks meant for what is underneath.
        panel.ignoresMouseEvents = follows

        lastCursor = nil
        reposition(panel)

        // `orderFrontRegardless` rather than `makeKeyAndOrderFront`: the HUD appears without
        // pulling activation away from the app the user is in.
        panel.orderFrontRegardless()
        model.hudDidAppear()

        if follows { startFollowing() } else { stopFollowing() }
        scheduleAutoHide()
    }

    func hide() {
        autoHideTask?.cancel()
        autoHideTask = nil
        stopFollowing()
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        model.hudDidDisappear()
    }

    // MARK: - Following

    private func startFollowing() {
        stopFollowing()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + Self.followInterval,
            repeating: Self.followInterval,
            leeway: .milliseconds(2)
        )
        timer.setEventHandler { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            self.reposition(panel)
        }
        followTimer = timer
        timer.resume()
    }

    private func stopFollowing() {
        followTimer?.setEventHandler(handler: nil)
        followTimer?.cancel()
        followTimer = nil
        lastCursor = nil
    }

    // MARK: - Placement

    /// Places the HUD beside the pointer using the same geometry as the full panel, so it flips
    /// at screen edges and moves between displays as the pointer does.
    private func reposition(_ panel: FloatingPanel) {
        let cursor = NSEvent.mouseLocation

        // Skip the work entirely while the pointer is still.
        if let lastCursor,
           abs(cursor.x - lastCursor.x) < Self.movementThreshold,
           abs(cursor.y - lastCursor.y) < Self.movementThreshold,
           panel.frame.size == lastSize {
            return
        }
        lastCursor = cursor

        let size = CGSize(width: max(panel.frame.width, 80), height: max(panel.frame.height, 24))
        lastSize = panel.frame.size

        let screens = NSScreen.screens
        guard let index = ScreenPositioning.screenIndex(containing: cursor, screens: screens.map(\.frame)) else {
            return
        }

        let placement = ScreenPositioning.place(
            cursor: cursor,
            panelSize: size,
            visibleFrame: screens[index].visibleFrame
        )
        guard placement.origin != panel.frame.origin else { return }
        panel.setFrameOrigin(placement.origin)
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

    /// Rebuilt when the follow setting changes, since interactivity is baked into the view.
    private func ensurePanel(followsPointer: Bool) -> FloatingPanel {
        if let panel, panelIsInteractive == !followsPointer { return panel }

        panel?.orderOut(nil)

        let rootView = MiniHUDView(model: model, isInteractive: !followsPointer) { [weak self] in
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
        self.panelIsInteractive = !followsPointer
        return panel
    }

    private var panelIsInteractive: Bool?

    @objc private func screenParametersChanged() {
        guard let panel, panel.isVisible else { return }
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        if let origin = ScreenPositioning.reposition(currentFrame: panel.frame, visibleFrames: visibleFrames) {
            panel.setFrameOrigin(origin)
        }
    }
}
