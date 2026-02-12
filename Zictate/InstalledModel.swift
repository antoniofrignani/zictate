//
//  InstalledModel.swift
//  Zictate
//
//  Created by Codex on 12/02/26.
//

import Foundation
import SwiftData

@Model
final class InstalledModel {
    @Attribute(.unique) var id: String
    var displayName: String
    var sourceURL: String
    var localPath: String
    var sizeBytes: Int64
    var sha256: String?
    var installedAt: Date
    var lastUsedAt: Date?
    var isActive: Bool

    init(
        id: String,
        displayName: String,
        sourceURL: String,
        localPath: String,
        sizeBytes: Int64,
        sha256: String? = nil,
        installedAt: Date = .now,
        lastUsedAt: Date? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.sourceURL = sourceURL
        self.localPath = localPath
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.installedAt = installedAt
        self.lastUsedAt = lastUsedAt
        self.isActive = isActive
    }
}
