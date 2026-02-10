import AVFoundation
import ApplicationServices
import AppKit
import Observation

@Observable
final class PermissionManager {
    var microphoneGranted = false
    var accessibilityGranted = false

    private var pollTimer: Timer?

    init() {
        checkMicrophoneStatus()
        checkAccessibilityStatus()
    }

    func checkMicrophoneStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        default:
            microphoneGranted = false
        }
    }

    func requestMicrophoneAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
            microphoneGranted = granted
        }
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
