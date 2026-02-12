//
//  GlobalHotkeyManager.swift
//  Zictate
//
//  Created by Codex on 12/02/26.
//

import Carbon.HIToolbox
import Foundation

final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    var onTrigger: (() -> Void)?

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let hotKeyID = EventHotKeyID(signature: FourCharCode("ZICT"), id: 1)

    private init() {
        installHandler()
    }

    deinit {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }

    func register(shortcut: HotkeyShortcut) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func installHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var incomingID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &incomingID
                )

                guard status == noErr else { return noErr }
                if incomingID.signature == manager.hotKeyID.signature && incomingID.id == manager.hotKeyID.id {
                    manager.onTrigger?()
                }
                return noErr
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )
    }
}

private extension FourCharCode {
    init(_ string: StaticString) {
        precondition(string.utf8CodeUnitCount == 4, "FourCharCode requires 4 ASCII chars")
        let bytes = string.withUTF8Buffer { buffer in
            [UInt32(buffer[0]), UInt32(buffer[1]), UInt32(buffer[2]), UInt32(buffer[3])]
        }
        self = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]
    }
}

