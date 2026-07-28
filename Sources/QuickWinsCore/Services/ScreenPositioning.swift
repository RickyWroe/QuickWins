import CoreGraphics
import Foundation

public struct PanelPlacement: Equatable, Sendable {
    /// Bottom-left origin of the panel frame, in AppKit screen coordinates.
    public let origin: CGPoint
    /// True when the panel was mirrored to the cursor's left because it would overflow right.
    public let flippedHorizontally: Bool
    /// True when the panel was mirrored above the cursor because it would overflow bottom.
    public let flippedVertically: Bool
    /// True when the panel had to be clamped, i.e. it does not fit beside the cursor at all.
    public let clamped: Bool

    public init(origin: CGPoint, flippedHorizontally: Bool, flippedVertically: Bool, clamped: Bool) {
        self.origin = origin
        self.flippedHorizontally = flippedHorizontally
        self.flippedVertically = flippedVertically
        self.clamped = clamped
    }
}

/// Pure geometry for placing the floating panel beside the pointer.
///
/// Everything here works on plain rectangles rather than `NSScreen` so multi-monitor and
/// screen-edge behaviour can be tested headlessly. All coordinates are AppKit-style with the
/// origin at the bottom-left and y increasing upward.
public enum ScreenPositioning {
    /// Requested gap between the pointer and the panel, in points.
    public static let defaultOffset = CGSize(width: 12, height: 12)

    /// Picks the screen whose frame contains the point, falling back to the nearest one.
    ///
    /// The pointer can sit in the dead space between mismatched displays, so containment
    /// alone is not enough to always produce a screen.
    public static func screenIndex(containing point: CGPoint, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        if let hit = screens.firstIndex(where: { $0.contains(point) }) { return hit }

        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, frame) in screens.enumerated() {
            let clampedX = min(max(point.x, frame.minX), frame.maxX)
            let clampedY = min(max(point.y, frame.minY), frame.maxY)
            let dx = point.x - clampedX
            let dy = point.y - clampedY
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// Places the panel down-and-right of the cursor, mirroring to the opposite side when
    /// there is not enough room, and clamping as a last resort so it never leaves the screen.
    public static func place(
        cursor: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect,
        offset: CGSize = defaultOffset
    ) -> PanelPlacement {
        var flippedHorizontally = false
        var flippedVertically = false

        // Horizontal: prefer the cursor's right side.
        var originX = cursor.x + offset.width
        if originX + panelSize.width > visibleFrame.maxX {
            let mirrored = cursor.x - offset.width - panelSize.width
            if mirrored >= visibleFrame.minX {
                originX = mirrored
                flippedHorizontally = true
            }
        }

        // Vertical: "below the cursor" means the panel's top edge sits under the pointer.
        var topY = cursor.y - offset.height
        var originY = topY - panelSize.height
        if originY < visibleFrame.minY {
            let mirroredTop = cursor.y + offset.height + panelSize.height
            if mirroredTop <= visibleFrame.maxY {
                topY = mirroredTop
                originY = topY - panelSize.height
                flippedVertically = true
            }
        }

        let unclamped = CGPoint(x: originX, y: originY)
        let clampedOrigin = clamp(origin: unclamped, size: panelSize, into: visibleFrame)
        let wasClamped = abs(clampedOrigin.x - unclamped.x) > 0.5 || abs(clampedOrigin.y - unclamped.y) > 0.5

        return PanelPlacement(
            origin: clampedOrigin,
            flippedHorizontally: flippedHorizontally,
            flippedVertically: flippedVertically,
            clamped: wasClamped
        )
    }

    /// Keeps a frame fully inside the visible area, biasing to the top-left if it cannot fit.
    public static func clamp(origin: CGPoint, size: CGSize, into visibleFrame: CGRect) -> CGPoint {
        let maxX = visibleFrame.maxX - size.width
        let maxY = visibleFrame.maxY - size.height
        let x = maxX < visibleFrame.minX ? visibleFrame.minX : min(max(origin.x, visibleFrame.minX), maxX)
        let y = maxY < visibleFrame.minY ? visibleFrame.minY : min(max(origin.y, visibleFrame.minY), maxY)
        return CGPoint(x: x, y: y)
    }

    /// Re-places an already visible panel after a display change, keeping it on a live screen.
    public static func reposition(
        currentFrame: CGRect,
        visibleFrames: [CGRect]
    ) -> CGPoint? {
        guard !visibleFrames.isEmpty else { return nil }
        if visibleFrames.contains(where: { $0.contains(currentFrame) }) { return nil }

        let center = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
        guard let index = screenIndex(containing: center, screens: visibleFrames) else { return nil }
        return clamp(origin: currentFrame.origin, size: currentFrame.size, into: visibleFrames[index])
    }
}
