import AppKit
import ApplicationServices
import UserNotifications

final class OutputManager {
    private var hasPromptedForAccessibility = false

    func output(text: String) {
        // Always copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let trusted = AXIsProcessTrusted()
        let autoPaste = Preferences.shared.autoPaste

        if autoPaste && trusted {
            // Delay to ensure the previously active app regains focus after transcription
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.simulatePaste()
            }
        } else if autoPaste && !trusted && !hasPromptedForAccessibility {
            // Prompt once to grant Accessibility — opens System Settings
            hasPromptedForAccessibility = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            showNotification(text: text)
        } else {
            showNotification(text: text)
        }
    }

    private func simulatePaste() {
        guard let source = CGEventSource(stateID: .privateState) else { return }

        // Virtual key code 0x09 = V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func showNotification(text: String) {
        let center = UNUserNotificationCenter.current()

        // Request permission on first use (silent if already granted/denied)
        center.requestAuthorization(options: [.alert]) { _, _ in }

        let content = UNMutableNotificationContent()
        content.title = "WhisperKey"
        let preview = text.count > 80 ? String(text.prefix(80)) + "..." : text
        content.body = "\(preview) – Copied to clipboard"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
