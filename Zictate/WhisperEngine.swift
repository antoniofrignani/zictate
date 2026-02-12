//
//  WhisperEngine.swift
//  Zictate
//
//  Created by Codex on 12/02/26.
//

import Foundation
import Darwin

struct TranscriptionResult: Sendable {
    var text: String
    var confidence: Double?
}

enum WhisperEngineError: LocalizedError {
    case modelNotLoaded
    case modelFileMissing
    case executableNotFound
    case processFailed(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No model is loaded."
        case .modelFileMissing:
            return "The selected model file was not found."
        case .executableNotFound:
            return "whisper.cpp CLI executable was not found. Install with `brew install whisper-cpp` and set path `/opt/homebrew/bin/whisper-cli` in Settings > CLI Path."
        case .processFailed(let details):
            return "whisper.cpp failed: \(details)"
        case .emptyResult:
            return "Transcription finished with an empty result."
        }
    }
}

protocol SpeechToTextEngine {
    func loadModel(at url: URL) throws
    func unloadModel()
    func transcribe(samples: [Float], sampleRate: Int, languageCode: String?) async throws -> TranscriptionResult
}

final class WhisperEngine: SpeechToTextEngine {
    private(set) var loadedModelURL: URL?
    private var preferredExecutableURL: URL?

    init(preferredExecutableURL: URL? = nil) {
        self.preferredExecutableURL = preferredExecutableURL
    }

    func setPreferredExecutableURL(_ url: URL?) {
        self.preferredExecutableURL = url
    }

    static func resolveUserProvidedExecutablePath(_ rawPath: String) -> URL? {
        normalizedExecutableURL(from: rawPath)
    }

    func loadModel(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WhisperEngineError.modelFileMissing
        }
        loadedModelURL = url
    }

    func unloadModel() {
        loadedModelURL = nil
    }

    func transcribe(samples: [Float], sampleRate: Int, languageCode: String? = nil) async throws -> TranscriptionResult {
        guard loadedModelURL != nil else {
            throw WhisperEngineError.modelNotLoaded
        }
        let modelURL = loadedModelURL!
        let executable = try resolveExecutable()
        let wavURL = try Self.createTemporaryWAV(samples: samples, sampleRate: sampleRate)
        let outputBaseURL = wavURL.deletingPathExtension().appendingPathExtension("out")

        defer {
            try? FileManager.default.removeItem(at: wavURL)
            try? FileManager.default.removeItem(at: outputBaseURL.appendingPathExtension("txt"))
        }

        var arguments = [
            "-m", modelURL.path,
            "-f", wavURL.path,
            "-otxt",
            "-of", outputBaseURL.path,
            "-nt",
            "-np"
        ]
        if let languageCode {
            let trimmedLanguage = languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmedLanguage.isEmpty, trimmedLanguage != "auto" {
                arguments.append(contentsOf: ["-l", trimmedLanguage])
            }
        }

        let execution = try await Self.runProcess(executable: executable, arguments: arguments)
        if execution.exitCode != 0 {
            let details = execution.standardError.isEmpty ? execution.standardOutput : execution.standardError
            throw WhisperEngineError.processFailed(details)
        }

        let fileResult = try? String(contentsOf: outputBaseURL.appendingPathExtension("txt"), encoding: .utf8)
        let text = (fileResult ?? execution.standardOutput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw WhisperEngineError.emptyResult
        }
        return TranscriptionResult(text: text, confidence: nil)
    }

    private func resolveExecutable() throws -> URL {
        let env = ProcessInfo.processInfo.environment

        if let envPath = env["WHISPER_CPP_EXECUTABLE"],
           let envExecutable = Self.normalizedExecutableURL(from: envPath) {
            return envExecutable
        }

        if let preferredExecutableURL,
           let preferredExecutable = Self.normalizedExecutableURL(from: preferredExecutableURL.path) {
            return preferredExecutable
        }

        if let bundled = Bundle.main.url(forResource: "whisper-cli", withExtension: nil),
           Self.isExecutableFile(at: bundled.path) {
            return bundled
        }

        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/opt/homebrew/opt/whisper-cpp/bin/whisper-cli",
            "/opt/homebrew/opt/whisper-cpp/bin/whisper-cpp",
            "/opt/homebrew/Cellar/whisper-cpp/current/bin/whisper-cli",
            "/opt/homebrew/Cellar/whisper-cpp/current/libexec/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/usr/local/bin/whisper-cpp",
            "/usr/local/opt/whisper-cpp/bin/whisper-cli",
            "/usr/local/Cellar/whisper-cpp/current/bin/whisper-cli",
            "/usr/local/Cellar/whisper-cpp/current/libexec/bin/whisper-cli",
            "/usr/bin/whisper-cli",
            "/usr/bin/whisper-cpp",
        ]

        for path in candidates {
            if let candidate = Self.normalizedExecutableURL(from: path) {
                return candidate
            }
        }

        if let cellarExecutable = resolveFromCellar(root: "/opt/homebrew/Cellar/whisper-cpp") {
            return cellarExecutable
        }
        if let cellarExecutable = resolveFromCellar(root: "/usr/local/Cellar/whisper-cpp") {
            return cellarExecutable
        }

        throw WhisperEngineError.executableNotFound
    }

    private func resolveFromCellar(root: String) -> URL? {
        let fm = FileManager.default
        guard let versions = try? fm.contentsOfDirectory(atPath: root), !versions.isEmpty else {
            return nil
        }

        for version in versions.sorted(by: >) {
            let binPath = "\(root)/\(version)/bin/whisper-cli"
            if let executable = Self.normalizedExecutableURL(from: binPath) {
                return executable
            }

            let libexecPath = "\(root)/\(version)/libexec/bin/whisper-cli"
            if let executable = Self.normalizedExecutableURL(from: libexecPath) {
                return executable
            }
        }

        return nil
    }

    private static func normalizedExecutableURL(from rawPath: String) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let directURL = URL(fileURLWithPath: expanded)
        if isExecutableFile(at: directURL.path) {
            return directURL
        }

        let resolvedURL = directURL.resolvingSymlinksInPath()
        if isExecutableFile(at: resolvedURL.path) {
            return resolvedURL
        }

        return nil
    }

    private static func isExecutableFile(at path: String) -> Bool {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: path) {
            return true
        }

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }

        return access(path, X_OK) == 0
    }

    private static func runProcess(executable: URL, arguments: [String]) async throws -> ProcessExecutionResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            return ProcessExecutionResult(
                exitCode: process.terminationStatus,
                standardOutput: stdout,
                standardError: stderr
            )
        }.value
    }

    private static func createTemporaryWAV(samples: [Float], sampleRate: Int) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zictate-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        var wavData = Data()

        let pcm16Samples = samples.map { sample in
            Int16(max(-1.0, min(1.0, sample)) * Float(Int16.max))
        }
        let pcmDataSize = pcm16Samples.count * MemoryLayout<Int16>.size
        let fileSize = 36 + pcmDataSize

        wavData.appendASCII("RIFF")
        wavData.appendLE(UInt32(fileSize))
        wavData.appendASCII("WAVE")
        wavData.appendASCII("fmt ")
        wavData.appendLE(UInt32(16))
        wavData.appendLE(UInt16(1))
        wavData.appendLE(UInt16(1))
        wavData.appendLE(UInt32(sampleRate))
        wavData.appendLE(UInt32(sampleRate * MemoryLayout<Int16>.size))
        wavData.appendLE(UInt16(MemoryLayout<Int16>.size))
        wavData.appendLE(UInt16(16))
        wavData.appendASCII("data")
        wavData.appendLE(UInt32(pcmDataSize))

        for value in pcm16Samples {
            wavData.appendLE(UInt16(bitPattern: value))
        }

        try wavData.write(to: tempURL, options: .atomic)
        return tempURL
    }
}

private struct ProcessExecutionResult {
    var exitCode: Int32
    var standardOutput: String
    var standardError: String
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(string.data(using: .ascii)!)
    }

    mutating func appendLE(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendLE(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
