//
//  Item.swift
//  webiqu
//
//  Created by Umut Can Arda on 5/13/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
