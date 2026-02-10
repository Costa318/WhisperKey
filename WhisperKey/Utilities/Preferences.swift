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
            "whisperCLIPath": Self.defaultWhisperCLIPath,
            "modelPath": Self.defaultModelPath,
            "threadCount": 4,
            "maxRecordingDuration": 300.0,
        ])

        language = defaults.string(forKey: "language") ?? "auto"
        autoPaste = defaults.bool(forKey: "autoPaste")
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        soundFeedback = defaults.bool(forKey: "soundFeedback")
        whisperCLIPath = defaults.string(forKey: "whisperCLIPath") ?? Self.defaultWhisperCLIPath
        modelPath = defaults.string(forKey: "modelPath") ?? Self.defaultModelPath
        threadCount = max(1, defaults.integer(forKey: "threadCount"))
        let dur = defaults.double(forKey: "maxRecordingDuration")
        maxRecordingDuration = dur > 0 ? dur : 300
    }
}
