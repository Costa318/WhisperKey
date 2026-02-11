import AVFAudio
import AVFoundation
import ApplicationServices
import AppKit
import Observation

@Observable
final class PermissionManager {
    var microphoneGranted = false
    var microphoneDenied = false
    var accessibilityGranted = false

    private var pollTimer: Timer?
    private var micPollTimer: Timer?

    init() {
        checkMicrophoneStatus()
        checkAccessibilityStatus()
    }

    func checkMicrophoneStatus() {
        let permission = AVAudioApplication.shared.recordPermission
        microphoneGranted = permission == .granted
        microphoneDenied = permission == .denied
    }

    func requestMicrophoneAccess() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.microphoneGranted = granted
                self?.microphoneDenied = !granted
            }
        }
    }

    func startPollingMicrophone() {
        micPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
            [weak self] _ in
            self?.checkMicrophoneStatus()
        }
    }

    func stopPollingMicrophone() {
        micPollTimer?.invalidate()
        micPollTimer = nil
    }

    func checkAccessibilityStatus() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        if let url = URL(
            string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(
            string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    func startPollingAccessibility() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkAccessibilityStatus()
        }
    }

    func stopPollingAccessibility() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
