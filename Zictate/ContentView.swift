//
//  ContentView.swift
//  Zictate
//
//  Created by Antonio Frignani on 12/02/26.
//

import SwiftUI
import AVFoundation
import SwiftData
import LocalAuthentication
import AppKit

struct ContentView: View {
    private struct RepositoryPreset: Identifiable {
        let id: String
        let name: String
        let url: String
    }

    private struct PendingRemoteModelCandidate: Identifiable {
        let id: String
        let displayName: String
        let modelID: String
        let downloadURL: URL
        let sizeBytes: Int64?
    }

    private struct LanguageOption: Identifiable, Hashable {
        let id: String
        let title: String
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var settings: [AppSettings]
    @Query private var installedModels: [InstalledModel]
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]

    @StateObject private var permissionsManager = PermissionsManager()
    @StateObject private var modelManager = ModelManager()
    @State private var modelInstallError: String?
    @State private var modelInstallSuccess: String?
    @State private var executablePathDraft: String = ""
    @State private var historyUnlocked = false
    @State private var historyAuthError: String?
    @State private var historyPage: Int = 0
    @State private var historyPageSize: Int = 20
    @State private var selectedHistoryIDs: Set<PersistentIdentifier> = []
    @State private var historyAutoLockTask: Task<Void, Never>?
    @State private var pendingModelDeletionID: String?
    @State private var pendingHistoryItemDeletionID: PersistentIdentifier?
    @State private var showDeleteSelectedConfirmation = false
    @State private var showDeletePageConfirmation = false
    @State private var showDeleteAllConfirmation = false
    @State private var customModelURLDraft: String = ""
    @State private var customModelNameDraft: String = ""
    @State private var languageSearchText: String = ""
    @State private var pendingRemoteModels: [PendingRemoteModelCandidate] = []
    @State private var bannerAutoClearTask: Task<Void, Never>?

    private let repositoryPresets: [RepositoryPreset] = [
        .init(id: "hf-base", name: "HF: Whisper Base EN", url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"),
        .init(id: "hf-small", name: "HF: Whisper Small EN", url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"),
        .init(id: "hf-medium", name: "HF: Whisper Medium EN", url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin"),
        .init(id: "hf-largev3-q5", name: "HF: Whisper Large-v3 (Q5_0 GGUF)", url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-q5_0.gguf"),
    ]
    private let languageOptions: [LanguageOption] = [
        .init(id: "auto", title: "Auto"),
        .init(id: "af", title: "Afrikaans"),
        .init(id: "ar", title: "Arabic"),
        .init(id: "hy", title: "Armenian"),
        .init(id: "az", title: "Azerbaijani"),
        .init(id: "be", title: "Belarusian"),
        .init(id: "bs", title: "Bosnian"),
        .init(id: "bg", title: "Bulgarian"),
        .init(id: "ca", title: "Catalan"),
        .init(id: "hr", title: "Croatian"),
        .init(id: "cs", title: "Czech"),
        .init(id: "da", title: "Danish"),
        .init(id: "en", title: "English"),
        .init(id: "et", title: "Estonian"),
        .init(id: "fi", title: "Finnish"),
        .init(id: "fr", title: "French"),
        .init(id: "gl", title: "Galician"),
        .init(id: "de", title: "German"),
        .init(id: "el", title: "Greek"),
        .init(id: "he", title: "Hebrew"),
        .init(id: "hi", title: "Hindi"),
        .init(id: "hu", title: "Hungarian"),
        .init(id: "is", title: "Icelandic"),
        .init(id: "id", title: "Indonesian"),
        .init(id: "it", title: "Italian"),
        .init(id: "ja", title: "Japanese"),
        .init(id: "kn", title: "Kannada"),
        .init(id: "kk", title: "Kazakh"),
        .init(id: "ko", title: "Korean"),
        .init(id: "lv", title: "Latvian"),
        .init(id: "lt", title: "Lithuanian"),
        .init(id: "mk", title: "Macedonian"),
        .init(id: "ms", title: "Malay"),
        .init(id: "mr", title: "Marathi"),
        .init(id: "ne", title: "Nepali"),
        .init(id: "nl", title: "Dutch"),
        .init(id: "no", title: "Norwegian"),
        .init(id: "fa", title: "Persian"),
        .init(id: "pl", title: "Polish"),
        .init(id: "pt", title: "Portuguese"),
        .init(id: "ro", title: "Romanian"),
        .init(id: "ru", title: "Russian"),
        .init(id: "sr", title: "Serbian"),
        .init(id: "sk", title: "Slovak"),
        .init(id: "sl", title: "Slovenian"),
        .init(id: "es", title: "Spanish"),
        .init(id: "sw", title: "Swahili"),
        .init(id: "sv", title: "Swedish"),
        .init(id: "tl", title: "Tagalog"),
        .init(id: "ta", title: "Tamil"),
        .init(id: "th", title: "Thai"),
        .init(id: "tr", title: "Turkish"),
        .init(id: "uk", title: "Ukrainian"),
        .init(id: "ur", title: "Urdu"),
        .init(id: "vi", title: "Vietnamese"),
        .init(id: "zh", title: "Chinese"),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.1, blue: 0.16), Color(red: 0.16, green: 0.22, blue: 0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    headerBar
                }
                .padding(20)

                ScrollView {
                    settingsSections
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            floatingBanner
                .padding(.top, 86)
                .padding(.trailing, 20)
        }
        .frame(minWidth: 960, minHeight: 700)
        .onAppear {
            bootstrapSettingsIfNeeded()
            migrateLegacyLanguageIfNeeded()
            permissionsManager.refresh()
            executablePathDraft = appState.whisperExecutablePath
            configureSettingsWindowBehavior()
        }
        .onChange(of: modelInstallError) { _, _ in
            refreshBannerAutoClear()
        }
        .onChange(of: modelInstallSuccess) { _, _ in
            refreshBannerAutoClear()
        }
        .confirmationDialog(
            "Delete model?",
            isPresented: isModelDeleteDialogPresented
        ) {
            Button("Delete \(pendingModelDeletionTitle)", role: .destructive) {
                if let modelID = pendingModelDeletionID {
                    deleteInstalledModel(byID: modelID)
                }
                pendingModelDeletionID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingModelDeletionID = nil
            }
        } message: {
            Text("This removes the model from disk.")
        }
        .confirmationDialog(
            "Delete transcript?",
            isPresented: isHistoryItemDeleteDialogPresented
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingHistoryItemDeletionID {
                    deleteHistoryItem(id: id)
                }
                pendingHistoryItemDeletionID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingHistoryItemDeletionID = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .confirmationDialog(
            "Delete selected transcripts?",
            isPresented: $showDeleteSelectedConfirmation
        ) {
            Button("Delete Selected", role: .destructive) {
                deleteSelectedHistoryItems()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .confirmationDialog(
            "Delete current page?",
            isPresented: $showDeletePageConfirmation
        ) {
            Button("Delete Page", role: .destructive) {
                deleteCurrentHistoryPage()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .confirmationDialog(
            "Delete all history?",
            isPresented: $showDeleteAllConfirmation
        ) {
            Button("Delete All", role: .destructive) {
                deleteAllHistoryItems()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Zictate")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Local realtime dictation from your menu bar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    headerInfoChip(title: "Model", value: selectedModelTitle)
                    headerInfoChip(title: "Language", value: effectiveLanguageLabel)
                    headerInfoChip(title: "Auto Insert", value: (settings.first?.autoInsertEnabled ?? false) ? "On" : "Off")
                }
                .padding(.top, 4)
            }
            Spacer()
            statusChip
        }
    }

    private func headerInfoChip(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(title):")
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.white.opacity(0.95))
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    private var settingsSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionBox(title: "Dictation", symbol: "waveform.badge.mic") { dictationContent }
            sectionBox(title: "Models", symbol: "square.stack.3d.up.fill") { modelsContent }
            if shouldShowPermissionsSection {
                sectionBox(title: "Permissions", symbol: "lock.shield") { permissionsContent }
            }
            sectionBox(title: "CLI Path", symbol: "terminal") { executableContent }
            sectionBox(title: "History", symbol: "text.bubble") {
                historyContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var shouldShowPermissionsSection: Bool {
        permissionsManager.microphoneStatus != .authorized || !permissionsManager.isAccessibilityTrusted
    }

    private func sectionBox<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))
            content()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private var statusChip: some View {
        let text = appState.isDictating ? "Recording" : (appState.isProcessing ? "Transcribing" : "Idle")
        let color: Color = appState.isDictating ? .red : (appState.isProcessing ? .orange : .secondary)
        return Text(text)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color.opacity(0.2), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
    }

    private var dictationContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HotkeyRecorderView(shortcut: $appState.shortcut)
            Text("Use this shortcut globally to start/stop dictation.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Automatically insert transcript at cursor", isOn: autoInsertEnabledBinding)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Language")
                    Spacer()
                    Text(selectedLanguageTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                TextField("Search language by name or code (e.g. italian, it)", text: $languageSearchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredLanguageOptions.prefix(8)) { option in
                            Button {
                                languageCodeBinding.wrappedValue = option.id
                            } label: {
                                HStack {
                                    Text(option.title)
                                    Spacer()
                                    Text(option.id.uppercased())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if languageCodeBinding.wrappedValue == option.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 210)
            }
            Text("Use Auto for multilingual models. English-only models perform best with English audio.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Insertion method")
                Spacer()
                HStack(spacing: 8) {
                    iconControlButton(
                        systemName: "keyboard",
                        help: "Insert mode: sends the transcript as keyboard input at the current cursor."
                    ) {
                        insertModeBinding.wrappedValue = .keyEvents
                    }
                    .opacity(insertModeBinding.wrappedValue == .keyEvents ? 1 : 0.7)

                    iconControlButton(
                        systemName: "doc.on.clipboard",
                        help: "Pasteboard mode: copies transcript to clipboard then pastes with Cmd+V."
                    ) {
                        insertModeBinding.wrappedValue = .pasteboard
                    }
                    .opacity(insertModeBinding.wrappedValue == .pasteboard ? 1 : 0.7)
                }
                .frame(maxWidth: 220)
                .disabled(!(settings.first?.autoInsertEnabled ?? false))
            }
            Text(
                insertModeBinding.wrappedValue == .keyEvents
                    ? "Insert mode types directly into the focused field."
                    : "Pasteboard mode pastes via clipboard (Cmd+V)."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Toggle("Enable double-tap trigger", isOn: $appState.doubleTapEnabled)

            HStack {
                Text("Double-tap key")
                Spacer()
                Picker("Double-tap key", selection: $appState.doubleTapKey) {
                    ForEach(DoubleTapModifierKey.allCases) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                .disabled(!appState.doubleTapEnabled)
            }

            if !appState.lastTranscript.isEmpty {
                Divider()
                Text("Last transcript")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appState.lastTranscript)
                    .textSelection(.enabled)
                Button("Insert Last Transcript at Cursor") {
                    appState.insertLastTranscriptAtCursor()
                }
            }

            if let lastError = appState.lastError {
                Text(lastError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private var executableContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("e.g. /opt/homebrew/bin/whisper-cli", text: $executablePathDraft)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save Path") { saveExecutablePath() }
                Button("Use Auto Discovery") {
                    executablePathDraft = ""
                    saveExecutablePath()
                }
            }

            let current = appState.whisperExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty {
                Text("Current: Auto discovery")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Current: \(current)")
                    .font(.caption)
                    .textSelection(.enabled)
                Text(appState.validateWhisperExecutablePath() ? "Path is executable." : "Path is not executable.")
                    .font(.caption)
                    .foregroundStyle(appState.validateWhisperExecutablePath() ? .green : .red)
            }
        }
    }

    private var permissionsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Microphone")
                Spacer()
                Text(microphoneStatusText)
                    .foregroundStyle(.secondary)
                Button("Request") { permissionsManager.requestMicrophoneAccess() }
                    .disabled(permissionsManager.microphoneStatus == .authorized)
            }

            HStack {
                Text("Accessibility")
                Spacer()
                Text(permissionsManager.isAccessibilityTrusted ? "Authorized" : "Not authorized")
                    .foregroundStyle(.secondary)
                Button("Request") { permissionsManager.requestAccessibilityAccess() }
                    .disabled(permissionsManager.isAccessibilityTrusted)
                Button("Open") { permissionsManager.openAccessibilitySettings() }
            }
        }
    }

    private var modelsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Main Repositories")
                    .font(.subheadline.weight(.semibold))
                Text("Quick-add from known sources.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(repositoryPresets) { preset in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.callout.weight(.medium))
                            Text(preset.url)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button("Download") {
                            customModelURLDraft = preset.url
                            customModelNameDraft = URL(string: preset.url)?.lastPathComponent ?? ""
                            Task { await validateAndQueueRemoteModel() }
                        }
                        .disabled(modelManager.isDownloading)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Bring Your Own Model")
                    .font(.subheadline.weight(.semibold))
                TextField("Model URL (Hugging Face, GitHub release, direct file URL)", text: $customModelURLDraft)
                    .textFieldStyle(.roundedBorder)
                TextField("Optional display/model name (e.g. ggml-my-model.bin)", text: $customModelNameDraft)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Validate & Add") {
                        Task { await validateAndQueueRemoteModel() }
                    }
                    .disabled(modelManager.isDownloading || customModelURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Import Local File") {
                        importLocalModelFromDisk()
                    }
                    .disabled(modelManager.isDownloading)
                }
                Text("Use direct model file URLs (.bin, .gguf).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Hugging Face repo pages like /org/repo are not valid model URLs. Use a file URL, e.g. .../blob/main/file.bin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !pendingRemoteModels.isEmpty {
                Divider()
                Text("Validated Remote Models")
                    .font(.subheadline.weight(.semibold))
                ForEach(pendingRemoteModels) { candidate in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.displayName)
                                    .font(.headline)
                                Text(candidate.modelID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(candidate.downloadURL.absoluteString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                                if let size = candidate.sizeBytes {
                                    Text("Size: \(formattedBytes(size))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Size: unknown")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if isInstalledModelID(candidate.modelID) {
                                Text("Installed")
                                    .foregroundStyle(.green)
                                if !isSelectedModelID(candidate.modelID) {
                                    Button("Use") {
                                        if let model = installedModels.first(where: { $0.id == candidate.modelID }) {
                                            useInstalledModel(model)
                                        }
                                    }
                                }
                            } else {
                                Button("Download") {
                                    Task { await installPendingRemoteModel(candidate) }
                                }
                                .disabled(modelManager.isDownloading)
                            }
                            iconControlButton(systemName: "xmark", help: "Remove from queue.") {
                                pendingRemoteModels.removeAll { $0.id == candidate.id }
                            }
                        }

                        if modelManager.downloadingModelID == candidate.modelID {
                            ProgressView(value: modelManager.downloadProgress)
                            Text("Downloading \(Int(modelManager.downloadProgress * 100))% • \(formattedSpeed(modelManager.downloadSpeedBytesPerSecond)) • ETA \(formattedETA(modelManager.etaSeconds))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                }
            }

            Divider()

            Text("Built-in Catalog")
                .font(.subheadline.weight(.semibold))

            ForEach(modelManager.availableModels) { option in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.displayName).font(.headline)
                            Text("\(option.id) - ~\(formattedBytes(option.estimatedSizeBytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if modelManager.isInstalled(option) {
                            Text(isSelectedModel(option) ? "Selected" : "Installed")
                                .foregroundStyle(.green)
                            Button(isSelectedModel(option) ? "Using" : "Use") { useModel(option) }
                                .disabled(isSelectedModel(option))
                            Button("Delete", role: .destructive) { pendingModelDeletionID = option.id }
                                .disabled(modelManager.isDownloading)
                        } else {
                            Button("Install") { Task { await installModel(option) } }
                                .disabled(modelManager.isDownloading)
                        }
                    }
                    if modelManager.downloadingModelID == option.id {
                        ProgressView(value: modelManager.downloadProgress)
                        Text("Downloading \(Int(modelManager.downloadProgress * 100))% • \(formattedSpeed(modelManager.downloadSpeedBytesPerSecond)) • ETA \(formattedETA(modelManager.etaSeconds))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
            }

            if !customInstalledModels.isEmpty {
                Text("Custom / Local Installed")
                    .font(.subheadline.weight(.semibold))
                ForEach(customInstalledModels) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.displayName)
                                .font(.headline)
                            Text("\(model.id) • \(formattedBytes(model.sizeBytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !model.sourceURL.isEmpty {
                                Text(model.sourceURL)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer()
                        Text(model.isActive ? "Selected" : "Installed")
                            .foregroundStyle(.green)
                        Button(model.isActive ? "Using" : "Use") {
                            useInstalledModel(model)
                        }
                        .disabled(model.isActive)
                        Button("Delete", role: .destructive) {
                            pendingModelDeletionID = model.id
                        }
                    }
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if !historyUnlocked {
            VStack(alignment: .leading, spacing: 10) {
                Text("History is protected.")
                    .font(.callout.weight(.semibold))
                Text("Authenticate with Touch ID or your account password to view transcripts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                iconControlButton(
                    systemName: "lock.open.fill",
                    help: "Unlock history with system authentication."
                ) {
                    authenticateHistoryAccess()
                }
                if let historyAuthError {
                    Text(historyAuthError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } else if items.isEmpty {
            Text("No transcripts yet.")
                .foregroundStyle(.secondary)
                .onAppear { refreshHistoryAutoLockTimer() }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    iconControlButton(
                        systemName: "lock.fill",
                        help: "Lock history."
                    ) {
                        lockHistory()
                    }

                    Spacer()

                    Text("Rows per page")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Rows per page", selection: $historyPageSize) {
                        Text("10").tag(10)
                        Text("20").tag(20)
                        Text("50").tag(50)
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    .onChange(of: historyPageSize) { _, _ in
                        historyPage = 0
                        selectedHistoryIDs.removeAll()
                        touchHistoryActivity()
                    }
                }

                HStack(spacing: 8) {
                    iconControlButton(
                        systemName: "checklist.checked",
                        help: "Select all items on this page."
                    ) {
                        for item in pagedHistoryItems {
                            selectedHistoryIDs.insert(item.persistentModelID)
                        }
                        touchHistoryActivity()
                    }

                    iconControlButton(
                        systemName: "xmark.circle",
                        help: "Clear selection."
                    ) {
                        selectedHistoryIDs.removeAll()
                        touchHistoryActivity()
                    }

                    iconControlButton(
                        systemName: "trash.slash",
                        role: .destructive,
                        help: "Delete selected items."
                    ) {
                        showDeleteSelectedConfirmation = true
                    }
                    .disabled(selectedHistoryIDs.isEmpty)

                    iconControlButton(
                        systemName: "trash",
                        role: .destructive,
                        help: "Delete current page."
                    ) {
                        showDeletePageConfirmation = true
                    }
                    .disabled(pagedHistoryItems.isEmpty)

                    iconControlButton(
                        systemName: "trash.circle.fill",
                        role: .destructive,
                        help: "Delete all history."
                    ) {
                        showDeleteAllConfirmation = true
                    }
                    .disabled(items.isEmpty)
                }

                Divider()

                ForEach(pagedHistoryItems) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 8) {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { selectedHistoryIDs.contains(item.persistentModelID) },
                                    set: { newValue in
                                        if newValue {
                                            selectedHistoryIDs.insert(item.persistentModelID)
                                        } else {
                                            selectedHistoryIDs.remove(item.persistentModelID)
                                        }
                                    }
                                )
                            )
                            .labelsHidden()

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(item.text.isEmpty ? "(empty)" : item.text)
                                    .textSelection(.enabled)
                            }

                            Spacer()

                            iconControlButton(
                                systemName: "trash",
                                role: .destructive,
                                help: "Delete this item."
                            ) {
                                pendingHistoryItemDeletionID = item.persistentModelID
                            }
                        }
                    }
                    Divider()
                }

                HStack {
                    Text("Page \(historyPage + 1) of \(max(historyPageCount, 1))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    iconControlButton(
                        systemName: "chevron.left",
                        help: "Previous page."
                    ) {
                        historyPage = max(0, historyPage - 1)
                        selectedHistoryIDs.removeAll()
                        touchHistoryActivity()
                    }
                    .disabled(historyPage == 0)
                    iconControlButton(
                        systemName: "chevron.right",
                        help: "Next page."
                    ) {
                        historyPage = min(max(0, historyPageCount - 1), historyPage + 1)
                        selectedHistoryIDs.removeAll()
                        touchHistoryActivity()
                    }
                    .disabled(historyPage >= max(0, historyPageCount - 1))
                }
            }
            .onAppear { refreshHistoryAutoLockTimer() }
            .onChange(of: selectedHistoryIDs.count) { _, _ in touchHistoryActivity() }
        }
    }

    private var pagedHistoryItems: [Item] {
        guard !items.isEmpty else { return [] }
        let safePage = min(max(0, historyPage), max(0, historyPageCount - 1))
        let start = safePage * historyPageSize
        guard start < items.count else { return [] }
        let end = min(start + historyPageSize, items.count)
        return Array(items[start..<end])
    }

    private var historyPageCount: Int {
        guard historyPageSize > 0 else { return 1 }
        return Int(ceil(Double(items.count) / Double(historyPageSize)))
    }

    private var customInstalledModels: [InstalledModel] {
        let builtinIDs = Set(modelManager.availableModels.map(\.id))
        return installedModels
            .filter { !builtinIDs.contains($0.id) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var pendingModelDeletionTitle: String {
        guard let id = pendingModelDeletionID else { return "model" }
        if let installed = installedModels.first(where: { $0.id == id }) {
            return installed.displayName
        }
        if let option = modelManager.availableModels.first(where: { $0.id == id }) {
            return option.displayName
        }
        return id
    }

    private var isModelDeleteDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingModelDeletionID != nil },
            set: { if !$0 { pendingModelDeletionID = nil } }
        )
    }

    private var isHistoryItemDeleteDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingHistoryItemDeletionID != nil },
            set: { if !$0 { pendingHistoryItemDeletionID = nil } }
        )
    }

    private func iconControlButton(
        systemName: String,
        role: ButtonRole? = nil,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func banner(text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var floatingBanner: some View {
        if let modelInstallError {
            banner(text: modelInstallError, color: .red)
                .frame(maxWidth: 460)
        } else if let modelInstallSuccess {
            banner(text: modelInstallSuccess, color: .green)
                .frame(maxWidth: 460)
        }
    }

    private func bootstrapSettingsIfNeeded() {
        guard settings.isEmpty else { return }
        modelContext.insert(AppSettings())
    }

    private func migrateLegacyLanguageIfNeeded() {
        guard let current = settings.first else { return }
        let normalized = current.languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized == "en" else { return }
        if let inferred = inferredLanguageCode(), inferred != "en" {
            current.languageCode = "auto"
            current.updatedAt = .now
        }
    }

    @MainActor
    private func installModel(_ option: RemoteModelOption) async {
        beginUserAction()
        do {
            let localURL = try await modelManager.install(option)
            upsertInstalledModel(
                id: option.id,
                displayName: option.displayName,
                sourceURL: option.sourceURL.absoluteString,
                localURL: localURL
            )
            selectInstalledModel(id: option.id)
            modelInstallSuccess = "Installed \(option.displayName)"
            modelInstallError = nil
        } catch {
            modelInstallError = "Install failed: \(error.localizedDescription)"
            modelInstallSuccess = nil
        }
    }

    @MainActor
    private func validateAndQueueRemoteModel() async {
        beginUserAction()
        let trimmedURL = customModelURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let remoteURL = URL(string: trimmedURL), !trimmedURL.isEmpty else {
            modelInstallError = "Invalid model URL."
            modelInstallSuccess = nil
            return
        }

        let preferredName = customModelNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let validated = try await modelManager.validateRemoteModelURL(
                remoteURL,
                preferredModelID: preferredName.isEmpty ? nil : preferredName
            )
            let displayName = preferredName.isEmpty ? validated.modelID : preferredName
            let candidate = PendingRemoteModelCandidate(
                id: validated.downloadURL.absoluteString,
                displayName: displayName,
                modelID: validated.modelID,
                downloadURL: validated.downloadURL,
                sizeBytes: validated.sizeBytes
            )
            pendingRemoteModels.removeAll { $0.id == candidate.id }
            pendingRemoteModels.append(candidate)
            modelInstallSuccess = "Validated \(displayName). Ready to download."
            modelInstallError = nil
        } catch {
            modelInstallError = "Validation failed: \(error.localizedDescription)"
            modelInstallSuccess = nil
        }
    }

    @MainActor
    private func installPendingRemoteModel(_ candidate: PendingRemoteModelCandidate) async {
        beginUserAction()
        do {
            let localURL = try await modelManager.install(from: candidate.downloadURL, modelID: candidate.modelID)
            upsertInstalledModel(
                id: candidate.modelID,
                displayName: candidate.displayName,
                sourceURL: candidate.downloadURL.absoluteString,
                localURL: localURL
            )
            selectInstalledModel(id: candidate.modelID)
            modelInstallSuccess = "Installed \(candidate.displayName)"
            modelInstallError = nil
        } catch {
            modelInstallError = "Install failed: \(error.localizedDescription)"
            modelInstallSuccess = nil
        }
    }

    private func importLocalModelFromDisk() {
        beginUserAction()
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import Model"

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        let preferredName = customModelNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let localURL = try modelManager.importLocalModel(
                from: sourceURL,
                modelID: preferredName.isEmpty ? nil : preferredName
            )
            let modelID = localURL.lastPathComponent
            let displayName = preferredName.isEmpty ? modelID : preferredName
            upsertInstalledModel(
                id: modelID,
                displayName: displayName,
                sourceURL: sourceURL.path,
                localURL: localURL
            )
            selectInstalledModel(id: modelID)
            modelInstallSuccess = "Imported \(displayName)"
            modelInstallError = nil
        } catch {
            modelInstallError = "Import failed: \(error.localizedDescription)"
            modelInstallSuccess = nil
        }
    }

    private func upsertInstalledModel(id: String, displayName: String, sourceURL: String, localURL: URL) {
        let sizeBytes = (try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        if let existing = installedModels.first(where: { $0.id == id }) {
            existing.displayName = displayName
            existing.sourceURL = sourceURL
            existing.localPath = localURL.path
            existing.sizeBytes = sizeBytes
            existing.lastUsedAt = .now
            return
        }

        let record = InstalledModel(
            id: id,
            displayName: displayName,
            sourceURL: sourceURL,
            localPath: localURL.path,
            sizeBytes: sizeBytes,
            lastUsedAt: .now
        )
        modelContext.insert(record)
    }

    private func useModel(_ option: RemoteModelOption) {
        beginUserAction()
        ensureInstalledModelRecord(option)
        selectInstalledModel(id: option.id)
        modelInstallSuccess = "Using \(option.displayName)"
        modelInstallError = nil
    }

    private func useInstalledModel(_ model: InstalledModel) {
        beginUserAction()
        selectInstalledModel(id: model.id)
        modelInstallSuccess = "Using \(model.displayName)"
        modelInstallError = nil
    }

    private func selectInstalledModel(id: String) {
        let targetSettings = ensureSettingsRecord()
        targetSettings.selectedModelID = id
        targetSettings.updatedAt = .now

        for model in installedModels {
            model.isActive = (model.id == id)
            if model.isActive {
                model.lastUsedAt = .now
            }
        }
    }

    private func ensureSettingsRecord() -> AppSettings {
        if let first = settings.first {
            return first
        }
        let newSettings = AppSettings()
        modelContext.insert(newSettings)
        return newSettings
    }

    private func ensureInstalledModelRecord(_ option: RemoteModelOption) {
        guard
            let localURL = try? modelManager.localURL(for: option),
            FileManager.default.fileExists(atPath: localURL.path)
        else {
            return
        }
        upsertInstalledModel(
            id: option.id,
            displayName: option.displayName,
            sourceURL: option.sourceURL.absoluteString,
            localURL: localURL
        )
    }

    private func deleteInstalledModel(byID id: String) {
        beginUserAction()
        guard let existing = installedModels.first(where: { $0.id == id }) else { return }

        do {
            try removeModelFilesFromDisk(modelID: id, localPath: existing.localPath)
            modelContext.delete(existing)

            if settings.first?.selectedModelID == id {
                let fallback = installedModels.first(where: { $0.id != id })?.id ?? ""
                let targetSettings = ensureSettingsRecord()
                targetSettings.selectedModelID = fallback
                targetSettings.updatedAt = .now
            }

            modelInstallSuccess = "Deleted \(existing.displayName)"
            modelInstallError = nil
        } catch {
            modelInstallError = "Delete failed: \(error.localizedDescription)"
            modelInstallSuccess = nil
        }
    }

    private func removeModelFilesFromDisk(modelID: String, localPath: String) throws {
        let fm = FileManager.default
        let localURL = URL(fileURLWithPath: localPath)
        if fm.fileExists(atPath: localURL.path) {
            try fm.removeItem(at: localURL)
        }

        if let canonicalURL = try? modelManager.localURL(forModelID: modelID),
           canonicalURL.path != localURL.path,
           fm.fileExists(atPath: canonicalURL.path) {
            try fm.removeItem(at: canonicalURL)
        }
    }

    private func isSelectedModel(_ option: RemoteModelOption) -> Bool {
        settings.first?.selectedModelID == option.id
    }

    private func isSelectedModelID(_ id: String) -> Bool {
        settings.first?.selectedModelID == id
    }

    private func isInstalledModelID(_ id: String) -> Bool {
        installedModels.contains(where: { $0.id == id })
    }

    private var selectedModelTitle: String {
        let selectedID = settings.first?.selectedModelID ?? ""
        guard !selectedID.isEmpty else { return "-" }
        if let installed = installedModels.first(where: { $0.id == selectedID }) {
            return installed.displayName
        }
        return selectedID
    }

    private var effectiveLanguageLabel: String {
        let selected = settings.first?.languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "auto"
        let normalized = selected.isEmpty ? "auto" : selected
        guard normalized == "auto" else { return normalized.uppercased() }
        if let inferred = inferredLanguageCode(), inferred != "auto" {
            return "Auto (\(inferred.uppercased()))"
        }
        return "Auto"
    }

    private var languageCodeBinding: Binding<String> {
        Binding(
            get: {
                let current = settings.first?.languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "auto"
                if current.isEmpty {
                    return "auto"
                }
                return languageOptions.contains(where: { $0.id == current }) ? current : "auto"
            },
            set: { newValue in
                let targetSettings = ensureSettingsRecord()
                targetSettings.languageCode = newValue
                targetSettings.updatedAt = .now
            }
        )
    }

    private var selectedLanguageTitle: String {
        let selected = languageCodeBinding.wrappedValue
        if let option = languageOptions.first(where: { $0.id == selected }) {
            return "\(option.title) (\(option.id.uppercased()))"
        }
        return selected.uppercased()
    }

    private var filteredLanguageOptions: [LanguageOption] {
        let query = languageSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return languageOptions }
        return languageOptions.filter {
            $0.id.lowercased().contains(query) || $0.title.lowercased().contains(query)
        }
    }

    private func inferredLanguageCode() -> String? {
        let selectedID = settings.first?.selectedModelID ?? ""
        guard !selectedID.isEmpty else { return nil }

        if let installed = installedModels.first(where: { $0.id == selectedID }) {
            return detectLanguageCode(from: "\(installed.id) \(installed.displayName) \(installed.sourceURL)")
        }
        return detectLanguageCode(from: selectedID)
    }

    private func detectLanguageCode(from text: String) -> String? {
        let lower = text.lowercased()
        let knownCodes = languageOptions.map(\.id).filter { $0 != "auto" }
        for code in knownCodes {
            if lower.contains(".\(code).") || lower.contains("-\(code)-") || lower.hasSuffix(".\(code)") || lower.contains("_\(code)_") {
                return code
            }
        }
        return nil
    }

    private var autoInsertEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.first?.autoInsertEnabled ?? true },
            set: { newValue in
                let targetSettings = ensureSettingsRecord()
                targetSettings.autoInsertEnabled = newValue
                targetSettings.updatedAt = .now
            }
        )
    }

    private var insertModeBinding: Binding<InsertMode> {
        Binding(
            get: { settings.first?.insertMode ?? .keyEvents },
            set: { newValue in
                let targetSettings = ensureSettingsRecord()
                targetSettings.insertMode = newValue
                targetSettings.updatedAt = .now
            }
        )
    }

    private var microphoneStatusText: String {
        switch permissionsManager.microphoneStatus {
        case .notDetermined:
            return "Not requested"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        @unknown default:
            return "Unknown"
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formattedSpeed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "-" }
        let mbps = bytesPerSecond / (1024 * 1024)
        return String(format: "%.2f MB/s", mbps)
    }

    private func formattedETA(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "-" }
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    private func saveExecutablePath() {
        beginUserAction()
        appState.whisperExecutablePath = executablePathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        modelInstallSuccess = "Updated whisper executable path"
        modelInstallError = nil
    }

    private func beginUserAction() {
        bannerAutoClearTask?.cancel()
        modelInstallError = nil
        modelInstallSuccess = nil
    }

    private func refreshBannerAutoClear() {
        bannerAutoClearTask?.cancel()
        guard modelInstallError != nil || modelInstallSuccess != nil else { return }
        bannerAutoClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            modelInstallError = nil
            modelInstallSuccess = nil
        }
    }

    private func authenticateHistoryAccess() {
        configureSettingsWindowBehavior()
        bringSettingsWindowToFront()

        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            historyAuthError = error?.localizedDescription ?? "System authentication is not available."
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock transcript history in Zictate"
        ) { success, evalError in
            DispatchQueue.main.async {
                bringSettingsWindowToFront()
                if success {
                    historyUnlocked = true
                    historyAuthError = nil
                    refreshHistoryAutoLockTimer()
                } else {
                    historyAuthError = evalError?.localizedDescription ?? "Authentication failed."
                }
            }
        }
    }

    private func deleteHistoryItem(_ item: Item) {
        selectedHistoryIDs.remove(item.persistentModelID)
        modelContext.delete(item)
        clampHistoryPagination()
        touchHistoryActivity()
    }

    private func deleteHistoryItem(id: PersistentIdentifier) {
        guard let item = items.first(where: { $0.persistentModelID == id }) else { return }
        deleteHistoryItem(item)
    }

    private func deleteSelectedHistoryItems() {
        guard !selectedHistoryIDs.isEmpty else { return }
        for item in items where selectedHistoryIDs.contains(item.persistentModelID) {
            modelContext.delete(item)
        }
        selectedHistoryIDs.removeAll()
        clampHistoryPagination()
        touchHistoryActivity()
    }

    private func deleteCurrentHistoryPage() {
        let toDelete = pagedHistoryItems
        for item in toDelete {
            selectedHistoryIDs.remove(item.persistentModelID)
            modelContext.delete(item)
        }
        clampHistoryPagination()
        touchHistoryActivity()
    }

    private func deleteAllHistoryItems() {
        for item in items {
            modelContext.delete(item)
        }
        selectedHistoryIDs.removeAll()
        historyPage = 0
        touchHistoryActivity()
    }

    private func clampHistoryPagination() {
        let pageCount = max(1, historyPageCount)
        historyPage = min(historyPage, pageCount - 1)
    }

    private func touchHistoryActivity() {
        guard historyUnlocked else { return }
        refreshHistoryAutoLockTimer()
    }

    private func refreshHistoryAutoLockTimer() {
        historyAutoLockTask?.cancel()
        historyAutoLockTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled else { return }
            lockHistory()
        }
    }

    private func lockHistory() {
        historyUnlocked = false
        selectedHistoryIDs.removeAll()
        historyAuthError = nil
        historyAutoLockTask?.cancel()
        historyAutoLockTask = nil
    }

    private func configureSettingsWindowBehavior() {
        guard let settingsWindow = NSApplication.shared.windows.first(where: { $0.title.localizedCaseInsensitiveContains("settings") }) else {
            return
        }
        settingsWindow.hidesOnDeactivate = false
    }

    private func bringSettingsWindowToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let settingsWindow = NSApplication.shared.windows.first(where: { $0.title.localizedCaseInsensitiveContains("settings") }) {
            settingsWindow.orderFrontRegardless()
            settingsWindow.makeKey()
        }
    }
}

#Preview {
    let previewContainer = try! ModelContainer(
        for: Item.self, AppSettings.self, InstalledModel.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    ContentView()
        .environmentObject(AppState(modelContainer: previewContainer))
        .modelContainer(previewContainer)
}
