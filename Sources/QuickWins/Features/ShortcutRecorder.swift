import AppKit
import Carbon.HIToolbox
import QuickWinsCore
import SwiftUI

/// Captures a single key combination for use as the global shortcut.
///
/// While recording, a local event monitor swallows key events so the keystroke configures the
/// shortcut instead of being delivered to the settings window.
struct ShortcutRecorder: View {
    @Binding var binding: ShortcutBinding
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(isRecording ? "Press keys…" : binding.display)
                .font(.callout.monospaced())
                .frame(minWidth: 96, minHeight: 22)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Theme.accent.opacity(0.15) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isRecording ? Theme.accent : Color.primary.opacity(0.15))
                )

            Button(isRecording ? "Cancel" : "Record") {
                isRecording ? stopRecording() : startRecording()
            }

            Button("Reset") {
                binding = .default
            }
            .disabled(binding == .default)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Global shortcut, currently \(binding.display)")
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard let captured = ShortcutRecorder.binding(from: event) else { return nil }
            binding = captured
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    /// Rejects bare keys: a global shortcut with no modifier would fire while typing anywhere.
    static func binding(from event: NSEvent) -> ShortcutBinding? {
        let carbonModifiers = carbonFlags(from: event.modifierFlags)
        guard carbonModifiers != 0 else { return nil }
        let keyCode = UInt32(event.keyCode)
        return ShortcutBinding(
            keyCode: keyCode,
            carbonModifiers: carbonModifiers,
            display: display(keyCode: keyCode, modifiers: event.modifierFlags)
        )
    }

    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= ShortcutBinding.CarbonModifier.command }
        if flags.contains(.shift) { result |= ShortcutBinding.CarbonModifier.shift }
        if flags.contains(.option) { result |= ShortcutBinding.CarbonModifier.option }
        if flags.contains(.control) { result |= ShortcutBinding.CarbonModifier.control }
        return result
    }

    static func display(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + keyName(for: keyCode)
    }

    private static func keyName(for keyCode: UInt32) -> String {
        // Named keys first; anything else is resolved from the current keyboard layout so the
        // label matches what is printed on the user's keys.
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Escape"
        case kVK_Delete: return "Delete"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: break
        }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "Key \(keyCode)" }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}
