import AppKit
import HotKey

final class HotkeyManager {
    private var primaryHotKey: HotKey?
    private var altHotKey: HotKey?
    var onHotkeyPressed: (() -> Void)?

    func register() {
        unregister()
        let prefs = Preferences.shared

        // Primary trigger (keyboard)
        if prefs.primaryType == "keyboard" {
            if let key = Key(carbonKeyCode: prefs.primaryKeyCode) {
                let modifiers = NSEvent.ModifierFlags(rawValue: prefs.primaryModifiers)
                    .intersection([.command, .option, .control, .shift])
                primaryHotKey = HotKey(key: key, modifiers: modifiers)
                primaryHotKey?.keyDownHandler = { [weak self] in
                    self?.onHotkeyPressed?()
                }
            }
        }

        // Alternative trigger (keyboard)
        if prefs.altEnabled && prefs.altType == "keyboard" {
            if let key = Key(carbonKeyCode: prefs.altKeyCode) {
                let modifiers = NSEvent.ModifierFlags(rawValue: prefs.altModifiers)
                    .intersection([.command, .option, .control, .shift])
                altHotKey = HotKey(key: key, modifiers: modifiers)
                altHotKey?.keyDownHandler = { [weak self] in
                    self?.onHotkeyPressed?()
                }
            }
        }
    }

    func unregister() {
        primaryHotKey = nil
        altHotKey = nil
    }

    func reregister() {
        unregister()
        register()
    }
}
