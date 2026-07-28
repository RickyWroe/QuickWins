import Foundation
import OSLog

public enum DiagnosticLevel: String, Sendable, CaseIterable {
    case debug
    case info
    case notice
    case error
}

public protocol DiagnosticLogging: AnyObject, Sendable {
    func log(_ level: DiagnosticLevel, category: String, _ message: String)
    /// Recent entries as plain text for the "Export diagnostic log" settings action.
    func exportText() -> String
    func clear()
}

public extension DiagnosticLogging {
    func info(_ category: String, _ message: String) { log(.info, category: category, message) }
    func notice(_ category: String, _ message: String) { log(.notice, category: category, message) }
    func error(_ category: String, _ message: String) { log(.error, category: category, message) }
}

/// Structured logging to the unified log plus a bounded in-memory ring buffer for export.
///
/// Task titles and notes are never logged — call sites pass task identifiers instead — so an
/// exported diagnostic file cannot leak what the user is working on.
public final class DiagnosticLogger: DiagnosticLogging, @unchecked Sendable {
    public static let subsystem = "com.rickywroe.quickwins"

    private struct Entry {
        let date: Date
        let level: DiagnosticLevel
        let category: String
        let message: String
    }

    private let capacity: Int
    private let lock = NSLock()
    private var entries: [Entry] = []
    private var loggers: [String: Logger] = [:]
    private let formatter: ISO8601DateFormatter

    public init(capacity: Int = 500) {
        self.capacity = max(50, capacity)
        self.formatter = ISO8601DateFormatter()
        self.formatter.formatOptions = [.withInternetDateTime]
    }

    public func log(_ level: DiagnosticLevel, category: String, _ message: String) {
        lock.lock()
        let logger = loggers[category] ?? {
            let created = Logger(subsystem: Self.subsystem, category: category)
            loggers[category] = created
            return created
        }()
        entries.append(Entry(date: Date(), level: level, category: category, message: message))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        lock.unlock()

        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .notice: logger.notice("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
    }

    public func exportText() -> String {
        lock.lock()
        let snapshot = entries
        lock.unlock()

        var lines = [
            "QuickWins diagnostic log",
            "Generated: \(formatter.string(from: Date()))",
            "Entries: \(snapshot.count)",
            "",
        ]
        lines.append(contentsOf: snapshot.map { entry in
            "\(formatter.string(from: entry.date)) [\(entry.level.rawValue)] \(entry.category): \(entry.message)"
        })
        return lines.joined(separator: "\n")
    }

    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}

/// Discards everything. Used by tests that do not assert on logging.
public final class NullDiagnosticLogger: DiagnosticLogging, @unchecked Sendable {
    public init() {}
    public func log(_ level: DiagnosticLevel, category: String, _ message: String) {}
    public func exportText() -> String { "" }
    public func clear() {}
}
