import QuickWinsCore
import SwiftUI

enum Theme {
    static let panelWidth: CGFloat = 340
    static let cornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 10
    static let horizontalPadding: CGFloat = 14
    /// Minimum practical hit target for a macOS control.
    static let minimumHitTarget: CGFloat = 22
    static let maximumListHeight: CGFloat = 240

    /// Panel geometry.
    ///
    /// The panel window's height is computed from these rather than measured from the view. A
    /// window that sizes itself to SwiftUI content containing a `ScrollView` is ambiguous: the
    /// scroll view wants to be as tall as its content, the window resizes to match, the scroll
    /// view re-measures, and AppKit's constraint engine recurses until the stack is exhausted.
    /// Adding a task did exactly that. Slight over-estimation here shows as a little empty space
    /// above the quick-add field, which is harmless; the alternative is a crash.
    static let panelHeaderHeight: CGFloat = 38
    static let panelDividerHeight: CGFloat = 1
    static let panelActiveCardHeight: CGFloat = 204
    static let panelEmptyFocusHeight: CGFloat = 142
    static let panelSectionHeaderHeight: CGFloat = 27
    static let panelRowHeight: CGFloat = 30
    static let panelListBottomPadding: CGFloat = 6
    static let panelQuickAddHeight: CGFloat = 39
    static let panelMinimumHeight: CGFloat = 170
    static let panelMaximumHeight: CGFloat = 580

    /// The system accent colour, so QuickWins matches whatever the user picked in Appearance
    /// settings rather than imposing a brand colour.
    static let accent = Color.accentColor
}

extension AccountabilityLevel {
    /// Colour is only ever a reinforcement here; `indicatorLabel` carries the same meaning.
    var indicatorColor: Color {
        switch self {
        case .calm: return .secondary
        case .subtle: return .yellow
        case .gentle: return .orange
        case .strong, .interrupted: return .red
        }
    }

    var indicatorSymbol: String {
        switch self {
        case .calm: return "circle.fill"
        case .subtle: return "moon.zzz"
        case .gentle: return "bell"
        case .strong: return "bell.badge"
        case .interrupted: return "exclamationmark.triangle"
        }
    }

    var indicatorLabel: String? {
        switch self {
        case .calm: return nil
        case .subtle: return "Quiet for a few minutes"
        case .gentle: return "No input for a while"
        case .strong: return "Still on this?"
        case .interrupted: return "Session interrupted"
        }
    }
}

extension View {
    /// Applies a transform only on the OS versions where it exists.
    @ViewBuilder
    func applying<Content: View>(@ViewBuilder _ transform: (Self) -> Content) -> some View {
        transform(self)
    }
}
