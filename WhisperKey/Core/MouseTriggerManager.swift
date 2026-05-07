import AppKit
import ApplicationServices

/// Marker stamped onto our own replayed events via a private CGEventSource so
/// the callback can recognize them and let them through unchanged. Without it,
/// a posted DOWN re-enters the tap and gets re-suppressed, leaving pendingButton
/// permanently set and turning every later click into a phantom "second click".
private let replayUserDataMarker: Int64 = 0x57484B5F52504C59  // "WHK_RPLY"

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

    /// Private event source used for replays — marked via userData so the callback
    /// can identify our own posted events and avoid intercepting them.
    private lazy var replaySource: CGEventSource? = {
        let source = CGEventSource(stateID: .privateState)
        source?.userData = replayUserDataMarker
        return source
    }()

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

    /// Synthesize a DOWN+UP at the cursor's *current* position using the marked
    /// replaySource. We don't reuse the saved CGEvent because its source is the
    /// user's HID (userData=0) and posting it would re-enter our own callback as
    /// an indistinguishable user click — re-suppressing it and leaving pendingButton
    /// set forever.
    func replayPendingClickAtCurrentCursor() {
        guard let savedEvent = pendingEvent else { return }
        let buttonNumber = Int(savedEvent.getIntegerValueField(.mouseEventButtonNumber))
        let flags = savedEvent.flags
        let location = CGEvent(source: nil)?.location ?? savedEvent.location

        // CGEvent's mouseButton parameter rejects values > .center (2). For high
        // button numbers (3=back, 4=forward) we pass .left as a placeholder and
        // override mouseEventButtonNumber, which is what apps actually read for
        // "other" mouse events.
        let baseButton: CGMouseButton =
            CGMouseButton(rawValue: UInt32(buttonNumber)) ?? .left

        func post(_ type: CGEventType) {
            guard
                let event = CGEvent(
                    mouseEventSource: replaySource,
                    mouseType: type,
                    mouseCursorPosition: location,
                    mouseButton: baseButton
                )
            else { return }
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(buttonNumber))
            event.flags = flags
            event.post(tap: .cgSessionEventTap)
        }

        post(.otherMouseDown)
        post(.otherMouseUp)
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

    // Pass through our own replayed events (identified by the userData marker on
    // their CGEventSource) without any further processing, otherwise they re-enter
    // the suppression logic and lock pendingButton forever.
    if event.getIntegerValueField(.eventSourceUserData) == replayUserDataMarker {
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
