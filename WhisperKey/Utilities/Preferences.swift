import AppKit
import Foundation
import Observation

@Observable
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    // MARK: - General

    var language: String { didSet { defaults.set(language, forKey: "language") } }
    var autoPaste: Bool { didSet { defaults.set(autoPaste, forKey: "autoPaste") } }
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }
    var soundFeedback: Bool { didSet { defaults.set(soundFeedback, forKey: "soundFeedback") } }

    // MARK: - Primary Trigger (default: ⌃⌥Y keyboard)

    /// "keyboard" or "mouse"
    var primaryType: String { didSet { defaults.set(primaryType, forKey: "primaryType") } }
    /// Carbon virtual key code (keyboard triggers)
    var primaryKeyCode: UInt32 { didSet { defaults.set(primaryKeyCode, forKey: "primaryKeyCode") } }
    /// Raw NSEvent.ModifierFlags value (both keyboard and mouse triggers)
    var primaryModifiers: UInt { didSet { defaults.set(primaryModifiers, forKey: "primaryModifiers") } }
    /// CGEvent button number: 2=middle, 3=back, 4=forward (mouse triggers)
    var primaryMouseButton: Int { didSet { defaults.set(primaryMouseButton, forKey: "primaryMouseButton") } }
    /// Require double-click (mouse triggers)
    var primaryDoubleClick: Bool { didSet { defaults.set(primaryDoubleClick, forKey: "primaryDoubleClick") } }

    // MARK: - Alternative Trigger (default: double middle click)

    var altEnabled: Bool { didSet { defaults.set(altEnabled, forKey: "altEnabled") } }
    /// "keyboard" or "mouse"
    var altType: String { didSet { defaults.set(altType, forKey: "altType") } }
    var altKeyCode: UInt32 { didSet { defaults.set(altKeyCode, forKey: "altKeyCode") } }
    var altModifiers: UInt { didSet { defaults.set(altModifiers, forKey: "altModifiers") } }
    var altMouseButton: Int { didSet { defaults.set(altMouseButton, forKey: "altMouseButton") } }
    var altDoubleClick: Bool { didSet { defaults.set(altDoubleClick, forKey: "altDoubleClick") } }

    // MARK: - Advanced

    var whisperCLIPath: String { didSet { defaults.set(whisperCLIPath, forKey: "whisperCLIPath") } }
    var modelPath: String { didSet { defaults.set(modelPath, forKey: "modelPath") } }
    var threadCount: Int { didSet { defaults.set(threadCount, forKey: "threadCount") } }
    var maxRecordingDuration: TimeInterval {
        didSet { defaults.set(maxRecordingDuration, forKey: "maxRecordingDuration") }
    }

    // MARK: - Default Paths

    static let defaultWhisperCLIPath: String = {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.whisperkey/bin/whisper-cli"
    }()

    static let defaultModelPath: String = {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.whisperkey/models/ggml-medium.bin"
    }()

    // MARK: - Init

    private init() {
        defaults.register(defaults: [
            "language": "auto",
            "autoPaste": true,
            "launchAtLogin": false,
            "soundFeedback": false,
            // Primary trigger: ⌃⌥Y (keyboard) — control modifier required because
            // single-modifier ⌥+letter combos are claimed by macOS text input on
            // non-US layouts (e.g. ⌥Y → "›" on German), bypassing Carbon hotkey dispatch.
            "primaryType": "keyboard",
            "primaryKeyCode": 0x10,  // Y
            "primaryModifiers": NSEvent.ModifierFlags([.control, .option]).rawValue,
            "primaryMouseButton": 2,
            "primaryDoubleClick": false,
            // Alternative trigger: double middle click (mouse)
            "altEnabled": true,
            "altType": "mouse",
            "altKeyCode": 0x31,
            "altModifiers": 0,
            "altMouseButton": 2,  // middle click
            "altDoubleClick": true,
            // Advanced
            "whisperCLIPath": Self.defaultWhisperCLIPath,
            "modelPath": Self.defaultModelPath,
            "threadCount": 4,
            "maxRecordingDuration": 300.0,
        ])

        language = defaults.string(forKey: "language") ?? "auto"
        autoPaste = defaults.bool(forKey: "autoPaste")
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        soundFeedback = defaults.bool(forKey: "soundFeedback")

        primaryType = defaults.string(forKey: "primaryType") ?? "keyboard"
        primaryKeyCode = defaults.object(forKey: "primaryKeyCode") as? UInt32 ?? 0x10
        primaryModifiers = defaults.object(forKey: "primaryModifiers") as? UInt
            ?? NSEvent.ModifierFlags.option.rawValue
        primaryMouseButton = defaults.object(forKey: "primaryMouseButton") as? Int ?? 2
        primaryDoubleClick = defaults.bool(forKey: "primaryDoubleClick")

        altEnabled = defaults.object(forKey: "altEnabled") as? Bool ?? true
        altType = defaults.string(forKey: "altType") ?? "mouse"
        altKeyCode = defaults.object(forKey: "altKeyCode") as? UInt32 ?? 0x31
        altModifiers = defaults.object(forKey: "altModifiers") as? UInt ?? 0
        altMouseButton = defaults.object(forKey: "altMouseButton") as? Int ?? 2
        altDoubleClick = defaults.object(forKey: "altDoubleClick") as? Bool ?? true

        whisperCLIPath = defaults.string(forKey: "whisperCLIPath") ?? Self.defaultWhisperCLIPath
        modelPath = defaults.string(forKey: "modelPath") ?? Self.defaultModelPath
        threadCount = max(1, defaults.integer(forKey: "threadCount"))
        let dur = defaults.double(forKey: "maxRecordingDuration")
        maxRecordingDuration = dur > 0 ? dur : 300
    }

    // MARK: - Migration

    /// Migrate old hotkeyKeyCode/hotkeyModifiers to new primary trigger format.
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        // If old keys exist and new keys don't, migrate
        if defaults.object(forKey: "hotkeyKeyCode") != nil,
            defaults.object(forKey: "primaryType") == nil
        {
            let keyCode = defaults.object(forKey: "hotkeyKeyCode") as? UInt32 ?? 0x10
            let modifiers = defaults.object(forKey: "hotkeyModifiers") as? UInt
                ?? NSEvent.ModifierFlags.option.rawValue
            defaults.set("keyboard", forKey: "primaryType")
            defaults.set(keyCode, forKey: "primaryKeyCode")
            defaults.set(modifiers, forKey: "primaryModifiers")
            // Clean up old keys
            defaults.removeObject(forKey: "hotkeyKeyCode")
            defaults.removeObject(forKey: "hotkeyModifiers")
        }
    }
}
