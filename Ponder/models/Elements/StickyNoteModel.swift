//
//  StickyNoteModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI

enum StickyListStyle: String, Codable {
    case none
    case bullets
    case numbers
}

@Model
class StickyNoteModel: LayerableElement {
    var id: UUID
    var canvasID: UUID
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double
    var fontSize: Double
    var isBold: Bool
    var isItalic: Bool
    var fontName: String
    var colorName: String
    var listStyleRaw: String
    var isCollapsed: Bool = false
    var zIndex: Int = 0
    var groupID: UUID? = nil
    var updatedAt: Date = Date()
    var isLayerHidden: Bool = false
    var layerOpacity: Double = 1

    var listStyle: StickyListStyle {
        get { StickyListStyle(rawValue: listStyleRaw) ?? .none }
        set { listStyleRaw = newValue.rawValue }
    }

    init(canvasID: UUID, x: Double = 0, y: Double = 0) {
        self.id = UUID()
        self.canvasID = canvasID
        self.text = ""
        self.x = x
        self.y = y
        self.width = 190
        self.height = 150
        self.rotation = 0
        self.fontSize = 15
        self.isBold = false
        self.isItalic = false
        self.fontName = "system"
        self.colorName = "yellow"
        self.listStyleRaw = StickyListStyle.none.rawValue
        self.isCollapsed = false
        self.zIndex = 0
        self.groupID = nil
        self.updatedAt = Date()
    }

    var layerTitle: String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Sticky Note" : String(t.prefix(28))
    }
    var layerIcon: String { "note.text" }
    var layerTint: Color { .orange }
}
