import AppKit
import ApplicationServices

final class MouseTriggerManager {
    var onTrigger: (() -> Void)?

    struct Config {
        let button: Int
        let doubleClick: Bool
        let modifiers: NSEvent.ModifierFlags
    }

    var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var configs: [Config] = []

    // Double-click detection state
    var pendingButton: Int?
    var pendingTimestamp: CFAbsoluteTime = 0
    var pendingEvent: CGEvent?
    var doubleClickTimer: DispatchWorkItem?

    private static let doubleClickInterval: CFAbsoluteTime = 0.3

    func start() {
        stop()

        guard !configs.isEmpty else { return }

        // Listen for otherMouseDown (buttons 2+) and otherMouseUp
        let mask = CGEventMask(
            (1 << CGEventType.otherMouseDown.rawValue)
                | (1 << CGEventType.otherMouseUp.rawValue)
        )

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: mouseEventCallback,
                userInfo: userInfo
            )
        else {
            print(
                "MouseTriggerManager: Failed to create event tap (Accessibility permission needed)")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        doubleClickTimer?.cancel()
        doubleClickTimer = nil
        pendingButton = nil
        pendingEvent = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

    func restart() {
        stop()
        loadFromPreferences()
        start()
    }

    func loadFromPreferences() {
        let prefs = Preferences.shared
        var newConfigs: [Config] = []

        if prefs.primaryType == "mouse" {
            newConfigs.append(
                Config(
                    button: prefs.primaryMouseButton,
                    doubleClick: prefs.primaryDoubleClick,
                    modifiers: NSEvent.ModifierFlags(rawValue: prefs.primaryModifiers)
                        .intersection([.command, .option, .control, .shift])
                ))
        }

        if prefs.altEnabled && prefs.altType == "mouse" {
            newConfigs.append(
                Config(
                    button: prefs.altMouseButton,
                    doubleClick: prefs.altDoubleClick,
                    modifiers: NSEvent.ModifierFlags(rawValue: prefs.altModifiers)
                        .intersection([.command, .option, .control, .shift])
                ))
        }

        configs = newConfigs
    }

    /// Called from the C callback when a matching event is detected.
    func fireTrigger() {
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?()
        }
    }

    /// Replay a suppressed click that turned out not to be a double-click.
    func replayEvent(_ event: CGEvent) {
        event.post(tap: .cgSessionEventTap)
    }
}

// MARK: - CGEvent Callback (free function required by C API)

private func mouseEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable tap if macOS disabled it
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let manager = Unmanaged<MouseTriggerManager>.fromOpaque(userInfo)
                .takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<MouseTriggerManager>.fromOpaque(userInfo).takeUnretainedValue()

    // Only handle otherMouseDown
    guard type == .otherMouseDown else {
        return Unmanaged.passUnretained(event)
    }

    let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
    let eventFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        .intersection([.command, .option, .control, .shift])

    // Find a matching config
    guard
        let config = manager.configs.first(where: {
            $0.button == buttonNumber && $0.modifiers == eventFlags
        })
    else {
        return Unmanaged.passUnretained(event)
    }

    if !config.doubleClick {
        // Simple single-click trigger — fire immediately and swallow
        manager.fireTrigger()
        return nil
    }

    // Double-click detection
    let now = CFAbsoluteTimeGetCurrent()

    if manager.pendingButton == buttonNumber,
        (now - manager.pendingTimestamp) < 0.3
    {
        // Second click within interval — fire trigger
        manager.doubleClickTimer?.cancel()
        manager.doubleClickTimer = nil
        manager.pendingButton = nil
        manager.pendingEvent = nil
        manager.fireTrigger()
        return nil  // swallow second click
    }

    // First click — suppress and wait for potential second click
    manager.pendingButton = buttonNumber
    manager.pendingTimestamp = now
    manager.pendingEvent = event.copy()

    manager.doubleClickTimer?.cancel()
    let timer = DispatchWorkItem { [weak manager] in
        guard let manager = manager else { return }
        // Timeout — no second click, replay the original
        if let savedEvent = manager.pendingEvent {
            manager.replayEvent(savedEvent)
        }
        manager.pendingButton = nil
        manager.pendingEvent = nil
    }
    manager.doubleClickTimer = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: timer)

    return nil  // suppress first click while waiting
}
