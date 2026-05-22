//
//  TableCellModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI

@Model
class TableCellModel {
    var id: UUID
    var tableID: UUID
    var row: Int
    var col: Int
    var value: String

    // Formatting
    var backgroundColorName: String   // "clear", "blue", "red" etc
    var textColorName: String         // "primary", "white", "black" etc
    var alignmentRaw: String          // "leading", "center", "trailing"
    var isBold: Bool
    var isMerged: Bool                // this cell is absorbed into a merge
    var mergeOriginRow: Int           // -1 if not part of a merge
    var mergeOriginCol: Int           // -1 if not part of a merge
    var colSpan: Int                  // 1 = normal, >1 = merge origin
    var rowSpan: Int                  // 1 = normal, >1 = merge origin

    // Default values here allow SwiftData to auto-migrate existing rows
    // without failing on "missing attribute values"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var alignment: TextAlignment {
        get {
            switch alignmentRaw {
            case "center":   return .center
            case "trailing": return .trailing
            default:         return .leading
            }
        }
        set {
            switch newValue {
            case .center:   alignmentRaw = "center"
            case .trailing: alignmentRaw = "trailing"
            default:        alignmentRaw = "leading"
            }
        }
    }

    init(tableID: UUID, row: Int, col: Int) {
        self.id = UUID()
        self.tableID = tableID
        self.row = row
        self.col = col
        self.value = ""
        self.backgroundColorName = "clear"
        self.textColorName = "adaptive"
        self.alignmentRaw = "leading"
        self.isBold = false
        self.isMerged = false
        self.mergeOriginRow = -1
        self.mergeOriginCol = -1
        self.colSpan = 1
        self.rowSpan = 1
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
