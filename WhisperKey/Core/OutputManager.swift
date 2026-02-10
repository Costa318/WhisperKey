import AppKit
import ApplicationServices
import UserNotifications

final class OutputManager {
    func output(text: String) {
        // Always copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if Preferences.shared.autoPaste && AXIsProcessTrusted() {
            // Brief delay to ensure the previously active app regains focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.simulatePaste()
            }
        } else {
            showNotification(text: text)
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Virtual key code 0x09 = V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
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
