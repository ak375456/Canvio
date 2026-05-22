//
//  TextElementModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI

@Model
class TextElementModel: LayerableElement {
    var id: UUID
    var canvasID: UUID
    var text: String
    var x: Double
    var y: Double
    var fontSize: Double
    var isBold: Bool
    var isItalic: Bool
    // NEW — default false for safe SwiftData migration
    var isUnderline: Bool = false
    var colorName: String
    var fontName: String = "system"
    // NEW — "leading" / "center" / "trailing", default "leading"
    var alignmentRaw: String = "leading"
    var zIndex: Int = 0
    var updatedAt: Date = Date()

    init(canvasID: UUID, text: String = "", x: Double = 0, y: Double = 0) {
        self.id          = UUID()
        self.canvasID    = canvasID
        self.text        = text
        self.x           = x
        self.y           = y
        self.fontSize    = 16
        self.isBold      = false
        self.isItalic    = false
        self.isUnderline = false
        self.colorName   = "primary"
        self.fontName    = "system"
        self.alignmentRaw = "leading"
        self.zIndex      = 0
        self.updatedAt   = Date()
    }

    // MARK: - Computed helpers

    var textAlignment: TextAlignment {
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

    var multilineAlignment: HorizontalAlignment {
        switch textAlignment {
        case .center:   return .center
        case .trailing: return .trailing
        default:        return .leading
        }
    }

    // MARK: - LayerableElement
    var layerTitle: String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Text" : String(t.prefix(28))
    }
    var layerIcon:  String { "textformat" }
    var layerTint:  Color  { .blue }
}
