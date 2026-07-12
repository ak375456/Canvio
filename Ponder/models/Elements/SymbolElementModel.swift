//
//  SymbolElementModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI

@Model
class SymbolElementModel: LayerableElement {
    var id:          UUID
    var canvasID:    UUID
    var symbolName:  String
    var colorName:   String
    var fontSize:    Double
    var x:           Double
    var y:           Double
    var createdAt:   Date
    var updatedAt:   Date
    var isLayerHidden: Bool = false
    var layerOpacity: Double = 1
    var zIndex:      Int
    var groupID:     UUID?

    init(canvasID: UUID, symbolName: String,
         colorName: String = "primary", fontSize: Double = 48,
         x: Double = 0, y: Double = 0) {
        self.id         = UUID()
        self.canvasID   = canvasID
        self.symbolName = symbolName
        self.colorName  = colorName
        self.fontSize   = fontSize
        self.x          = x
        self.y          = y
        self.createdAt  = Date()
        self.updatedAt  = Date()
        self.zIndex     = 0
        self.groupID    = nil
    }

    var layerTitle: String { symbolName }
    var layerIcon:  String { symbolName }
    var layerTint:  Color  { .cyan }
}
