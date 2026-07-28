import Foundation
import ServiceManagement

public enum LaunchAtLoginError: Error, LocalizedError {
    case unavailable
    case registrationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Launch at login requires QuickWins to be running from an application bundle."
        case .registrationFailed(let reason):
            return "macOS refused the login item: \(reason)"
        }
    }
}

public protocol LaunchAtLoginManaging: AnyObject, Sendable {
    var isSupported: Bool { get }
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// Login-item registration via `SMAppService`, the supported replacement for
/// `LSSharedFileList` and login-item helper bundles.
public final class LaunchAtLoginService: LaunchAtLoginManaging, @unchecked Sendable {
    private let logger: DiagnosticLogging

    public init(logger: DiagnosticLogging) {
        self.logger = logger
    }

    /// `SMAppService.mainApp` needs a real bundle; running the raw executable cannot register.
    public var isSupported: Bool { Bundle.main.bundleIdentifier != nil }

    public var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        guard isSupported else { throw LaunchAtLoginError.unavailable }
        do {
            if enabled {
                // Registering an already-registered service throws; treat it as success.
                guard SMAppService.mainApp.status != .enabled else { return }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            logger.info("launchAtLogin", "Login item \(enabled ? "registered" : "unregistered").")
        } catch {
            logger.error("launchAtLogin", "Failed to \(enabled ? "register" : "unregister"): \(error.localizedDescription)")
            throw LaunchAtLoginError.registrationFailed(error.localizedDescription)
        }
    }
}

public final class StubLaunchAtLoginService: LaunchAtLoginManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    public var isSupported: Bool
    public var failureToThrow: Error?

    public init(isSupported: Bool = true) {
        self.isSupported = isSupported
    }

    public var isEnabled: Bool {
        lock.lock(); defer { lock.unlock() }
        return enabled
    }

    public func setEnabled(_ value: Bool) throws {
        guard isSupported else { throw LaunchAtLoginError.unavailable }
        if let failureToThrow { throw failureToThrow }
        lock.lock(); enabled = value; lock.unlock()
    }
}
