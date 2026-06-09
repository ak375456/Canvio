//
//  TodoListModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI

@Model
class TodoListModel: LayerableElement {
    var id: UUID
    var canvasID: UUID
    var title: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var colorName: String
    var createdAt: Date
    var updatedAt: Date
    var zIndex: Int = 0
    var groupID: UUID? = nil

    init(canvasID: UUID, x: Double = 0, y: Double = 0) {
        self.id = UUID()
        self.canvasID = canvasID
        self.title = "Todo"
        self.x = x
        self.y = y
        self.width = 280
        self.height = 320
        self.colorName = "blue"
        self.createdAt = Date()
        self.updatedAt = Date()
        self.zIndex = 0
        self.groupID = nil
    }

    var layerTitle: String {
        title.isEmpty ? "Todo List" : title
    }
    var layerIcon: String { "checklist" }
    var layerTint: Color { .green }
}
