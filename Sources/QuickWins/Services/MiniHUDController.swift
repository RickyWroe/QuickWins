import AppKit
import QuickWinsCore
import SwiftUI

/// Shows and hides the compact cursor HUD.
///
/// By default the HUD stays on screen until the user switches it off, and the shortcut is a
/// show/hide switch rather than a peek. It never takes key focus and never activates the app, so
/// pressing the shortcut mid-sentence does not interrupt typing.
@MainActor
final class MiniHUDController {
    /// Cadence while the pointer is moving. Fast enough that the HUD reads as attached to it.
    private static let activeInterval: TimeInterval = 1.0 / 30.0
    /// Cadence once the pointer has been still. An always-on HUD spends most of its life here,
    /// so this is what determines its resting cost.
    private static let idleInterval: TimeInterval = 0.5
    /// How long the pointer must be still before dropping to the idle cadence.
    private static let quietPeriod: TimeInterval = 0.75
    /// Sub-pixel jitter is not worth a window-server round trip.
    private static let movementThreshold: CGFloat = 0.5

    private let model: AppModel
    private let logger: DiagnosticLogging
    private let openPanel: () -> Void

    private var panel: FloatingPanel?
    private var autoHideTask: Task<Void, Never>?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var followTimer: DispatchSourceTimer?
    private var isPollingFast = false
    private var lastMovementAt: Date?
    private var lastCursor: CGPoint?
    private var lastSize: CGSize = .zero
    private var panelIsInteractive: Bool?

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
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        followTimer?.cancel()
    }

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - Lifecycle

    /// Restores the HUD at launch when the user left it on.
    func restoreVisibility() {
        guard model.settings.miniHUDAlwaysVisible, model.settings.miniHUDVisible else { return }
        show(persist: false)
    }

    /// The shortcut and the menu item both land here, and the choice sticks across relaunches.
    func toggle() {
        isVisible ? hide(persist: true) : show(persist: true)
    }

    /// Re-applies the settings that change how the HUD behaves rather than what it shows.
    func applySettings() {
        let settings = model.settings

        if settings.miniHUDAlwaysVisible {
            autoHideTask?.cancel()
            autoHideTask = nil
            if settings.miniHUDVisible && !isVisible {
                show(persist: false)
                return
            }
        }

        guard isVisible, let panel else { return }
        // Follow mode is baked into the panel's interactivity, so a change rebuilds it.
        if panelIsInteractive == settings.miniHUDFollowsPointer {
            hide(persist: false)
            show(persist: false)
            return
        }
        panel.ignoresMouseEvents = settings.miniHUDFollowsPointer
        settings.miniHUDFollowsPointer ? startFollowing() : stopFollowing()
        scheduleAutoHide()
    }

    func show(persist: Bool = true) {
        let follows = model.settings.miniHUDFollowsPointer
        let panel = ensurePanel(followsPointer: follows)

        // A window glued to the pointer must not intercept clicks meant for what is underneath.
        panel.ignoresMouseEvents = follows
        // A drop shadow has to be recomputed by the window server on every move; at pointer
        // speed that dominates the cost of following. The capsule's border carries the edge.
        panel.hasShadow = !follows

        // Force a layout pass first: the hosting controller sizes the window from its SwiftUI
        // content asynchronously, and placing a not-yet-sized window puts it in the wrong spot
        // until the next poll corrects it.
        panel.layoutIfNeeded()

        lastCursor = nil
        reposition(panel)
        panel.orderFrontRegardless()
        model.hudDidAppear()

        if follows { startFollowing() } else { stopFollowing() }
        scheduleAutoHide()

        if persist { persistVisibility(true) }
    }

    func hide(persist: Bool = true) {
        autoHideTask?.cancel()
        autoHideTask = nil
        stopFollowing()
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            model.hudDidDisappear()
        }
        if persist { persistVisibility(false) }
    }

    private func persistVisibility(_ visible: Bool) {
        guard model.settings.miniHUDVisible != visible else { return }
        model.updateSettings { $0.miniHUDVisible = visible }
    }

    // MARK: - Following

    /// Tracking polls the cursor, at a cadence that adapts to whether it is moving.
    ///
    /// Mouse monitors alone are not enough: a cursor can move without this process seeing an
    /// event — `CGWarpMouseCursorPosition` generates none at all, and a global monitor only
    /// observes events delivered to other applications. Polling is therefore the source of
    /// truth, and the monitors exist only to snap back to the fast cadence the instant the
    /// pointer stirs. While the pointer is still the timer drops to twice a second, which is
    /// what keeps an all-day HUD cheap.
    private func startFollowing() {
        stopFollowing()

        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
        ]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.noteMovement()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.noteMovement()
            return event
        }

        lastMovementAt = Date()
        schedulePolling(fast: true)
    }

    private func stopFollowing() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        followTimer?.setEventHandler(handler: nil)
        followTimer?.cancel()
        followTimer = nil
        isPollingFast = false
        lastMovementAt = nil
        lastCursor = nil
    }

    private func schedulePolling(fast: Bool) {
        guard isPollingFast != fast || followTimer == nil else { return }
        followTimer?.setEventHandler(handler: nil)
        followTimer?.cancel()

        let interval = fast ? Self.activeInterval : Self.idleInterval
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: fast ? .milliseconds(2) : .milliseconds(150)
        )
        timer.setEventHandler { [weak self] in self?.pollCursor() }
        followTimer = timer
        isPollingFast = fast
        timer.resume()
    }

    /// A mouse event means the pointer is live; go back to the fast cadence immediately.
    private func noteMovement() {
        guard isVisible else { return }
        lastMovementAt = Date()
        schedulePolling(fast: true)
        pollCursor()
    }

    private func pollCursor() {
        guard let panel, panel.isVisible else { return }
        if reposition(panel) {
            lastMovementAt = Date()
            schedulePolling(fast: true)
            return
        }
        // Drop to the idle cadence once the pointer has been still for a moment.
        if isPollingFast, let lastMovementAt, Date().timeIntervalSince(lastMovementAt) > Self.quietPeriod {
            schedulePolling(fast: false)
        }
    }

    /// Places the HUD beside the pointer using the same geometry as the full panel, so it flips
    /// at screen edges and moves between displays as the pointer does.
    ///
    /// Returns true when the pointer had actually moved, which is what drives the cadence.
    @discardableResult
    private func reposition(_ panel: FloatingPanel) -> Bool {
        let cursor = NSEvent.mouseLocation

        if let lastCursor,
           abs(cursor.x - lastCursor.x) < Self.movementThreshold,
           abs(cursor.y - lastCursor.y) < Self.movementThreshold,
           panel.frame.size == lastSize {
            return false
        }
        lastCursor = cursor

        let size = CGSize(width: max(panel.frame.width, 80), height: max(panel.frame.height, 24))
        lastSize = panel.frame.size

        let screens = NSScreen.screens
        guard let index = ScreenPositioning.screenIndex(containing: cursor, screens: screens.map(\.frame)) else {
            return true
        }

        let placement = ScreenPositioning.place(
            cursor: cursor,
            panelSize: size,
            visibleFrame: screens[index].visibleFrame
        )
        if placement.origin != panel.frame.origin {
            panel.setFrameOrigin(placement.origin)
        }
        return true
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
        // An always-on HUD has no business hiding itself.
        guard !model.settings.miniHUDAlwaysVisible else { return }
        let seconds = model.settings.miniHUDAutoHideSeconds
        guard seconds > 0 else { return }
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // An auto-hide is the HUD getting out of the way, not the user switching it off.
            self?.hide(persist: false)
        }
    }

    /// Rebuilt when the follow setting changes, since interactivity is baked into the view.
    private func ensurePanel(followsPointer: Bool) -> FloatingPanel {
        if let panel, panelIsInteractive == !followsPointer { return panel }

        panel?.orderOut(nil)

        let rootView = MiniHUDView(model: model, isInteractive: !followsPointer) { [weak self] in
            guard let self else { return }
            if !self.model.settings.miniHUDAlwaysVisible { self.hide(persist: false) }
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

    @objc private func screenParametersChanged() {
        guard let panel, panel.isVisible else { return }
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        if let origin = ScreenPositioning.reposition(currentFrame: panel.frame, visibleFrames: visibleFrames) {
            panel.setFrameOrigin(origin)
        }
    }
}
