import AppKit
import Carbon.HIToolbox
import QuickWinsCore

enum GlobalShortcutError: Error, LocalizedError {
    case registrationFailed(OSStatus)
    case handlerInstallFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status) where status == OSStatus(eventHotKeyExistsErr):
            return "That keyboard shortcut is already claimed by macOS or another app."
        case .registrationFailed(let status):
            return "The keyboard shortcut could not be registered (error \(status))."
        case .handlerInstallFailed(let status):
            return "The keyboard shortcut handler could not be installed (error \(status))."
        }
    }
}

/// System-wide hot key registration.
///
/// Uses Carbon's `RegisterEventHotKey`, which is still the supported way to claim a global
/// shortcut without requesting Accessibility permission. The event-tap alternative would work
/// but would demand a far broader permission than opening a panel warrants.
@MainActor
final class GlobalShortcutService {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextIdentifier: UInt32 = 1
    private static let signature: FourCharCode = 0x5157_6E73 // 'QWns'

    /// The Carbon event handler is installed once per process, not once per service.
    ///
    /// `InstallEventHandler` refuses a duplicate registration of the same callback on the same
    /// target with `eventHandlerAlreadyInstalledErr`, so a second service instance would fail to
    /// install and its hot key would never fire. One shared handler is also all that is needed:
    /// it dispatches by hot-key id through `handlers`.
    private static var sharedHandlerRef: EventHandlerRef?

    private var hotKeyRef: EventHotKeyRef?
    private var identifier: UInt32?

    private let logger: DiagnosticLogging
    var onTrigger: (() -> Void)?

    init(logger: DiagnosticLogging) {
        self.logger = logger
    }

    deinit {
        // The shared handler outlives individual services and is torn down with the process.
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    }

    private(set) var registeredBinding: ShortcutBinding?

    func register(_ binding: ShortcutBinding) throws {
        unregister()
        try installHandlerIfNeeded()

        let identifier = Self.nextIdentifier
        Self.nextIdentifier += 1
        self.identifier = identifier

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            self.identifier = nil
            logger.error("shortcut", "Registration of \(binding.display) failed with status \(status).")
            throw GlobalShortcutError.registrationFailed(status)
        }

        hotKeyRef = reference
        registeredBinding = binding
        Self.handlers[identifier] = { [weak self] in self?.onTrigger?() }
        logger.info("shortcut", "Registered global shortcut \(binding.display).")
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let identifier { Self.handlers.removeValue(forKey: identifier) }
        identifier = nil
        registeredBinding = nil
    }

    private func installHandlerIfNeeded() throws {
        guard Self.sharedHandlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var reference: EventHandlerRef?
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &spec,
            nil,
            &reference
        )
        // Already installed is success, not failure — it means another code path beat us to it.
        guard status == noErr || status == OSStatus(eventHandlerAlreadyInstalledErr) else {
            throw GlobalShortcutError.handlerInstallFailed(status)
        }
        Self.sharedHandlerRef = reference
    }

    fileprivate static func fire(identifier: UInt32) {
        handlers[identifier]?()
    }
}

/// Carbon requires a plain C function pointer, so the callback bounces through a static table
/// keyed by hot-key id rather than capturing the service instance.
private let hotKeyEventHandler: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let identifier = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated { GlobalShortcutService.fire(identifier: identifier) }
    }
    return noErr
}
