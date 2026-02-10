import ServiceManagement
import SwiftUI

struct FirstLaunchView: View {
    @State private var currentStep = 0
    @State private var setupManager = SetupManager()
    @State private var permissionManager = PermissionManager()

    var body: some View {
        VStack(spacing: 0) {
            StepIndicator(currentStep: currentStep, totalSteps: 5)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)

            Divider()

            Group {
                switch currentStep {
                case 0:
                    WelcomeStepView { currentStep = 1 }
                case 1:
                    PrerequisitesStepView(
                        setupManager: setupManager,
                        onNext: { currentStep = 2 },
                        onBack: { currentStep = 0 }
                    )
                case 2:
                    InstallStepView(
                        setupManager: setupManager,
                        onNext: { currentStep = 3 },
                        onBack: { currentStep = 1 }
                    )
                case 3:
                    PermissionsStepView(
                        permissionManager: permissionManager,
                        onNext: { currentStep = 4 },
                        onBack: { currentStep = 2 }
                    )
                case 4:
                    ReadyStepView(onFinish: finishSetup)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        }
        .frame(width: 600, height: 500)
    }

    private func finishSetup() {
        NotificationCenter.default.post(name: .whisperKeySetupCompleted, object: nil)
    }
}

// MARK: - Step Indicator

private struct StepIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)

                if step < totalSteps - 1 {
                    Rectangle()
                        .fill(step < currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStepView: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Welcome to WhisperKey")
                .font(.largeTitle.bold())

            VStack(spacing: 8) {
                Text("WhisperKey transcribes your speech locally on your Mac.")
                Text("Nothing is sent to the cloud.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Text(
                "To get started, WhisperKey needs to download and set up a speech recognition engine. This is a one-time process."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 400)

            Spacer()

            Button("Get Started") { onNext() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
    }
}

// MARK: - Step 2: Prerequisites

private struct PrerequisitesStepView: View {
    let setupManager: SetupManager
    let onNext: () -> Void
    let onBack: () -> Void

    @State private var checking = true
    @State private var installed = false
    @State private var polling = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if checking {
                ProgressView()
                    .controlSize(.large)
                Text("Checking for build tools...")
                    .font(.title3)
            } else if installed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Build tools found")
                    .font(.title3)
            } else {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)

                Text("Build Tools Required")
                    .font(.title3.bold())

                Text(
                    "WhisperKey needs Apple's Command Line Tools to compile the speech engine."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

                Button("Install Build Tools") {
                    setupManager.installXcodeCommandLineTools()
                    polling = true
                    startPolling()
                }
                .controlSize(.large)

                if polling {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for installation to complete...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            HStack {
                Button("Back") { onBack() }
                Spacer()
            }
        }
        .onAppear { checkPrerequisites() }
    }

    private func checkPrerequisites() {
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            installed = setupManager.xcodeCommandLineToolsInstalled
            checking = false

            if installed {
                try? await Task.sleep(for: .seconds(1))
                onNext()
            }
        }
    }

    private func startPolling() {
        Task {
            while !installed {
                try? await Task.sleep(for: .seconds(3))
                installed = setupManager.xcodeCommandLineToolsInstalled
            }
            try? await Task.sleep(for: .seconds(1))
            onNext()
        }
    }
}

// MARK: - Step 3: Installation

private struct InstallStepView: View {
    @Bindable var setupManager: SetupManager
    let onNext: () -> Void
    let onBack: () -> Void

    @State private var showLog = false

    var body: some View {
        VStack(spacing: 20) {
            if setupManager.installationComplete {
                completedView
            } else if setupManager.error != nil {
                errorView
            } else if setupManager.isInstalling {
                progressView
            } else {
                readyToInstallView
            }
        }
    }

    private var completedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Installation complete!")
                .font(.title3.bold())
            Spacer()
            HStack {
                Spacer()
                Button("Continue") { onNext() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(2))
                onNext()
            }
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)
            Text("Installation failed")
                .font(.title3.bold())
            Text(setupManager.error ?? "Unknown error")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            logView

            Spacer()
            HStack {
                Button("Back") { onBack() }
                Spacer()
                Button("Retry") {
                    Task { await setupManager.startInstallation() }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
    }

    private var progressView: some View {
        VStack(spacing: 16) {
            Spacer()

            if let step = setupManager.currentStep {
                Text("\(step.stepLabel): \(step.description)")
                    .font(.headline)

                if step == .downloadingModel, setupManager.totalBytes > 0 {
                    ProgressView(value: setupManager.downloadProgress)
                        .frame(maxWidth: 400)
                    Text(
                        "\(formatBytes(setupManager.downloadedBytes)) / \(formatBytes(setupManager.totalBytes))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
            }

            logView

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { setupManager.cancel() }
            }
        }
    }

    private var readyToInstallView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Install Speech Engine")
                .font(.title3.bold())

            VStack(spacing: 4) {
                Text("WhisperKey will download and compile the speech recognition engine.")
                Text("This requires about 2 GB of disk space.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .multilineTextAlignment(.center)

            if !setupManager.checkDiskSpace() {
                Label(
                    "Low disk space. At least 3 GB of free space is recommended.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .font(.callout)
            }

            Spacer()

            HStack {
                Button("Back") { onBack() }
                Spacer()
                Button("Install") {
                    Task { await setupManager.startInstallation() }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
    }

    private var logView: some View {
        DisclosureGroup("Show Details", isExpanded: $showLog) {
            ScrollView {
                Text(setupManager.logOutput)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 120)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(maxWidth: 450)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Step 4: Permissions

private struct PermissionsStepView: View {
    @Bindable var permissionManager: PermissionManager
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Permissions")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 20) {
                // Microphone
                HStack(spacing: 16) {
                    Image(
                        systemName: permissionManager.microphoneGranted
                            ? "checkmark.circle.fill" : "mic.fill"
                    )
                    .font(.title2)
                    .foregroundStyle(permissionManager.microphoneGranted ? Color.green : Color.accentColor)
                    .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Microphone")
                            .font(.headline)
                        if permissionManager.microphoneGranted {
                            Text("Microphone access granted")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text("Required for recording speech")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if !permissionManager.microphoneGranted {
                        Button("Grant Access") {
                            Task { await permissionManager.requestMicrophoneAccess() }
                        }
                    }
                }

                Divider()

                // Accessibility
                HStack(spacing: 16) {
                    Image(
                        systemName: permissionManager.accessibilityGranted
                            ? "checkmark.circle.fill" : "accessibility"
                    )
                    .font(.title2)
                    .foregroundStyle(permissionManager.accessibilityGranted ? Color.green : Color.accentColor)
                    .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility")
                            .font(.headline)
                        if permissionManager.accessibilityGranted {
                            Text("Auto-paste enabled")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text(
                                "Optional — allows auto-pasting transcriptions into your active app"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if !permissionManager.accessibilityGranted {
                        Button("Enable Auto-Paste") {
                            permissionManager.openAccessibilitySettings()
                        }
                    }
                }

                if !permissionManager.microphoneGranted {
                    Label(
                        "WhisperKey cannot work without microphone access.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            HStack {
                Button("Back") { onBack() }
                Spacer()
                if !permissionManager.accessibilityGranted && permissionManager.microphoneGranted {
                    Button("Skip — I'll just use clipboard") { onNext() }
                        .foregroundStyle(.secondary)
                }
                Button("Continue") { onNext() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(!permissionManager.microphoneGranted)
            }
        }
        .onAppear {
            permissionManager.startPollingAccessibility()
        }
        .onDisappear {
            permissionManager.stopPollingAccessibility()
        }
    }
}

// MARK: - Step 5: Ready

private struct ReadyStepView: View {
    let onFinish: () -> Void

    @State private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("You're all set!")
                .font(.largeTitle.bold())

            VStack(spacing: 8) {
                Text("WhisperKey is now in your menu bar.")
                    .font(.title3)
                Text("Press **⌥ Space** to start recording. Press again to stop and transcribe.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Toggle("Launch WhisperKey at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)

            Spacer()

            Button("Start Using WhisperKey") {
                applyLaunchAtLogin()
                onFinish()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
    }

    private func applyLaunchAtLogin() {
        Preferences.shared.launchAtLogin = launchAtLogin
        if #available(macOS 13.0, *) {
            if launchAtLogin {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }
}
