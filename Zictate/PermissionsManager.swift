//
//  PermissionsManager.swift
//  Zictate
//
//  Created by Codex on 12/02/26.
//

import AppKit
import AVFoundation
import ApplicationServices
import Combine
import Foundation

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var microphoneStatus: AVAuthorizationStatus
    @Published private(set) var isAccessibilityTrusted: Bool

    init() {
        self.microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        self.isAccessibilityTrusted = AXIsProcessTrusted()
    }

    func refresh() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        isAccessibilityTrusted = AXIsProcessTrusted()
    }

    func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
