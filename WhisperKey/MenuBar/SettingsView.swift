import ApplicationServices
import SwiftUI

struct SettingsView: View {
    @Bindable private var preferences = Preferences.shared

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
                .tag(0)

            advancedTab
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
                .tag(1)
        }
        .frame(width: 460, height: 380)
        .fixedSize()
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Triggers") {
                HStack {
                    Text("Primary:")
                    TriggerRecorderView(slot: .primary)
                }
                HStack {
                    Text("Alternative:")
                    TriggerRecorderView(slot: .alt)
                        .opacity(preferences.altEnabled ? 1 : 0.5)
                        .disabled(!preferences.altEnabled)
                }
                Toggle("Enable alternative trigger", isOn: Binding(
                    get: { preferences.altEnabled },
                    set: { newValue in
                        preferences.altEnabled = newValue
                        NotificationCenter.default.post(name: .triggerChanged, object: nil)
                    }
                ))

                if hasMouseTrigger && !AXIsProcessTrusted() {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Accessibility permission required for mouse triggers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Settings") {
                            if let url = URL(
                                string:
                                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                            ) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                    }
                }
            }

            Section("Transcription") {
                Picker("Language", selection: $preferences.language) {
                    Text("Auto (recommended)").tag("auto")
                    Divider()
                    Text("English").tag("en")
                    Text("German").tag("de")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("Italian").tag("it")
                    Text("Portuguese").tag("pt")
                    Text("Dutch").tag("nl")
                    Text("Polish").tag("pl")
                    Text("Russian").tag("ru")
                    Text("Ukrainian").tag("uk")
                    Text("Turkish").tag("tr")
                    Text("Japanese").tag("ja")
                    Text("Korean").tag("ko")
                    Text("Chinese").tag("zh")
                    Text("Hindi").tag("hi")
                    Text("Thai").tag("th")
                    Text("Arabic").tag("ar")
                    Text("Indonesian").tag("id")
                    Text("Vietnamese").tag("vi")
                    Text("Swedish").tag("sv")
                }
            }

            Section("Output") {
                Toggle("Auto-paste transcription", isOn: $preferences.autoPaste)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                Toggle("Sound feedback on record start/stop", isOn: $preferences.soundFeedback)
            }
        }
        .formStyle(.grouped)
    }

    private var hasMouseTrigger: Bool {
        preferences.primaryType == "mouse"
            || (preferences.altEnabled && preferences.altType == "mouse")
    }

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        Form {
            Section("Paths") {
                LabeledContent("whisper-cli") {
                    HStack {
                        TextField("", text: $preferences.whisperCLIPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        Button("Reset") {
                            preferences.whisperCLIPath = Preferences.defaultWhisperCLIPath
                        }
                        .font(.caption)
                    }
                }
                LabeledContent("Model") {
                    HStack {
                        TextField("", text: $preferences.modelPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        Button("Reset") {
                            preferences.modelPath = Preferences.defaultModelPath
                        }
                        .font(.caption)
                    }
                }
            }

            Section("Performance") {
                Stepper(
                    "Threads: \(preferences.threadCount)",
                    value: $preferences.threadCount,
                    in: 1...ProcessInfo.processInfo.activeProcessorCount
                )

                Stepper(
                    "Max recording: \(Int(preferences.maxRecordingDuration / 60)) min",
                    value: $preferences.maxRecordingDuration,
                    in: 60...600,
                    step: 60
                )
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Trigger Recorder

enum TriggerSlot {
    case primary
    case alt
}

private struct TriggerRecorderView: View {
    let slot: TriggerSlot

    @State private var isRecording = false
    @State private var displayText: String = ""
    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?
    @State private var pendingMouseButton: Int?
    @State private var pendingMouseModifiers: UInt = 0
    @State private var doubleClickTimer: DispatchWorkItem?

    var body: some View {
        Button(action: { isRecording ? stopRecording() : startRecording() }) {
            Text(isRecording ? "Press key or click mouse..." : displayText)
                .frame(minWidth: 140)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .font(.system(.body, design: .monospaced))
        }
        .buttonStyle(.bordered)
        .onAppear { updateDisplayText() }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        pendingMouseButton = nil

        // Listen for keyboard events
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let modifiers = event.modifierFlags.intersection(
                [.command, .option, .control, .shift])
            guard !modifiers.isEmpty else { return nil }

            let prefs = Preferences.shared
            switch slot {
            case .primary:
                prefs.primaryType = "keyboard"
                prefs.primaryKeyCode = UInt32(event.keyCode)
                prefs.primaryModifiers = modifiers.rawValue
            case .alt:
                prefs.altType = "keyboard"
                prefs.altKeyCode = UInt32(event.keyCode)
                prefs.altModifiers = modifiers.rawValue
            }

            stopRecording()
            updateDisplayText()
            NotificationCenter.default.post(name: .triggerChanged, object: nil)
            return nil
        }

        // Listen for mouse button events (middle click, side buttons)
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { event in
            let button = event.buttonNumber
            let modifiers = event.modifierFlags.intersection(
                [.command, .option, .control, .shift])

            if let pending = pendingMouseButton, pending == button {
                // Second click on same button — store as double-click
                doubleClickTimer?.cancel()
                doubleClickTimer = nil
                pendingMouseButton = nil
                saveMouse(button: button, modifiers: modifiers, doubleClick: true)
                return nil
            }

            // First click — wait for potential double-click
            pendingMouseButton = button
            pendingMouseModifiers = modifiers.rawValue
            doubleClickTimer?.cancel()
            let timer = DispatchWorkItem {
                // Timeout — store as single click
                saveMouse(
                    button: button,
                    modifiers: NSEvent.ModifierFlags(rawValue: pendingMouseModifiers),
                    doubleClick: false
                )
                pendingMouseButton = nil
            }
            doubleClickTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: timer)

            return nil
        }
    }

    private func saveMouse(button: Int, modifiers: NSEvent.ModifierFlags, doubleClick: Bool) {
        let prefs = Preferences.shared
        switch slot {
        case .primary:
            prefs.primaryType = "mouse"
            prefs.primaryMouseButton = button
            prefs.primaryModifiers = modifiers.rawValue
            prefs.primaryDoubleClick = doubleClick
        case .alt:
            prefs.altType = "mouse"
            prefs.altMouseButton = button
            prefs.altModifiers = modifiers.rawValue
            prefs.altDoubleClick = doubleClick
        }

        stopRecording()
        updateDisplayText()
        NotificationCenter.default.post(name: .triggerChanged, object: nil)
    }

    private func stopRecording() {
        isRecording = false
        doubleClickTimer?.cancel()
        doubleClickTimer = nil
        pendingMouseButton = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        keyMonitor = nil
        mouseMonitor = nil
    }

    private func updateDisplayText() {
        let prefs = Preferences.shared
        switch slot {
        case .primary:
            displayText = Self.triggerDisplayString(
                type: prefs.primaryType,
                keyCode: prefs.primaryKeyCode,
                modifiers: prefs.primaryModifiers,
                mouseButton: prefs.primaryMouseButton,
                doubleClick: prefs.primaryDoubleClick
            )
        case .alt:
            displayText = Self.triggerDisplayString(
                type: prefs.altType,
                keyCode: prefs.altKeyCode,
                modifiers: prefs.altModifiers,
                mouseButton: prefs.altMouseButton,
                doubleClick: prefs.altDoubleClick
            )
        }
    }

    static func triggerDisplayString(
        type: String, keyCode: UInt32, modifiers: UInt,
        mouseButton: Int, doubleClick: Bool
    ) -> String {
        let mods = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }

        if type == "keyboard" {
            parts.append(keyName(for: keyCode))
            return parts.joined()
        } else {
            if doubleClick { parts.append("Double") }
            parts.append(mouseButtonName(for: mouseButton))
            return parts.joined(separator: " ")
        }
    }

    private static func mouseButtonName(for button: Int) -> String {
        switch button {
        case 2: return "Middle Click"
        case 3: return "Side Button 1"
        case 4: return "Side Button 2"
        default: return "Mouse Button \(button)"
        }
    }

    private static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x25: "L", 0x26: "J", 0x28: "K", 0x2C: "/", 0x2D: "N",
            0x2E: "M", 0x2F: ".", 0x31: "Space", 0x24: "Return",
            0x30: "Tab", 0x33: "Delete", 0x35: "Esc",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
            0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let triggerChanged = Notification.Name("WhisperKeyTriggerChanged")
}
