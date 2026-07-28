import Foundation

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case upcoming
    case active
    case paused
    case completed
    case skipped
    case overdue

    /// Statuses that still expect work from the user today.
    public var isOpen: Bool {
        switch self {
        case .upcoming, .active, .paused, .overdue: return true
        case .completed, .skipped: return false
        }
    }

    /// Only `.active` may hold a running focus session.
    public var holdsRunningSession: Bool { self == .active }

    public var accessibilityDescription: String {
        switch self {
        case .upcoming: return "Upcoming"
        case .active: return "Active, timer running"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .skipped: return "Skipped"
        case .overdue: return "Overdue"
        }
    }

    /// SF Symbol used to convey status without relying on color alone.
    public var symbolName: String {
        switch self {
        case .upcoming: return "circle"
        case .active: return "record.circle"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "arrow.uturn.forward.circle"
        case .overdue: return "exclamationmark.circle"
        }
    }
}
