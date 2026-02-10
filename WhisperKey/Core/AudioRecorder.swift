import AVFoundation
import Foundation

final class AudioRecorder {
    enum RecordingResult {
        case success(URL)
        case tooShort
    }

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var startTime: Date?
    private var maxDurationTimer: Timer?

    private(set) var isRecording = false
    var onMaxDurationReached: (() -> Void)?

    func startRecording() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("whisperkey_\(UUID().uuidString).wav")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16000,
                channels: 1,
                interleaved: true
            )
        else {
            throw RecordingError.formatCreationFailed
        }

        let file = try AVAudioFile(forWriting: url, settings: targetFormat.settings)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecordingError.converterCreationFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            let ratio = 16000.0 / inputFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

            guard outputFrameCount > 0,
                let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: targetFormat, frameCapacity: outputFrameCount)
            else { return }

            var error: NSError?
            var hasInput = true
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if hasInput {
                    hasInput = false
                    outStatus.pointee = .haveData
                    return buffer
                }
                outStatus.pointee = .noDataNow
                return nil
            }

            if error == nil, outputBuffer.frameLength > 0 {
                try? file.write(from: outputBuffer)
            }
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.audioFile = file
        self.recordingURL = url
        self.startTime = Date()
        self.isRecording = true

        let maxDuration = Preferences.shared.maxRecordingDuration
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) {
            [weak self] _ in
            self?.onMaxDurationReached?()
        }
    }

    func stopRecording() -> RecordingResult {
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isRecording = false

        let duration = -(startTime?.timeIntervalSinceNow ?? 0)

        guard let url = recordingURL else { return .tooShort }

        if duration < 0.5 {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
            return .tooShort
        }

        recordingURL = nil
        return .success(url)
    }

    enum RecordingError: LocalizedError {
        case formatCreationFailed
        case converterCreationFailed

        var errorDescription: String? {
            switch self {
            case .formatCreationFailed: "Failed to create target audio format"
            case .converterCreationFailed: "Failed to create audio format converter"
            }
        }
    }
}
