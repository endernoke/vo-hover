// Settings window, laid out like System Settings / VoiceOver Utility:
// a category sidebar on the left and a grouped form on the right.

import SwiftUI
import ServiceManagement
import Combine

enum Pane: String, CaseIterable, Identifiable {
    case general, pointer, verbosity, commands
    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .pointer: "Pointer"
        case .verbosity: "Verbosity"
        case .commands: "Commands"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .pointer: "cursorarrow.rays"
        case .verbosity: "text.bubble.fill"
        case .commands: "command"
        }
    }
    var tint: Color {
        switch self {
        case .general: .gray
        case .pointer: .blue
        case .verbosity: .purple
        case .commands: .indigo
        }
    }
}

/// Coloured rounded-square icon, as in the System Settings sidebar.
struct SidebarIcon: View {
    let pane: Pane
    var body: some View {
        Image(systemName: pane.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(pane.tint.gradient))
            .accessibilityHidden(true)
    }
}

final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()
    @Published var selection: Pane? = .general
}

struct SettingsView: View {
    @ObservedObject var model = SettingsModel.shared

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $model.selection) { pane in
                Label { Text(pane.title) } icon: { SidebarIcon(pane: pane) }
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            let pane = model.selection ?? .general
            Group {
                switch pane {
                case .general: GeneralPane()
                case .pointer: PointerPane()
                case .verbosity: VerbosityPane()
                case .commands: CommandsPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(pane.title)
        }
        .frame(minWidth: 640, minHeight: 440)
    }
}

// MARK: - General

struct GeneralPane: View {
    @AppStorage(PrefKey.enabled) private var enabled = true
    @AppStorage(PrefKey.showInMenuBar) private var showInMenuBar = true
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var automation = VoiceOver.automationPermission()
    @State private var voRunning = VoiceOver.isRunning
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    Text("Speak item under the pointer")
                    Text("VoiceOver speaks the item under the pointer when the pointer rests on it. The VoiceOver cursor and keyboard focus don’t move.")
                }
            }

            Section {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Lets VOHover find the item under the pointer.",
                    state: axTrusted ? .granted : .denied,
                    action: { openPrivacy("Privacy_Accessibility") })
                PermissionRow(
                    title: "VoiceOver",
                    detail: voRunning
                        ? "Lets VOHover speak through VoiceOver. VoiceOver Utility must also allow VoiceOver to be controlled with AppleScript."
                        : "Turn on VoiceOver to check this permission.",
                    state: automation,
                    action: { openPrivacy("Privacy_Automation") },
                    request: VoiceOver.requestAutomationPermission)
            } header: {
                Text("Permissions")
            }

            Section {
                // A custom binding, not onChange: the periodic refresh below must not
                // register/unregister the login item, only user clicks should.
                Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: setLoginItem))
                Toggle(isOn: $showInMenuBar) {
                    Text("Show in menu bar")
                    Text("When hidden, open VOHover from Finder or Spotlight to return to these settings.")
                }
            }
        }
        .onReceive(refresh) { _ in
            axTrusted = AXIsProcessTrusted()
            voRunning = VoiceOver.isRunning
            automation = VoiceOver.automationPermission()
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            logger.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let state: PermissionState
    /// Opens the privacy pane in System Settings.
    let action: () -> Void
    /// Shows the system's consent alert, for permissions that support asking before a decision.
    var request: (() -> Void)?

    private var statusText: String {
        switch state {
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not yet requested"
        case .unknown: "Unknown"
        }
    }
    private var statusSymbol: (String, Color) {
        switch state {
        case .granted: ("checkmark.circle.fill", .green)
        case .denied: ("exclamationmark.triangle.fill", .orange)
        case .notDetermined, .unknown: ("questionmark.circle.fill", .secondary)
        }
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Label(statusText, systemImage: statusSymbol.0)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(statusSymbol.1, .primary)
                    .accessibilityLabel("\(title) permission: \(statusText)")
                if state == .notDetermined, let request {
                    Button("Allow…", action: request)
                        .accessibilityLabel("Allow \(title) access")
                } else if state == .denied {
                    Button("Open Settings…", action: action)
                        .accessibilityLabel("Open \(title) privacy settings")
                }
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

private func openPrivacy(_ anchor: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Pointer

struct PointerPane: View {
    @AppStorage(PrefKey.dwell) private var dwell = 0.15
    @AppStorage(PrefKey.useVOSummary) private var useVOSummary = false
    @AppStorage(PrefKey.readContainer) private var readContainer = true
    @AppStorage(PrefKey.textAreaReadsLine) private var textAreaReadsLine = true

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Slider(value: $dwell, in: 0...1, step: 0.05) {
                        Text("Delay before speaking")
                    } minimumValueLabel: {
                        Text("None").accessibilityHidden(true)
                    } maximumValueLabel: {
                        Text("Long").accessibilityHidden(true)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                    .accessibilityValue(String(format: "%.2f seconds", dwell))
                } label: {
                    Text("Delay before speaking")
                    Text(String(format: "%.2f seconds after the pointer stops on an item.", dwell))
                }
            }

            Section {
                Picker(selection: $useVOSummary) {
                    Text("Item description").tag(false)
                    Text("VoiceOver mouse summary").tag(true)
                } label: {
                    Text("Speak")
                    Text(useVOSummary
                         ? "Uses VoiceOver’s “Describe Item in Mouse Pointer” wording, which ends with “is under the mouse”."
                         : "Speaks the item’s name followed by the details chosen in Verbosity.")
                }

                Toggle(isOn: $readContainer) {
                    Text("Read the enclosing item when an item has no label")
                    Text("For example, reads a button when the pointer is over its unlabeled icon.")
                }
                .disabled(useVOSummary)
            }

            Section {
                Picker(selection: $textAreaReadsLine) {
                    Text("Line under the pointer").tag(true)
                    Text("All text").tag(false)
                } label: {
                    Text("In text areas, read")
                    Text("Applies to terminals, editors and other multi-line text, such as Terminal, iTerm and TextEdit.")
                }
            }
        }
    }
}

// MARK: - Verbosity

struct VerbosityPane: View {
    @AppStorage(PrefKey.useVOSummary) private var useVOSummary = false
    @AppStorage(PrefKey.includeValue) private var includeValue = true
    @AppStorage(PrefKey.includeRole) private var includeRole = true
    @AppStorage(PrefKey.includeState) private var includeState = true

    private var example: String {
        var parts = ["Volume"]
        if includeValue { parts.append("50%") }
        if includeRole { parts.append("slider") }
        if includeState { parts.append("dimmed") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $includeValue) {
                    Text("Value")
                    Text("Contents of text fields, slider positions and pop-up menu choices.")
                }
                Toggle(isOn: $includeRole) {
                    Text("Type")
                    Text("For example, “button”, “link” or “checkbox”.")
                }
                Toggle(isOn: $includeState) {
                    Text("State")
                    Text("For example, “checked” or “dimmed”.")
                }
            } header: {
                Text("After the item’s name, speak its")
            } footer: {
                if useVOSummary {
                    Text("These options don’t apply while Pointer > Speak is set to VoiceOver mouse summary.")
                }
            }
            .disabled(useVOSummary)

            Section("Example") {
                Text(example)
                    .accessibilityLabel("Example: \(example)")
            }
            .disabled(useVOSummary)
        }
    }
}

// MARK: - Commands

/// Installed by install.sh.
private let toggleScriptURL = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Scripts/VOHover/Toggle VOHover.scpt")

struct CommandsPane: View {
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Turn hover speech on or off with a VoiceOver command")
                    Text("VOHover provides a script you can assign to any VoiceOver command, such as a key, a NumPad key or a trackpad gesture.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .accessibilityElement(children: .combine)
            }

            Section {
                StepRow(number: 1, text: "Open VoiceOver Utility, choose Commands, set Command set to User, then click Edit.")
                StepRow(number: 2, text: "Click Add, choose an input, then for the command choose Custom Commands > Run AppleScript Script.")
                StepRow(number: 3, text: "Choose the Toggle VOHover script. VoiceOver says “Hover speech on” or “Hover speech off” each time you use it.")
            } header: {
                Text("Steps")
            }

            Section {
                LabeledContent {
                    HStack {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([toggleScriptURL])
                        }
                        Button(copied ? "Copied" : "Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(toggleScriptURL.path(percentEncoded: false), forType: .string)
                            copied = true
                        }
                    }
                } label: {
                    Text("Toggle VOHover script")
                    Text(toggleScriptURL.path(percentEncoded: false))
                        .textSelection(.enabled)
                }
                LabeledContent("VoiceOver Utility") {
                    Button("Open VoiceOver Utility") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/VoiceOver Utility.app"))
                    }
                }
            }
        }
    }
}

struct StepRow: View {
    let number: Int
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}
