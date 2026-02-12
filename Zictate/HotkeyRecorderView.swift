//
//  HotkeyRecorderView.swift
//  Zictate
//
//  Created by Codex on 12/02/26.
//

import AppKit
import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var shortcut: HotkeyShortcut
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 12) {
            Text(shortcut.displayString)
                .font(.system(.body, design: .monospaced))

            Button(isRecording ? "Press keys..." : "Record Shortcut") {
                toggleRecording()
            }

            if isRecording {
                Button("Cancel", role: .cancel) {
                    stopRecording()
                }
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !modifiers.isEmpty else {
                NSSound.beep()
                return nil
            }

            shortcut = HotkeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}

