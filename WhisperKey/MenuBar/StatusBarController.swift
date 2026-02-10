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
        switch state {
        case .idle, .setup:
            statusMenuItem.title = "Press ⌥Space to record"
            setIcon(name: "waveform", isTemplate: true)
        case .recording:
            statusMenuItem.title = "Recording... Press ⌥Space to stop"
            setIcon(name: "waveform", tintColor: .systemRed)
        case .transcribing:
            statusMenuItem.title = "Transcribing..."
            setIcon(name: "ellipsis.circle", isTemplate: true)
        }
    }

    private func setIcon(name: String, isTemplate: Bool = false, tintColor: NSColor? = nil) {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: "WhisperKey")
        else { return }

        if let tintColor {
            let colored = image.withSymbolConfiguration(config)
            button.image = colored
            button.contentTintColor = tintColor
        } else {
            let img = image.withSymbolConfiguration(config)
            img?.isTemplate = isTemplate
            button.image = img
            button.contentTintColor = nil
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
