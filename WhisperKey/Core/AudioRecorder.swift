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
    private let writeQueue = DispatchQueue(label: "com.whisperkey.audiowrite")

    private(set) var isRecording = false
    var onMaxDurationReached: (() -> Void)?

    func startRecording() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("whisperkey_\(UUID().uuidString).wav")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        // Validate the hardware format — can be degenerate if mic access isn't ready
        guard hardwareFormat.channelCount > 0, hardwareFormat.sampleRate > 0 else {
            throw RecordingError.invalidInputFormat
        }

        // Target: 16kHz mono Int16 on disk, Float32 for processing
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        // processingFormat = Float32 16kHz mono — this is the format we must write
        let file = try AVAudioFile(
            forWriting: url,
            settings: fileSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Use AVAudioConverter to go from hardware format → Float32 16kHz mono
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            )
        else {
            throw RecordingError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            throw RecordingError.converterCreationFailed
        }

        let writeQueue = self.writeQueue
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) {
            buffer, _ in
            let ratio = targetFormat.sampleRate / hardwareFormat.sampleRate
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
                writeQueue.async {
                    try? file.write(from: outputBuffer)
                }
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

        // Wait for any pending writes to finish before closing the file
        writeQueue.sync {}
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
        case invalidInputFormat

        var errorDescription: String? {
            switch self {
            case .formatCreationFailed: "Failed to create target audio format"
            case .converterCreationFailed: "Failed to create audio format converter"
            case .invalidInputFormat: "No valid audio input found. Check microphone access."
            }
        }
    }
}
