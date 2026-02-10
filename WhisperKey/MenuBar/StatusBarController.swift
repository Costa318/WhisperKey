import AppKit
import ServiceManagement

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let statusMenuItem: NSMenuItem
    private let launchAtLoginItem: NSMenuItem

    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        statusMenuItem = NSMenuItem(
            title: "Press ⌥Space to record", action: nil, keyEquivalent: "")
        launchAtLoginItem = NSMenuItem(
            title: "Launch at Login", action: nil, keyEquivalent: "")

        setupMenu()
        updateForState(.idle)
    }

    private func setupMenu() {
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...", action: #selector(settingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        launchAtLoginItem.state = Preferences.shared.launchAtLogin ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit WhisperKey", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func updateForState(_ state: AppState.Status) {
        guard let button = statusItem.button else { return }

        switch state {
        case .idle, .setup:
            statusMenuItem.title = "Press ⌥Space to record"
            setCustomIcon(on: button)
        case .recording:
            statusMenuItem.title = "Recording... Press ⌥Space to stop"
            setCustomIcon(on: button, tintColor: .systemRed)
        case .transcribing:
            statusMenuItem.title = "Transcribing..."
            setCustomIcon(on: button, tintColor: .systemOrange)
        }
    }

    private func setCustomIcon(on button: NSStatusBarButton, tintColor: NSColor? = nil) {
        guard let baseImage = NSImage(named: "MenuBarIcon") else { return }

        if let tintColor {
            // Bake color into pixels so macOS can't override it
            let colored = NSImage(size: baseImage.size, flipped: false) { rect in
                baseImage.draw(in: rect)
                tintColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            colored.isTemplate = false
            button.image = colored
        } else {
            baseImage.isTemplate = true
            button.image = baseImage
        }
    }

    @objc private func settingsClicked() {
        onSettings?()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let prefs = Preferences.shared
        prefs.launchAtLogin.toggle()
        sender.state = prefs.launchAtLogin ? .on : .off

        if prefs.launchAtLogin {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }
}
