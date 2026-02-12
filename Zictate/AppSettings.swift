//
//  AppSettings.swift
//  Zictate
//
//  Created by Codex on 12/02/26.
//

import Foundation
import SwiftData

enum InsertMode: String, CaseIterable, Codable {
    case keyEvents
    case pasteboard
}

@Model
final class AppSettings {
    var selectedModelID: String
    var languageCode: String
    var autoInsertEnabled: Bool
    var insertModeRawValue: String
    var chunkDurationMs: Int
    var vadThreshold: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        selectedModelID: String = "ggml-base.en.bin",
        languageCode: String = "auto",
        autoInsertEnabled: Bool = true,
        insertMode: InsertMode = .keyEvents,
        chunkDurationMs: Int = 1200,
        vadThreshold: Double = 0.45,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.selectedModelID = selectedModelID
        self.languageCode = languageCode
        self.autoInsertEnabled = autoInsertEnabled
        self.insertModeRawValue = insertMode.rawValue
        self.chunkDurationMs = chunkDurationMs
        self.vadThreshold = vadThreshold
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var insertMode: InsertMode {
        get { InsertMode(rawValue: insertModeRawValue) ?? .keyEvents }
        set { insertModeRawValue = newValue.rawValue }
    }
}
