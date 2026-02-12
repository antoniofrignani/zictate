//
//  TextInsertionService.swift
//  Zictate
//
//  Created by Codex on 12/02/26.
//

import AppKit
import ApplicationServices
import Foundation

final class TextInsertionService {
    func insert(_ text: String, mode: InsertMode) {
        guard !text.isEmpty else { return }
        switch mode {
        case .pasteboard:
            pasteAtCursor(text)
        case .keyEvents:
            typeAtCursor(text)
        }
    }

    private func pasteAtCursor(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        vUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false)

        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }

    private func typeAtCursor(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            return
        }
        down.keyboardSetUnicodeString(stringLength: text.utf16.count, unicodeString: Array(text.utf16))
        up.keyboardSetUnicodeString(stringLength: text.utf16.count, unicodeString: Array(text.utf16))
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

