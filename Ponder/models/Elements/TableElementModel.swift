//
//  TableElementModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI

@Model
class TableElementModel: LayerableElement {
    var id: UUID
    var canvasID: UUID
    var x: Double
    var y: Double
    var rowCount: Int
    var colCount: Int
    var cellWidth: Double
    var cellHeight: Double
    var rotation: Double
    var zIndex: Int
    var createdAt: Date
    var updatedAt: Date

    // Header colors
    var colHeaderColorName: String
    var rowHeaderColorName: String
    var showColHeaders: Bool
    var showRowHeaders: Bool

    init(canvasID: UUID, rows: Int, cols: Int, x: Double = 0, y: Double = 0) {
        self.id = UUID()
        self.canvasID = canvasID
        self.rowCount = rows
        self.colCount = cols
        self.x = x
        self.y = y
        self.cellWidth = 90
        self.cellHeight = 36
        self.rotation = 0
        self.zIndex = 0
        self.colHeaderColorName = "systemGray6"
        self.rowHeaderColorName = "systemGray6"
        self.showColHeaders = true
        self.showRowHeaders = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // Computed total size
    var totalWidth: Double {
        let headerW = showRowHeaders ? cellWidth * 0.6 : 0
        return headerW + cellWidth * Double(colCount)
    }

    var totalHeight: Double {
        let headerH = showColHeaders ? cellHeight : 0
        return headerH + cellHeight * Double(rowCount)
    }

    // LayerableElement
    var layerTitle: String { "Table \(rowCount)×\(colCount)" }
    var layerIcon: String { "tablecells" }
    var layerTint: Color { .indigo }
}
