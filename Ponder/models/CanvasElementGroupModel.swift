//
//  CanvasElementGroupModel.swift
//  Ponder
//

import Foundation
import SwiftData

@Model
class CanvasElementGroupModel {
    var id: UUID
    var canvasID: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(canvasID: UUID, name: String = "Group") {
        self.id = UUID()
        self.canvasID = canvasID
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
