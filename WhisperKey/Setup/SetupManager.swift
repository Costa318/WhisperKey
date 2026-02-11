import Foundation
import Observation

@Observable
final class SetupManager {
    enum InstallStep: Int, CaseIterable {
        case creatingDirectories
        case cloningRepository
        case compiling
        case downloadingModel

        var description: String {
            switch self {
            case .creatingDirectories: "Creating directories..."
            case .cloningRepository: "Downloading whisper.cpp source code..."
            case .compiling: "Compiling whisper.cpp (this may take 1–2 minutes)..."
            case .downloadingModel: "Downloading speech model (~1.5 GB)..."
            }
        }

        var stepLabel: String {
            "Step \(rawValue + 1)/\(Self.allCases.count)"
        }
    }

    var currentStep: InstallStep?
    var isInstalling = false
    var installationComplete = false
    var error: String?
    var logOutput = ""

    // Download progress
    var downloadProgress: Double = 0
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0

    private var currentProcess: Process?
    private var modelDownloader: ModelDownloader?
    private let appState = AppState.shared

    // MARK: - Prerequisite Checks

    var xcodeCommandLineToolsInstalled: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func checkDiskSpace() -> Bool {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(
                forPath: NSHomeDirectory()
            )
            if let freeSpace = attrs[.systemFreeSize] as? Int64 {
                return freeSpace > 3_000_000_000
            }
        } catch {}
        return true
    }

    func installXcodeCommandLineTools() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]
        try? process.run()
    }

    /// Find cmake binary — check system paths, then temp build dir
    private func findCmakePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/cmake",
            "/usr/local/bin/cmake",
            "/Applications/CMake.app/Contents/bin/cmake",
            "/usr/bin/cmake",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Download cmake to temp build dir if not installed on system
    private static let cmakeVersion = "3.31.4"
    private static let cmakeDirName = "cmake-\(cmakeVersion)-macos-universal"
    private static let cmakeURL =
        "https://github.com/Kitware/CMake/releases/download/v\(cmakeVersion)/\(cmakeDirName).tar.gz"

    private func ensureCmake() async throws -> String {
        // Fast path: cmake already on the system
        if let systemCmake = findCmakePath() {
            await appendLog("Found cmake at \(systemCmake)")
            return systemCmake
        }

        // Download cmake as a temporary build tool
        await appendLog("cmake not found on system, downloading temporary copy...")
        let buildDir = "/tmp/whisperkey-build"
        let tarPath = "\(buildDir)/cmake.tar.gz"
        let cmakeBin = "\(buildDir)/\(Self.cmakeDirName)/CMake.app/Contents/bin/cmake"

        // Download
        try await runProcess(
            "/usr/bin/curl",
            arguments: ["-L", "-o", tarPath, Self.cmakeURL]
        )

        // Extract
        try await runProcess(
            "/usr/bin/tar",
            arguments: ["xzf", tarPath, "-C", buildDir]
        )

        // Clean up tarball
        try? FileManager.default.removeItem(atPath: tarPath)

        guard FileManager.default.isExecutableFile(atPath: cmakeBin) else {
            throw NSError(
                domain: "SetupManager", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to download cmake. Check your internet connection and try again."
                ])
        }

        await appendLog("Downloaded cmake \(Self.cmakeVersion)")
        return cmakeBin
    }

    // MARK: - Installation

    @MainActor
    func startInstallation() async {
        isInstalling = true
        error = nil
        logOutput = ""
        installationComplete = false

        do {
            currentStep = .creatingDirectories
            try await createDirectories()

            currentStep = .cloningRepository
            try await cloneRepository()

            currentStep = .compiling
            try await compileWhisperCpp()

            currentStep = .downloadingModel
            try await downloadModel()

            // Cleanup build artifacts
            try? FileManager.default.removeItem(atPath: "/tmp/whisperkey-build")

            installationComplete = true
        } catch {
            self.error = error.localizedDescription
            // Cleanup on failure
            try? FileManager.default.removeItem(atPath: "/tmp/whisperkey-build")
        }

        isInstalling = false
    }

    func cancel() {
        currentProcess?.terminate()
        modelDownloader?.cancel()
        isInstalling = false
        try? FileManager.default.removeItem(atPath: "/tmp/whisperkey-build")
    }

    // MARK: - Installation Steps

    private func createDirectories() async throws {
        let fm = FileManager.default
        try fm.createDirectory(
            atPath: "\(appState.baseDirectory)/bin",
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            atPath: "\(appState.baseDirectory)/models",
            withIntermediateDirectories: true
        )
        await appendLog("Created ~/.whisperkey/bin and ~/.whisperkey/models")
    }

    private func cloneRepository() async throws {
        // Clean up any previous build attempt
        let buildDir = "/tmp/whisperkey-build"
        if FileManager.default.fileExists(atPath: buildDir) {
            try FileManager.default.removeItem(atPath: buildDir)
        }

        try await runProcess(
            "/usr/bin/git",
            arguments: [
                "clone", "--depth", "1",
                "https://github.com/ggerganov/whisper.cpp.git",
                "\(buildDir)/whisper.cpp",
            ]
        )
    }

    private func compileWhisperCpp() async throws {
        let sourceDir = "/tmp/whisperkey-build/whisper.cpp"

        let cmake = try await ensureCmake()

        try await runProcess(
            cmake,
            arguments: ["-B", "build", "-DGGML_METAL=ON", "-DBUILD_SHARED_LIBS=OFF"],
            currentDirectory: sourceDir
        )

        let cpuCount = ProcessInfo.processInfo.activeProcessorCount
        try await runProcess(
            cmake,
            arguments: ["--build", "build", "--config", "Release", "-j\(cpuCount)"],
            currentDirectory: sourceDir
        )

        // Copy binary to ~/.whisperkey/bin/
        let sourcePath = "\(sourceDir)/build/bin/whisper-cli"
        let destPath = appState.whisperCLIPath

        let fm = FileManager.default
        if fm.fileExists(atPath: destPath) {
            try fm.removeItem(atPath: destPath)
        }
        try fm.copyItem(atPath: sourcePath, toPath: destPath)

        // Ensure executable
        try await runProcess("/bin/chmod", arguments: ["+x", destPath])
        await appendLog("Installed whisper-cli to ~/.whisperkey/bin/")
    }

    private func downloadModel() async throws {
        guard
            let url = URL(
                string:
                    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
            )
        else {
            throw URLError(.badURL)
        }

        let destination = URL(fileURLWithPath: appState.modelPath)
        let downloader = ModelDownloader()
        self.modelDownloader = downloader

        try await downloader.download(from: url, to: destination) {
            [weak self] fraction, completed, total in
            self?.downloadProgress = fraction
            self?.downloadedBytes = completed
            self?.totalBytes = total
        }

        await appendLog("Downloaded ggml-medium.bin")
    }

    // MARK: - Process Execution

    @MainActor
    private func appendLog(_ text: String) {
        logOutput += text + "\n"
    }

    private func runProcess(
        _ executablePath: String,
        arguments: [String],
        currentDirectory: String? = nil
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            if let dir = currentDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: dir)
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            self.currentProcess = process

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    Task { @MainActor in self?.appendLog(str) }
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    Task { @MainActor in self?.appendLog(str) }
                }
            }

            process.terminationHandler = { process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "SetupManager",
                            code: Int(process.terminationStatus),
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "Command failed with exit code \(process.terminationStatus)"
                            ]
                        ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
