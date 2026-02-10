import HotKey

final class HotkeyManager {
    private var hotKey: HotKey?
    var onHotkeyPressed: (() -> Void)?

    func register() {
        hotKey = HotKey(key: .space, modifiers: [.option])
        hotKey?.keyDownHandler = { [weak self] in
            self?.onHotkeyPressed?()
        }
    }

    func unregister() {
        hotKey = nil
    }
}
