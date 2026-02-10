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
                    Text("⌥ Space")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .font(.system(.body, design: .monospaced))
                }
            }

            Section("Transcription") {
                Picker("Language", selection: $preferences.language) {
                    Text("Auto (recommended)").tag("auto")
                    Text("German").tag("de")
                    Text("English").tag("en")
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
