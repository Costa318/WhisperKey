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
        .frame(width: 460, height: 320)
        .fixedSize()
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Record / Stop:")
                    HotkeyRecorderView()
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

// MARK: - Hotkey Recorder

private struct HotkeyRecorderView: View {
    @State private var isRecording = false
    @State private var displayText: String = ""
    @State private var monitor: Any?

    var body: some View {
        Button(action: { startRecording() }) {
            Text(isRecording ? "Press shortcut..." : displayText)
                .frame(minWidth: 100)
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

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Escape cancels
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

            // Require at least one modifier key
            guard !modifiers.isEmpty else { return nil }

            let prefs = Preferences.shared
            prefs.hotkeyKeyCode = UInt32(event.keyCode)
            prefs.hotkeyModifiers = modifiers.rawValue

            stopRecording()
            updateDisplayText()

            // Notify HotkeyManager to re-register
            NotificationCenter.default.post(name: .hotkeyChanged, object: nil)

            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func updateDisplayText() {
        let prefs = Preferences.shared
        let modifiers = NSEvent.ModifierFlags(rawValue: prefs.hotkeyModifiers)
        displayText = Self.hotkeyDisplayString(keyCode: prefs.hotkeyKeyCode, modifiers: modifiers)
    }

    static func hotkeyDisplayString(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined(separator: "")
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

extension Notification.Name {
    static let hotkeyChanged = Notification.Name("WhisperKeyHotkeyChanged")
}
