//
//  Item.swift
//  Zictate
//
//  Created by Antonio Frignani on 12/02/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    var text: String
    
    init(timestamp: Date, text: String = "") {
        self.timestamp = timestamp
        self.text = text
    }
}
