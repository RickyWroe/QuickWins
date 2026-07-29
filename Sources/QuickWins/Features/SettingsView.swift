import AppKit
import QuickWinsCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let shortcutError: String?
    let hudShortcutError: String?
    let applyShortcut: () -> Void
    let applyHUDSettings: () -> Void

    var body: some View {
        TabView {
            GeneralSettingsTab(
                model: model,
                shortcutError: shortcutError,
                hudShortcutError: hudShortcutError,
                applyShortcut: applyShortcut,
                applyHUDSettings: applyHUDSettings
            )
                .tabItem { Label("General", systemImage: "gearshape") }

            AlertSettingsTab(model: model)
                .tabItem { Label("Check-ins", systemImage: "bell") }

            AdvancedSettingsTab(model: model)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 460)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @ObservedObject var model: AppModel
    let shortcutError: String?
    let hudShortcutError: String?
    let applyShortcut: () -> Void
    let applyHUDSettings: () -> Void

    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Enable global shortcut", isOn: binding(\.shortcutEnabled))
                    .onChange(of: model.settings.shortcutEnabled) { _, _ in applyShortcut() }

                LabeledContent("Shortcut") {
                    ShortcutRecorder(binding: Binding(
                        get: { model.settings.shortcut },
                        set: { newValue in
                            model.updateSettings { $0.shortcut = newValue }
                            applyShortcut()
                        }
                    ))
                    .disabled(!model.settings.shortcutEnabled)
                }

                if let shortcutError {
                    Label(shortcutError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Opening the panel")
            }

            Section {
                Toggle("Enable mini HUD shortcut", isOn: binding(\.miniHUDShortcutEnabled))
                    .onChange(of: model.settings.miniHUDShortcutEnabled) { _, _ in applyShortcut() }

                LabeledContent("Shortcut") {
                    ShortcutRecorder(binding: Binding(
                        get: { model.settings.miniHUDShortcut },
                        set: { newValue in
                            model.updateSettings { $0.miniHUDShortcut = newValue }
                            applyShortcut()
                        }
                    ))
                    .disabled(!model.settings.miniHUDShortcutEnabled)
                }

                Toggle("Keep the HUD on screen", isOn: binding(\.miniHUDAlwaysVisible))
                    .onChange(of: model.settings.miniHUDAlwaysVisible) { _, _ in applyHUDSettings() }

                Toggle("Follow the pointer", isOn: binding(\.miniHUDFollowsPointer))
                    .onChange(of: model.settings.miniHUDFollowsPointer) { _, _ in applyHUDSettings() }

                LabeledContent("Hide after") {
                    Stepper(value: Binding(
                        get: { model.settings.miniHUDAutoHideSeconds },
                        set: { value in model.updateSettings { $0.miniHUDAutoHideSeconds = value } }
                    ), in: 0...60, step: 1) {
                        Text(model.settings.miniHUDAutoHideSeconds == 0
                             ? "Stays open"
                             : "\(Int(model.settings.miniHUDAutoHideSeconds))s")
                            .font(.callout.monospacedDigit())
                            .frame(minWidth: 76, alignment: .trailing)
                    }
                }
                .disabled(model.settings.miniHUDAlwaysVisible)

                if let hudShortcutError {
                    Label(hudShortcutError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Mini HUD")
            } footer: {
                Text("A small capsule beside the pointer showing the current task's colour and elapsed time. Kept on screen, the shortcut becomes a show/hide switch and the choice survives a relaunch; switch that off and the shortcut becomes a peek that hides itself. While it follows the pointer it is click-through, so it never intercepts a click meant for what is underneath — turn following off if you would rather click it to open the full panel. Avoid a plain Shift combination for the shortcut: a global shortcut consumes the key everywhere, so Shift+Q would stop you typing a capital Q.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open beside the pointer", isOn: binding(\.openPanelBesideCursor))
                Toggle("Bring the panel forward for stronger check-ins", isOn: Binding(
                    get: { model.settings.accountability.surfacePanelOnStrongAlert },
                    set: { value in model.updateSettings { $0.accountability.surfacePanelOnStrongAlert = value } }
                ))
                Toggle("Automatically start the next task", isOn: binding(\.automaticallySelectNextTask))
            } header: {
                Text("Behaviour")
            }

            Section {
                Picker("Menu bar shows", selection: Binding(
                    get: { model.settings.menuBarDisplay },
                    set: { value in model.updateSettings { $0.menuBarDisplay = value } }
                )) {
                    ForEach(MenuBarDisplayStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)

                Toggle("Launch at login", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: setLaunchAtLogin
                ))
                .disabled(!model.environment.launchAtLogin.isSupported)

                if !model.environment.launchAtLogin.isSupported {
                    Text("Available once QuickWins is running from an application bundle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("System")
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try model.environment.launchAtLogin.setEnabled(enabled)
            model.updateSettings { $0.launchAtLogin = enabled }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }
}

// MARK: - Check-ins

private struct AlertSettingsTab: View {
    @ObservedObject var model: AppModel

    private var config: AccountabilityConfig { model.settings.accountability }

    var body: some View {
        Form {
            Section {
                Toggle("Notice when there is no input", isOn: configBinding(\.enabled))
                Text("QuickWins reads only how long the system has been idle. It never inspects what you type, which apps you use, or what is on screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.notificationAuthorization == .notDetermined {
                    Button("Allow notifications…") { model.requestNotificationAuthorization() }
                } else if model.notificationAuthorization == .denied {
                    Label("Notifications are turned off in System Settings.", systemImage: "bell.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Inactivity")
            }

            Section {
                ThresholdRow(title: "Change the indicator after", minutes: minutesBinding(\.subtleThreshold), range: 1...30)
                ThresholdRow(title: "Gentle notification after", minutes: minutesBinding(\.gentleThreshold), range: 2...45)
                ThresholdRow(title: "Stronger notification after", minutes: minutesBinding(\.strongThreshold), range: 3...60)
                ThresholdRow(title: "Mark session interrupted after", minutes: minutesBinding(\.interruptThreshold), range: 5...120)
            } header: {
                Text("Thresholds")
            } footer: {
                Text("Reaching the last threshold only flags the session. Your task is never completed, failed, or changed automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!config.enabled)

            Section {
                Toggle("Play a sound", isOn: configBinding(\.soundEnabled))
                Toggle("Repeat reminders", isOn: configBinding(\.repeatRemindersEnabled))
                ThresholdRow(title: "Wait between repeats", minutes: minutesBinding(\.repeatCooldown), range: 1...60)
                    .disabled(!config.repeatRemindersEnabled)
                ThresholdRow(title: "Quiet period after \"Still working\"", minutes: minutesBinding(\.gracePeriod), range: 1...60)
            } header: {
                Text("Delivery")
            }
            .disabled(!config.enabled)

            Section {
                Toggle("Quiet hours", isOn: Binding(
                    get: { config.quietHours != nil },
                    set: { enabled in
                        model.updateSettings {
                            $0.accountability.quietHours = enabled ? QuietHours(startMinute: 22 * 60, endMinute: 7 * 60) : nil
                        }
                    }
                ))
                if let quietHours = config.quietHours {
                    MinuteOfDayRow(title: "From", minute: Binding(
                        get: { quietHours.startMinute },
                        set: { value in
                            model.updateSettings { $0.accountability.quietHours = QuietHours(startMinute: value, endMinute: quietHours.endMinute) }
                        }
                    ))
                    MinuteOfDayRow(title: "Until", minute: Binding(
                        get: { quietHours.endMinute },
                        set: { value in
                            model.updateSettings { $0.accountability.quietHours = QuietHours(startMinute: quietHours.startMinute, endMinute: value) }
                        }
                    ))
                }
            } header: {
                Text("Quiet hours")
            }
            .disabled(!config.enabled)
        }
        .formStyle(.grouped)
    }

    private func configBinding(_ keyPath: WritableKeyPath<AccountabilityConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings.accountability[keyPath: keyPath] },
            set: { value in model.updateSettings { $0.accountability[keyPath: keyPath] = value } }
        )
    }

    private func minutesBinding(_ keyPath: WritableKeyPath<AccountabilityConfig, TimeInterval>) -> Binding<Double> {
        Binding(
            get: { model.settings.accountability[keyPath: keyPath] / 60 },
            set: { value in model.updateSettings { $0.accountability[keyPath: keyPath] = value * 60 } }
        )
    }
}

private struct ThresholdRow: View {
    let title: String
    @Binding var minutes: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Stepper(value: $minutes, in: range, step: 1) {
                    Text("\(Int(minutes.rounded())) min")
                        .font(.callout.monospacedDigit())
                        .frame(minWidth: 56, alignment: .trailing)
                }
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(minutes.rounded())) minutes")
    }
}

private struct MinuteOfDayRow: View {
    let title: String
    @Binding var minute: Int

    private var date: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    var body: some View {
        DatePicker(title, selection: date, displayedComponents: .hourAndMinute)
    }
}

// MARK: - Advanced

private struct AdvancedSettingsTab: View {
    @ObservedObject var model: AppModel

    @State private var showResetConfirmation = false
    @State private var exportMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Storage") {
                    Text(model.environment.isUsingFallbackStorage ? "In memory (not saved)" : "Local database")
                        .foregroundStyle(.secondary)
                }
                Button("Export diagnostic log…") { exportDiagnostics() }
                if let exportMessage {
                    Text(exportMessage).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("The log records app events and task identifiers. It never contains task titles, notes, or anything you type.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset all data…", role: .destructive) { showResetConfirmation = true }
            } header: {
                Text("Data")
            } footer: {
                Text("Removes every task and returns all settings to their defaults. This cannot be undone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("QuickWins", value: appVersion)
                Text("A local daily task tracker. No account, no network, no analytics. Your tasks stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete every task and reset all settings?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset everything", role: .destructive) { model.resetAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "QuickWins-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportDiagnostics(to: url)
            exportMessage = "Saved to \(url.lastPathComponent)."
        } catch {
            exportMessage = "Could not save the log: \(error.localizedDescription)"
        }
    }
}
