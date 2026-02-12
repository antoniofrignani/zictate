//
//  DictationOverlayController.swift
//  Zictate
//
//  Created by Codex on 12/02/26.
//

import AppKit
import SwiftUI

@MainActor
final class DictationOverlayController {
    static let shared = DictationOverlayController()

    private var panel: NSPanel?

    private init() {}

    func show(appState: AppState) {
        let panel = self.panel ?? makePanel(appState: appState)
        panel.contentView = NSHostingView(
            rootView: DictationOverlayView()
                .environmentObject(appState)
        )
        self.panel = panel

        position(panel: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func makePanel(appState: AppState) -> NSPanel {
        let size = NSSize(width: 320, height: 82)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: DictationOverlayView()
                .environmentObject(appState)
        )

        return panel
    }

    private func position(panel: NSPanel) {
        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else { return }

        let frame = panel.frame
        let visible = screen.visibleFrame
        let x = visible.midX - frame.width / 2
        let y = visible.minY + 28
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct DictationOverlayView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            WaveformBars(levels: appState.liveWaveform)
                .frame(width: 238)
                .frame(height: 30)

            Button {
                appState.stopDictation()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(width: 26, height: 26)
                    .background(Color.red.opacity(0.85), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!appState.isDictating)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .padding(8)
    }
}

private struct WaveformBars: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { proxy in
            let count = max(levels.count, 1)
            let spacing: CGFloat = 1
            let barWidth = max((proxy.size.width - CGFloat(count - 1) * spacing) / CGFloat(count), 1)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.47, green: 0.87, blue: 1.0),
                                    Color(red: 0.30, green: 0.56, blue: 1.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(
                            width: barWidth,
                            height: max(4, CGFloat(level) * proxy.size.height)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
