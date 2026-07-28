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
