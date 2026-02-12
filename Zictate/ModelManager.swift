//
//  ModelManager.swift
//  Zictate
//
//  Created by Codex on 12/02/26.
//

import Combine
import Foundation

struct RemoteModelOption: Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    var sourceURL: URL
    var recommendedForRealtime: Bool
    var estimatedSizeBytes: Int64
}

struct ValidatedRemoteModel: Sendable {
    var modelID: String
    var downloadURL: URL
    var sizeBytes: Int64?
}

enum ModelManagerError: LocalizedError {
    case unsupportedURL
    case invalidDownloadLocation
    case invalidModelFile
    case invalidModelName

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            return "Model URL is invalid. Use a direct model file URL (.bin/.gguf). For Hugging Face, use /resolve/... or /blob/... file URLs."
        case .invalidDownloadLocation:
            return "Could not move downloaded model to app storage."
        case .invalidModelFile:
            return "The selected URL/file is not a supported model (.bin or .gguf)."
        case .invalidModelName:
            return "Model name is invalid."
        }
    }
}

@MainActor
final class ModelManager: ObservableObject {
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var downloadingModelID: String?
    @Published private(set) var downloadSpeedBytesPerSecond: Double = 0
    @Published private(set) var etaSeconds: Double?
    @Published private(set) var lastErrorMessage: String?

    private var activeDownloadSession: URLSession?
    private var activeDownloadDelegate: DownloadDelegate?

    let availableModels: [RemoteModelOption] = [
        RemoteModelOption(
            id: "ggml-base.en.bin",
            displayName: "Whisper Base EN (Low Latency)",
            sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!,
            recommendedForRealtime: true,
            estimatedSizeBytes: 148_000_000
        ),
        RemoteModelOption(
            id: "ggml-small.en.bin",
            displayName: "Whisper Small EN (Better Accuracy)",
            sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!,
            recommendedForRealtime: true,
            estimatedSizeBytes: 466_000_000
        ),
        RemoteModelOption(
            id: "ggml-medium.en.bin",
            displayName: "Whisper Medium EN (Higher Quality)",
            sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin")!,
            recommendedForRealtime: false,
            estimatedSizeBytes: 1_500_000_000
        ),
    ]

    func modelsDirectoryURL() throws -> URL {
        let appSupportRoot = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let modelsDir = appSupportRoot
            .appendingPathComponent("Zictate", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }

    func localURL(for option: RemoteModelOption) throws -> URL {
        try modelsDirectoryURL().appendingPathComponent(option.id)
    }

    func localURL(forModelID modelID: String) throws -> URL {
        try modelsDirectoryURL().appendingPathComponent(modelID)
    }

    func isInstalled(_ option: RemoteModelOption) -> Bool {
        guard let localURL = try? localURL(for: option) else { return false }
        return FileManager.default.fileExists(atPath: localURL.path)
    }

    func uninstall(_ option: RemoteModelOption) throws {
        let destinationURL = try localURL(for: option)
        guard FileManager.default.fileExists(atPath: destinationURL.path) else { return }
        try FileManager.default.removeItem(at: destinationURL)
    }

    func install(_ option: RemoteModelOption) async throws -> URL {
        _ = try await install(from: option.sourceURL, modelID: option.id)
        return try localURL(for: option)
    }

    func install(from remoteURL: URL, modelID preferredModelID: String? = nil) async throws -> URL {
        let normalizedURL = try normalizedRemoteModelURL(from: remoteURL)

        isDownloading = true
        let modelID = try resolvedModelID(from: normalizedURL, preferredID: preferredModelID)
        downloadingModelID = modelID
        downloadProgress = 0
        downloadSpeedBytesPerSecond = 0
        etaSeconds = nil
        lastErrorMessage = nil
        defer {
            isDownloading = false
            downloadingModelID = nil
            downloadSpeedBytesPerSecond = 0
            etaSeconds = nil
            activeDownloadSession?.finishTasksAndInvalidate()
            activeDownloadSession = nil
            activeDownloadDelegate = nil
        }

        do {
            let temporaryURL = try await downloadFile(from: normalizedURL)
            let destinationURL = try localURL(forModelID: modelID)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            do {
                try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            } catch {
                // Fallback for cross-volume moves.
                try FileManager.default.copyItem(at: temporaryURL, to: destinationURL)
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            downloadProgress = 1
            etaSeconds = 0

            return destinationURL
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func validateRemoteModelURL(_ remoteURL: URL, preferredModelID: String? = nil) async throws -> ValidatedRemoteModel {
        let normalizedURL = try normalizedRemoteModelURL(from: remoteURL)
        guard isSupportedModelFile(normalizedURL) else {
            throw ModelManagerError.invalidModelFile
        }
        let modelID = try resolvedModelID(from: normalizedURL, preferredID: preferredModelID)
        let size = try await fetchRemoteFileSize(url: normalizedURL)

        return ValidatedRemoteModel(modelID: modelID, downloadURL: normalizedURL, sizeBytes: size)
    }

    func importLocalModel(from sourceURL: URL, modelID preferredModelID: String? = nil) throws -> URL {
        let modelID = try resolvedModelID(from: sourceURL, preferredID: preferredModelID)
        let destinationURL = try localURL(forModelID: modelID)

        guard isSupportedModelFile(sourceURL) else {
            throw ModelManagerError.invalidModelFile
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw ModelManagerError.invalidDownloadLocation
        }

        return destinationURL
    }

    private func resolvedModelID(from url: URL, preferredID: String?) throws -> String {
        let raw = preferredID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? preferredID!
            : url.lastPathComponent

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ModelManagerError.invalidModelName
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        guard !sanitized.isEmpty else {
            throw ModelManagerError.invalidModelName
        }
        return sanitized
    }

    private func normalizedRemoteModelURL(from inputURL: URL) throws -> URL {
        guard let scheme = inputURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ModelManagerError.unsupportedURL
        }

        guard let host = inputURL.host?.lowercased() else {
            throw ModelManagerError.unsupportedURL
        }

        // Support Hugging Face UI URLs by converting blob/raw URLs to direct resolve URLs.
        if host.contains("huggingface.co") {
            let pathComponents = inputURL.path.split(separator: "/").map(String.init)
            guard pathComponents.count >= 2 else {
                throw ModelManagerError.unsupportedURL
            }

            // Repository root like /org/repo is not enough to infer file automatically.
            if pathComponents.count == 2 {
                throw ModelManagerError.unsupportedURL
            }

            // /org/repo/blob/<rev>/<file...> -> /org/repo/resolve/<rev>/<file...>
            if pathComponents.count >= 5, pathComponents[2] == "blob" || pathComponents[2] == "raw" {
                var components = URLComponents(url: inputURL, resolvingAgainstBaseURL: false)
                var rewritten = pathComponents
                rewritten[2] = "resolve"
                components?.path = "/" + rewritten.joined(separator: "/")
                if let rebuilt = components?.url {
                    return rebuilt
                }
                throw ModelManagerError.unsupportedURL
            }

            // Must already be direct-style URL.
            if pathComponents.count >= 5, pathComponents[2] == "resolve" {
                return inputURL
            }

            throw ModelManagerError.unsupportedURL
        }

        return inputURL
    }

    private func isSupportedModelFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "bin" || ext == "gguf" || ext.isEmpty
    }

    private func fetchRemoteFileSize(url: URL) async throws -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelManagerError.unsupportedURL
        }
        guard (200...399).contains(http.statusCode) else {
            throw ModelManagerError.unsupportedURL
        }

        if let contentLengthHeader = http.value(forHTTPHeaderField: "Content-Length"),
           let parsed = Int64(contentLengthHeader), parsed > 0 {
            return parsed
        }
        return nil
    }

    private func downloadFile(from remoteURL: URL) async throws -> URL {
        let delegate = DownloadDelegate { [weak self] progress, bytesPerSecond, remainingSeconds in
            Task { @MainActor in
                self?.downloadProgress = progress
                self?.downloadSpeedBytesPerSecond = bytesPerSecond
                self?.etaSeconds = remainingSeconds
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        activeDownloadSession = session
        activeDownloadDelegate = delegate

        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            let task = session.downloadTask(with: remoteURL)
            task.resume()
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var continuation: CheckedContinuation<URL, Error>?
    private let onProgress: (Double, Double, Double?) -> Void
    private var lastProgressUpdateAt: Date?
    private var lastWrittenBytes: Int64 = 0
    private var lastEmittedAt: Date?

    init(onProgress: @escaping (Double, Double, Double?) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let now = Date()
        let bytesPerSecond: Double

        if let previousAt = lastProgressUpdateAt {
            let deltaTime = now.timeIntervalSince(previousAt)
            if deltaTime > 0 {
                let deltaBytes = totalBytesWritten - lastWrittenBytes
                bytesPerSecond = max(0, Double(deltaBytes) / deltaTime)
            } else {
                bytesPerSecond = 0
            }
        } else {
            bytesPerSecond = 0
        }

        lastProgressUpdateAt = now
        lastWrittenBytes = totalBytesWritten

        let remainingBytes = max(0, totalBytesExpectedToWrite - totalBytesWritten)
        let remainingSeconds: Double?
        if bytesPerSecond > 0 {
            remainingSeconds = Double(remainingBytes) / bytesPerSecond
        } else {
            remainingSeconds = nil
        }

        let shouldEmit: Bool
        if let lastEmittedAt {
            shouldEmit = now.timeIntervalSince(lastEmittedAt) >= 1 || progress >= 1
        } else {
            shouldEmit = true
        }

        if shouldEmit {
            self.lastEmittedAt = now
            onProgress(progress, bytesPerSecond, remainingSeconds)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let persistentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zictate-model-\(UUID().uuidString)")
            .appendingPathExtension("bin")

        do {
            if FileManager.default.fileExists(atPath: persistentURL.path) {
                try FileManager.default.removeItem(at: persistentURL)
            }
            try FileManager.default.moveItem(at: location, to: persistentURL)
            continuation?.resume(returning: persistentURL)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
