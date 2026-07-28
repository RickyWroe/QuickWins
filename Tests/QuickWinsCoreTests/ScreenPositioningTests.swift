import CoreGraphics
import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Screen positioning")
struct ScreenPositioningTests {
    /// A 1440x900 display with the menu bar excluded, in AppKit bottom-left coordinates.
    private let mainScreen = CGRect(x: 0, y: 0, width: 1_440, height: 862)
    private let panel = CGSize(width: 340, height: 420)

    @Test("The panel opens 12 points right of and below the pointer")
    func defaultPlacementIsDownAndRight() {
        let placement = ScreenPositioning.place(
            cursor: CGPoint(x: 400, y: 700), panelSize: panel, visibleFrame: mainScreen
        )
        let expectedOrigin = CGPoint(x: 400 + 12, y: 700 - 12 - panel.height)
        #expect(placement.origin.x == expectedOrigin.x)
        // Top edge sits 12 points under the cursor, so the origin is a panel-height lower.
        #expect(placement.origin.y == expectedOrigin.y)
        #expect(!placement.flippedHorizontally)
        #expect(!placement.flippedVertically)
        #expect(!placement.clamped)
    }

    @Test("Near the right edge the panel mirrors to the pointer's left")
    func flipsHorizontallyAtRightEdge() {
        let placement = ScreenPositioning.place(
            cursor: CGPoint(x: 1_400, y: 700), panelSize: panel, visibleFrame: mainScreen
        )
        let expectedX: CGFloat = 1_400 - 12 - panel.width
        #expect(placement.flippedHorizontally)
        #expect(placement.origin.x == expectedX)
        #expect(placement.origin.x + panel.width <= mainScreen.maxX)
        #expect(!placement.clamped)
    }

    @Test("Near the bottom edge the panel mirrors above the pointer")
    func flipsVerticallyAtBottomEdge() {
        let placement = ScreenPositioning.place(
            cursor: CGPoint(x: 400, y: 80), panelSize: panel, visibleFrame: mainScreen
        )
        let expectedY: CGFloat = 80 + 12
        #expect(placement.flippedVertically)
        #expect(placement.origin.y == expectedY)
        #expect(placement.origin.y >= mainScreen.minY)
    }

    @Test("A bottom-right corner pointer flips on both axes at once")
    func flipsBothAxesInCorner() {
        let placement = ScreenPositioning.place(
            cursor: CGPoint(x: 1_430, y: 20), panelSize: panel, visibleFrame: mainScreen
        )
        #expect(placement.flippedHorizontally)
        #expect(placement.flippedVertically)
        let frame = CGRect(origin: placement.origin, size: panel)
        #expect(mainScreen.contains(frame))
    }

    @Test("The panel always ends up fully on screen, whatever the pointer position")
    func neverLeavesTheVisibleFrame() {
        for x in stride(from: CGFloat(0), through: 1_440, by: 60) {
            for y in stride(from: CGFloat(0), through: 862, by: 60) {
                let placement = ScreenPositioning.place(
                    cursor: CGPoint(x: x, y: y), panelSize: panel, visibleFrame: mainScreen
                )
                let frame = CGRect(origin: placement.origin, size: panel)
                #expect(mainScreen.contains(frame), "Panel escaped at cursor (\(x), \(y))")
            }
        }
    }

    @Test("A panel taller than the screen is clamped rather than placed off-screen")
    func clampsWhenPanelCannotFit() {
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 200)
        let placement = ScreenPositioning.place(
            cursor: CGPoint(x: 150, y: 100), panelSize: panel, visibleFrame: tiny
        )
        #expect(placement.clamped)
        #expect(placement.origin.x == tiny.minX)
        #expect(placement.origin.y == tiny.minY)
    }

    // MARK: - Multiple displays

    @Test("The pointer's own display is chosen on a multi-monitor desk")
    func picksScreenUnderCursor() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_440, height: 862),
            CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
        ]
        #expect(ScreenPositioning.screenIndex(containing: CGPoint(x: 2_000, y: 500), screens: screens) == 1)
        #expect(ScreenPositioning.screenIndex(containing: CGPoint(x: 200, y: 500), screens: screens) == 0)
    }

    @Test("A display arranged to the left of the main one is handled")
    func handlesNegativeOriginDisplay() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_440, height: 862),
            CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
        ]
        let index = ScreenPositioning.screenIndex(containing: CGPoint(x: -1_800, y: 400), screens: screens)
        #expect(index == 1)

        let placement = ScreenPositioning.place(
            cursor: CGPoint(x: -1_800, y: 400), panelSize: panel, visibleFrame: screens[1]
        )
        #expect(screens[1].contains(CGRect(origin: placement.origin, size: panel)))
    }

    @Test("A pointer in the dead space between mismatched displays still resolves to a screen")
    func fallsBackToNearestScreen() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_440, height: 862),
            CGRect(x: 1_440, y: 400, width: 1_920, height: 1_080),
        ]
        // Below the second display's bottom edge, past the first display's right edge.
        let index = ScreenPositioning.screenIndex(containing: CGPoint(x: 1_600, y: 100), screens: screens)
        #expect(index != nil)
    }

    @Test("No screens means no placement rather than a guess at the origin")
    func noScreensYieldsNil() {
        #expect(ScreenPositioning.screenIndex(containing: .zero, screens: []) == nil)
    }

    // MARK: - Display changes while open

    @Test("An open panel is left alone while its display is still connected")
    func repositionIsNoOpWhenStillVisible() {
        let frame = CGRect(x: 100, y: 100, width: 340, height: 420)
        #expect(ScreenPositioning.reposition(currentFrame: frame, visibleFrames: [mainScreen]) == nil)
    }

    @Test("An open panel is pulled back when its display disappears")
    func repositionRecoversFromDisconnectedDisplay() throws {
        let onSecondDisplay = CGRect(x: 2_000, y: 500, width: 340, height: 420)
        let origin = try #require(
            ScreenPositioning.reposition(currentFrame: onSecondDisplay, visibleFrames: [mainScreen])
        )
        #expect(mainScreen.contains(CGRect(origin: origin, size: panel)))
    }
}
