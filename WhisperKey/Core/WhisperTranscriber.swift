import Foundation

final class WhisperTranscriber {
    struct Result {
        let text: String
        let duration: TimeInterval
    }

    enum TranscriptionError: LocalizedError {
        case binaryNotFound
        case modelNotFound
        case timeout
        case emptyResult
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound: "whisper-cli not found. Run setup again."
            case .modelNotFound: "Speech model not found. Run setup again."
            case .timeout: "Transcription timed out."
            case .emptyResult: "Could not detect speech."
            case .processFailed(let msg): "Transcription failed: \(msg)"
            }
        }
    }

    func transcribe(audioURL: URL) async throws -> Result {
        let prefs = Preferences.shared

        guard FileManager.default.fileExists(atPath: prefs.whisperCLIPath) else {
            throw TranscriptionError.binaryNotFound
        }
        guard FileManager.default.fileExists(atPath: prefs.modelPath) else {
            throw TranscriptionError.modelNotFound
        }

        let startTime = Date()

        let text = try await runWhisper(
            binary: prefs.whisperCLIPath,
            model: prefs.modelPath,
            audioFile: audioURL.path,
            language: prefs.language,
            threads: prefs.threadCount
        )

        // Clean up temp audio file
        try? FileManager.default.removeItem(at: audioURL)

        let duration = -startTime.timeIntervalSinceNow

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptionError.emptyResult
        }

        return Result(text: trimmed, duration: duration)
    }

    private func runWhisper(
        binary: String, model: String, audioFile: String, language: String, threads: Int
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = [
                "--model", model,
                "--file", audioFile,
                "--language", language,
                "--no-timestamps",
                "--threads", "\(threads)",
            ]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // 60-second timeout
            let timeoutItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: timeoutItem)

            process.terminationHandler = { proc in
                timeoutItem.cancel()

                let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else if proc.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: TranscriptionError.timeout)
                } else {
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(
                        throwing: TranscriptionError.processFailed(errMsg))
                }
            }

            do {
                try process.run()
            } catch {
                timeoutItem.cancel()
                continuation.resume(throwing: error)
            }
        }
    }
}
