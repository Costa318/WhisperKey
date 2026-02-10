import AppKit
import HotKey

final class HotkeyManager {
    private var hotKey: HotKey?
    var onHotkeyPressed: (() -> Void)?

    func register() {
        let prefs = Preferences.shared
        guard let key = Key(carbonKeyCode: prefs.hotkeyKeyCode) else { return }
        let modifiers = NSEvent.ModifierFlags(rawValue: prefs.hotkeyModifiers)
            .intersection([.command, .option, .control, .shift])

        hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey?.keyDownHandler = { [weak self] in
            self?.onHotkeyPressed?()
        }
    }

    func unregister() {
        hotKey = nil
    }

    func reregister() {
        unregister()
        register()
    }
}
