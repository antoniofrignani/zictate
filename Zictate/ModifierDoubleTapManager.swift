//
//  ModifierDoubleTapManager.swift
//  Zictate
//
//  Created by Codex on 12/02/26.
//

import AppKit
import Carbon.HIToolbox
import Foundation

enum DoubleTapModifierKey: String, CaseIterable, Identifiable {
    case leftControl
    case rightControl
    case leftShift
    case rightShift
    case leftOption
    case rightOption
    case leftCommand
    case rightCommand
    case capsLock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leftControl: return "Left Control"
        case .rightControl: return "Right Control"
        case .leftShift: return "Left Shift"
        case .rightShift: return "Right Shift"
        case .leftOption: return "Left Option"
        case .rightOption: return "Right Option"
        case .leftCommand: return "Left Command"
        case .rightCommand: return "Right Command"
        case .capsLock: return "Caps Lock"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .leftControl: return 59
        case .rightControl: return 62
        case .leftShift: return 56
        case .rightShift: return 60
        case .leftOption: return 58
        case .rightOption: return 61
        case .leftCommand: return 55
        case .rightCommand: return 54
        case .capsLock: return 57
        }
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .leftControl, .rightControl:
            return .control
        case .leftShift, .rightShift:
            return .shift
        case .leftOption, .rightOption:
            return .option
        case .leftCommand, .rightCommand:
            return .command
        case .capsLock:
            return .capsLock
        }
    }
}

final class ModifierDoubleTapManager {
    static let shared = ModifierDoubleTapManager()

    var onTrigger: (() -> Void)?
    var maxIntervalSeconds: TimeInterval = 0.35

    var selectedKey: DoubleTapModifierKey = .rightShift {
        didSet {
            lastTapAt = nil
        }
    }

    var isEnabled = false {
        didSet {
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lastTapAt: Date?

    private init() {}

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        guard localMonitor == nil, globalMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
    }

    private func stopMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        lastTapAt = nil
    }

    private func handle(_ event: NSEvent) {
        guard isEnabled else { return }
        guard event.type == .flagsChanged else { return }
        guard event.keyCode == selectedKey.keyCode else { return }

        let isPressPhase = event.modifierFlags.contains(selectedKey.modifierFlag)
        guard isPressPhase else { return }

        let now = Date()
        if let lastTapAt, now.timeIntervalSince(lastTapAt) <= maxIntervalSeconds {
            self.lastTapAt = nil
            onTrigger?()
        } else {
            self.lastTapAt = now
        }
    }
}

