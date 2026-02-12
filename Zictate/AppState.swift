//
//  AppState.swift
//  Zictate
//
//  Created by Codex on 12/02/26.
//

import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftData

@MainActor
final class AppState: ObservableObject {
    @Published var isDictating = false
    @Published var isProcessing = false
    @Published var liveWaveform: [Float] = Array(repeating: 0.03, count: 64)
    @Published var lastTranscript: String = ""
    @Published var lastError: String?
    @Published var whisperExecutablePath: String {
        didSet {
            defaults.set(whisperExecutablePath, forKey: Self.whisperExecutablePathDefaultsKey)
            applyExecutablePath()
        }
    }
    @Published var shortcut: HotkeyShortcut {
        didSet {
            persistShortcut()
            GlobalHotkeyManager.shared.register(shortcut: shortcut)
        }
    }
    @Published var doubleTapEnabled: Bool {
        didSet {
            defaults.set(doubleTapEnabled, forKey: Self.doubleTapEnabledDefaultsKey)
            ModifierDoubleTapManager.shared.isEnabled = doubleTapEnabled
        }
    }
    @Published var doubleTapKey: DoubleTapModifierKey {
        didSet {
            defaults.set(doubleTapKey.rawValue, forKey: Self.doubleTapKeyDefaultsKey)
            ModifierDoubleTapManager.shared.selectedKey = doubleTapKey
        }
    }

    private let defaults: UserDefaults
    private let modelContext: ModelContext
    private let audioCaptureService = AudioCaptureService()
    private let whisperEngine = WhisperEngine()
    private let textInsertionService = TextInsertionService()

    init(modelContainer: ModelContainer, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.modelContext = ModelContext(modelContainer)

        let storedKeyCode = defaults.object(forKey: Self.shortcutKeyCodeDefaultsKey) as? UInt32
        let storedModifiers = defaults.object(forKey: Self.shortcutModifiersDefaultsKey) as? UInt

        if let storedKeyCode, let storedModifiers {
            self.shortcut = HotkeyShortcut(
                keyCode: storedKeyCode,
                modifiers: NSEvent.ModifierFlags(rawValue: storedModifiers)
            )
        } else {
            self.shortcut = .defaults
        }

        self.doubleTapEnabled = defaults.object(forKey: Self.doubleTapEnabledDefaultsKey) as? Bool ?? false
        if
            let rawKey = defaults.string(forKey: Self.doubleTapKeyDefaultsKey),
            let parsed = DoubleTapModifierKey(rawValue: rawKey)
        {
            self.doubleTapKey = parsed
        } else {
            self.doubleTapKey = .rightShift
        }

        self.whisperExecutablePath = defaults.string(forKey: Self.whisperExecutablePathDefaultsKey) ?? ""

        GlobalHotkeyManager.shared.onTrigger = { [weak self] in
            Task { @MainActor in
                self?.toggleDictation()
            }
        }
        GlobalHotkeyManager.shared.register(shortcut: shortcut)

        ModifierDoubleTapManager.shared.onTrigger = { [weak self] in
            Task { @MainActor in
                self?.toggleDictation()
            }
        }
        ModifierDoubleTapManager.shared.selectedKey = doubleTapKey
        ModifierDoubleTapManager.shared.isEnabled = doubleTapEnabled

        applyExecutablePath()
    }

    func toggleDictation() {
        isDictating ? stopDictation() : startDictation()
    }

    func startDictation() {
        guard !isProcessing else { return }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard micStatus == .authorized else {
            lastError = "Microphone permission is required before dictation can start."
            return
        }

        do {
            liveWaveform = Array(repeating: 0.03, count: 64)
            try audioCaptureService.start { [weak self] samples in
                self?.updateWaveform(from: samples)
            }
            isDictating = true
            DictationOverlayController.shared.show(appState: self)
            lastError = nil
        } catch {
            lastError = "Could not start microphone capture: \(error.localizedDescription)"
        }
    }

    func stopDictation() {
        guard isDictating else { return }
        isDictating = false
        DictationOverlayController.shared.hide()

        let capture = audioCaptureService.stop()
        guard !capture.samples.isEmpty else {
            lastError = "No audio captured."
            return
        }

        Task {
            await transcribeAndHandle(samples: capture.samples, sampleRate: capture.sampleRate)
        }
    }

    func insertLastTranscriptAtCursor() {
        guard !lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let settings = fetchSettings()
        textInsertionService.insert(lastTranscript, mode: settings?.insertMode ?? .pasteboard)
    }

    func validateWhisperExecutablePath() -> Bool {
        let path = whisperExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return false }
        return WhisperEngine.resolveUserProvidedExecutablePath(path) != nil
    }

    private func persistShortcut() {
        defaults.set(shortcut.keyCode, forKey: Self.shortcutKeyCodeDefaultsKey)
        defaults.set(shortcut.modifiers.rawValue, forKey: Self.shortcutModifiersDefaultsKey)
    }

    static let shortcutKeyCodeDefaultsKey = "dictation.shortcut.keyCode"
    static let shortcutModifiersDefaultsKey = "dictation.shortcut.modifiers"
    static let doubleTapEnabledDefaultsKey = "dictation.doubleTap.enabled"
    static let doubleTapKeyDefaultsKey = "dictation.doubleTap.key"
    static let whisperExecutablePathDefaultsKey = "whisper.executable.path"

    private func transcribeAndHandle(samples: [Float], sampleRate: Int) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            guard let modelURL = try resolveSelectedModelURL() else {
                throw AppStateError.noModelSelected
            }

            try whisperEngine.loadModel(at: modelURL)
            let languageCode = fetchSettings()?.languageCode
            let result = try await whisperEngine.transcribe(
                samples: samples,
                sampleRate: sampleRate,
                languageCode: languageCode
            )
            let transcript = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                throw AppStateError.emptyTranscription
            }

            lastTranscript = transcript
            lastError = nil

            let item = Item(timestamp: .now, text: transcript)
            modelContext.insert(item)

            if fetchSettings()?.autoInsertEnabled == true {
                let mode = fetchSettings()?.insertMode ?? .pasteboard
                textInsertionService.insert(transcript, mode: mode)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func fetchSettings() -> AppSettings? {
        let descriptor = FetchDescriptor<AppSettings>()
        return try? modelContext.fetch(descriptor).first
    }

    private func resolveSelectedModelURL() throws -> URL? {
        let settings = fetchSettings()
        let selectedID = settings?.selectedModelID ?? ""
        guard !selectedID.isEmpty else { return nil }

        let descriptor = FetchDescriptor<InstalledModel>(
            predicate: #Predicate<InstalledModel> { model in
                model.id == selectedID
            }
        )

        guard let model = try modelContext.fetch(descriptor).first else {
            return nil
        }
        let url = URL(fileURLWithPath: model.localPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private func applyExecutablePath() {
        let trimmed = whisperExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            whisperEngine.setPreferredExecutableURL(nil)
            return
        }
        whisperEngine.setPreferredExecutableURL(
            WhisperEngine.resolveUserProvidedExecutablePath(trimmed) ?? URL(fileURLWithPath: trimmed)
        )
    }

    private func updateWaveform(from samples: [Float]) {
        let barCount = 64
        guard !samples.isEmpty else { return }

        let bucketSize = max(samples.count / barCount, 1)
        var targetBars: [Float] = Array(repeating: 0.03, count: barCount)

        for index in 0..<barCount {
            let start = index * bucketSize
            guard start < samples.count else { break }
            let end = min(start + bucketSize, samples.count)
            if end <= start { continue }

            var sum: Float = 0
            for sample in samples[start..<end] {
                sum += abs(sample)
            }
            let meanAbs = sum / Float(end - start)
            targetBars[index] = min(max(meanAbs * 10.5, 0.03), 1.0)
        }

        if liveWaveform.count != barCount {
            liveWaveform = targetBars
            return
        }

        var smoothed = liveWaveform
        for i in 0..<barCount {
            let previous = liveWaveform[i]
            let incoming = targetBars[i]
            if incoming >= previous {
                smoothed[i] = previous * 0.18 + incoming * 0.82
            } else {
                smoothed[i] = previous * 0.52 + incoming * 0.48
            }
        }
        liveWaveform = smoothed
    }
}

enum AppStateError: LocalizedError {
    case noModelSelected
    case emptyTranscription

    var errorDescription: String? {
        switch self {
        case .noModelSelected:
            return "No installed model selected. Install a model and press Use."
        case .emptyTranscription:
            return "No text was detected from the captured audio."
        }
    }
}
