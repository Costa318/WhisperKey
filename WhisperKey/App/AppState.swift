import Foundation
import Observation

@Observable
final class AppState {
    static let shared = AppState()

    enum Status {
        case setup
        case idle
        case recording
        case transcribing
    }

    var status: Status = .idle

    let baseDirectory: String
    let whisperCLIPath: String
    let modelPath: String

    var needsSetup: Bool {
        !FileManager.default.fileExists(atPath: whisperCLIPath)
            || !FileManager.default.fileExists(atPath: modelPath)
    }

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        baseDirectory = "\(home)/.whisperkey"
        whisperCLIPath = "\(baseDirectory)/bin/whisper-cli"
        modelPath = "\(baseDirectory)/models/ggml-medium.bin"
    }
}
