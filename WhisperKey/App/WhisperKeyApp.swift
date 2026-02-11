import AVFoundation
import SwiftUI
import UserNotifications

@main
struct WhisperKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar-only app — all UI managed via AppDelegate + NSStatusItem.
        // This Settings scene satisfies the SwiftUI App protocol but is never auto-opened.
        Settings {
            SettingsView()
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var hotkeyManager: HotkeyManager!
    private var audioRecorder: AudioRecorder!
    private var transcriber: WhisperTranscriber!
    private var outputManager: OutputManager!

    private var setupWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

        // Menu bar
        statusBar = StatusBarController()
        statusBar.onSettings = { [weak self] in self?.showSettings() }

        // Core
        audioRecorder = AudioRecorder()
        transcriber = WhisperTranscriber()
        outputManager = OutputManager()

        audioRecorder.onMaxDurationReached = { [weak self] in
            DispatchQueue.main.async { self?.stopRecordingAndTranscribe() }
        }

        // Hotkey
        hotkeyManager = HotkeyManager()
        hotkeyManager.onHotkeyPressed = { [weak self] in self?.handleHotkey() }

        if AppState.shared.needsSetup {
            // Become a regular foreground app during setup so macOS shows
            // TCC permission dialogs (LSUIElement/accessory apps can't trigger them).
            NSApp.setActivationPolicy(.regular)
            showSetupWizard()
        } else {
            hotkeyManager.register()
            checkMicrophonePermission()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(setupDidComplete),
            name: .whisperKeySetupCompleted, object: nil
        )

        NotificationCenter.default.addObserver(
            self, selector: #selector(hotkeyDidChange),
            name: .hotkeyChanged, object: nil
        )
    }

    // MARK: - Hotkey Flow

    private func handleHotkey() {
        switch AppState.shared.status {
        case .idle:
            startRecording()
        case .recording:
            stopRecordingAndTranscribe()
        case .transcribing, .setup:
            break
        }
    }

    private func startRecording() {
        let permission = AVAudioApplication.shared.recordPermission
        guard permission == .granted else {
            if permission == .undetermined {
                AVAudioApplication.requestRecordPermission { _ in }
                postNotification("Please grant microphone access and try again.")
            } else {
                postNotification("Microphone access denied. Enable it in System Settings.")
            }
            return
        }

        do {
            try audioRecorder.startRecording()
            AppState.shared.status = .recording
            statusBar.updateForState(.recording)

            if Preferences.shared.soundFeedback {
                NSSound(named: .init("Tink"))?.play()
            }
        } catch {
            AppState.shared.status = .idle
            statusBar.updateForState(.idle)
            postNotification("Failed to start recording: \(error.localizedDescription)")
        }
    }

    private func stopRecordingAndTranscribe() {
        let result = audioRecorder.stopRecording()

        switch result {
        case .tooShort:
            AppState.shared.status = .idle
            statusBar.updateForState(.idle)
            postNotification("Recording too short")

        case .success(let url):
            AppState.shared.status = .transcribing
            statusBar.updateForState(.transcribing)

            if Preferences.shared.soundFeedback {
                NSSound(named: .init("Tink"))?.play()
            }

            Task {
                do {
                    let result = try await transcriber.transcribe(audioURL: url)
                    await MainActor.run {
                        outputManager.output(text: result.text)
                        AppState.shared.status = .idle
                        statusBar.updateForState(.idle)
                    }
                } catch {
                    await MainActor.run {
                        AppState.shared.status = .idle
                        statusBar.updateForState(.idle)
                        postNotification(error.localizedDescription)
                    }
                }
            }
        }
    }

    // MARK: - Setup Wizard

    func showSetupWizard() {
        AppState.shared.status = .setup
        statusBar.updateForState(.setup)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WhisperKey Setup"
        window.contentView = NSHostingView(rootView: FirstLaunchView())
        window.center()
        window.isReleasedWhenClosed = false

        setupWindowController = NSWindowController(window: window)
        setupWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func setupDidComplete() {
        setupWindowController?.close()
        setupWindowController = nil
        // Switch back to menu-bar-only (accessory) mode now that setup is done
        NSApp.setActivationPolicy(.accessory)
        AppState.shared.status = .idle
        statusBar.updateForState(.idle)
        hotkeyManager.register()
        checkMicrophonePermission()
    }

    @objc private func hotkeyDidChange() {
        hotkeyManager.reregister()
    }

    // MARK: - Settings

    private func showSettings() {
        if settingsWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "WhisperKey Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Permissions

    private func checkMicrophonePermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            let alert = NSAlert()
            alert.messageText = "Microphone Access Required"
            alert.informativeText =
                "WhisperKey needs microphone access to work. Enable it in System Settings."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Dismiss")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(
                    string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                ) {
                    NSWorkspace.shared.open(url)
                }
            }
        default:
            break
        }
    }

    // MARK: - Helpers

    private func postNotification(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "WhisperKey"
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let whisperKeySetupCompleted = Notification.Name("WhisperKeySetupCompleted")
}
