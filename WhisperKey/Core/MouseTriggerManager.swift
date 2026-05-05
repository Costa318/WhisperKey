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
    /// Buttons whose next mouseUp must be swallowed to balance a suppressed mouseDown.
    var suppressNextUp: Set<Int> = []

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
        suppressNextUp.removeAll()

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

    /// Replay the saved first-click DOWN at the cursor's *current* position, then
    /// synthesize a matching UP. Posting the saved event at its original location
    /// would warp the cursor back to where the click happened.
    func replayPendingClickAtCurrentCursor() {
        guard let savedEvent = pendingEvent else { return }
        let buttonNumber = Int(savedEvent.getIntegerValueField(.mouseEventButtonNumber))
        let location = CGEvent(source: nil)?.location ?? savedEvent.location

        savedEvent.location = location
        savedEvent.post(tap: .cgSessionEventTap)

        if let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseUp,
            mouseCursorPosition: location,
            mouseButton: CGMouseButton(rawValue: UInt32(buttonNumber)) ?? .center
        ) {
            upEvent.setIntegerValueField(.mouseEventButtonNumber, value: Int64(buttonNumber))
            upEvent.post(tap: .cgSessionEventTap)
        }
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
    let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))

    // Swallow UPs paired with previously-suppressed DOWNs to keep event sequencing balanced.
    if type == .otherMouseUp {
        if manager.suppressNextUp.remove(buttonNumber) != nil {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .otherMouseDown else {
        return Unmanaged.passUnretained(event)
    }

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
        // Simple single-click trigger — fire immediately and swallow (DOWN + paired UP)
        manager.suppressNextUp.insert(buttonNumber)
        manager.fireTrigger()
        return nil
    }

    // Double-click detection
    let now = CFAbsoluteTimeGetCurrent()
    let interval = NSEvent.doubleClickInterval

    if manager.pendingButton == buttonNumber,
        (now - manager.pendingTimestamp) < interval
    {
        // Second click within interval — fire trigger, swallow this DOWN and its UP
        manager.doubleClickTimer?.cancel()
        manager.doubleClickTimer = nil
        manager.pendingButton = nil
        manager.pendingEvent = nil
        manager.suppressNextUp.insert(buttonNumber)
        manager.fireTrigger()
        return nil
    }

    // First click — suppress (both DOWN and the paired UP) and wait for a possible second click
    manager.pendingButton = buttonNumber
    manager.pendingTimestamp = now
    manager.pendingEvent = event.copy()
    manager.suppressNextUp.insert(buttonNumber)

    manager.doubleClickTimer?.cancel()
    let timer = DispatchWorkItem { [weak manager] in
        guard let manager = manager else { return }
        // Timeout — replay the click at the cursor's *current* position
        // (replaying the saved event at its original location would warp the cursor back).
        manager.replayPendingClickAtCurrentCursor()
        manager.pendingButton = nil
        manager.pendingEvent = nil
        // Leave suppressNextUp set: if the user is still holding the button,
        // their eventual real UP must still be swallowed (we already posted our own UP).
        // If the user already released, the flag was cleared when that UP arrived.
    }
    manager.doubleClickTimer = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: timer)

    return nil  // suppress first click while waiting
}
