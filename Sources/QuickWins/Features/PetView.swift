import QuickWinsCore
import SwiftUI

/// The companion: one tortoise that gets sleepy while nothing is happening and wakes the moment
/// you touch the keyboard.
///
/// Always drawn at a fixed size. The mini HUD's window is sized by its controller, and content
/// that changed size with state would reintroduce the layout recursion that crashed the app in
/// 1.1.1 — so posture is expressed through rotation and tint inside a constant frame, never by
/// growing.
struct PetView: View {
    let state: PetState
    /// Body tint, normally the active task's colour.
    let color: Color
    /// 0–1 share of today's focus goal. Brightens the pet; never dims it as a penalty.
    let vitality: Double
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var symbolName: String {
        state.prefersFilledSymbol ? "tortoise.fill" : "tortoise"
    }

    /// Sleepiness drains the colour toward grey, so the state reads even in a monochrome capture.
    private var bodyTint: Color {
        let awake = 1 - state.restfulness
        return color.opacity(0.45 + 0.55 * awake)
    }

    /// A shallow forward tilt as it settles. Deliberately small — this is a status indicator that
    /// happens to have a face, not an animation.
    private var tilt: Angle {
        .degrees(state.restfulness * 8)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: symbolName)
                .font(.system(size: size * 0.78, weight: .regular))
                .foregroundStyle(bodyTint)
                .rotationEffect(tilt, anchor: .bottom)
                .brightnessBoost(vitality)

            if state.showsSleepMarker {
                Image(systemName: "zzz")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .offset(x: size * 0.16, y: -size * 0.12)
            }
        }
        // Constant frame regardless of state: see the note above.
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: state)
        .accessibilityHidden(true)
    }
}

private extension View {
    /// A day approaching its goal lifts the pet slightly. Reward only — a low value is simply
    /// neutral, never a visible penalty.
    @ViewBuilder
    func brightnessBoost(_ vitality: Double) -> some View {
        let clamped = min(1, max(0, vitality))
        self.brightness(clamped * 0.12)
            .saturation(0.85 + clamped * 0.25)
    }
}
