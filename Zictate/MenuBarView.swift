//
//  MenuBarView.swift
//  Zictate
//
//  Created by Codex on 12/02/26.
//

import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label(
            appState.isDictating ? "Recording" : (appState.isProcessing ? "Transcribing" : "Idle"),
            systemImage: appState.isDictating ? "record.circle.fill" : (appState.isProcessing ? "waveform.badge.magnifyingglass" : "pause.circle")
        )
        .foregroundStyle(appState.isDictating ? .red : .secondary)

        Divider()

        Button(appState.isDictating ? "Stop Dictation" : "Start Dictation") {
            appState.toggleDictation()
        }
        .disabled(appState.isProcessing)

        if appState.doubleTapEnabled {
            Text("Trigger: Double-tap \(appState.doubleTapKey.displayName)")
        } else {
            Text("Shortcut: \(appState.shortcut.displayString)")
        }

        if !appState.lastTranscript.isEmpty {
            Divider()
            Text(appState.lastTranscript)
                .lineLimit(3)
            Button("Insert Last Transcript") {
                appState.insertLastTranscriptAtCursor()
            }
        }

        if let lastError = appState.lastError {
            Divider()
            Text(lastError)
                .foregroundStyle(.red)
        }

        Divider()

        Button("Open Settings") {
            openWindow(id: "settings")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit Zictate") {
            NSApplication.shared.terminate(nil)
        }
    }
}
