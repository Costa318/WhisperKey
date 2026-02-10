import Foundation

final class ModelDownloader: NSObject, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private var progressHandler: ((Double, Int64, Int64) -> Void)?
    private var destinationURL: URL?
    private var downloadTask: URLSessionDownloadTask?

    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }()

    func download(
        from url: URL,
        to destination: URL,
        onProgress: @escaping (_ fraction: Double, _ completed: Int64, _ total: Int64) -> Void
    ) async throws {
        self.destinationURL = destination
        self.progressHandler = onProgress

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            let task = session.downloadTask(with: url)
            self.downloadTask = task
            task.resume()
        }
    }

    func cancel() {
        downloadTask?.cancel()
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let destination = destinationURL else {
            continuation?.resume(throwing: URLError(.badURL))
            continuation = nil
            return
        }

        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: location, to: destination)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let fraction =
            totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        progressHandler?(fraction, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
