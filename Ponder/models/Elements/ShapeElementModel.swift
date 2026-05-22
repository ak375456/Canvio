//
//  ShapeElementModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI

@Model
class ShapeElementModel: LayerableElement {
    var id: UUID
    var canvasID: UUID
    var shapeTypeRaw: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double
    var strokeColorName: String
    var fillColorName: String
    var hasFill: Bool
    var strokeWidth: Double
    var hasArrowHead: Bool
    var triangleVariantRaw: String
    var polygonSides: Int
    var createdAt: Date
    var updatedAt: Date
    var zIndex: Int = 0

    var shapeKind: ShapeKind {
        get { ShapeKind(rawValue: shapeTypeRaw) ?? .rectangle }
        set { shapeTypeRaw = newValue.rawValue }
    }

    var triangleVariant: TriangleVariant {
        get { TriangleVariant(rawValue: triangleVariantRaw) ?? .equilateral }
        set { triangleVariantRaw = newValue.rawValue }
    }

    init(canvasID: UUID, kind: ShapeKind, x: Double = 0, y: Double = 0) {
        self.id = UUID()
        self.canvasID = canvasID
        self.shapeTypeRaw = kind.rawValue
        self.x = x
        self.y = y
        switch kind {
        case .line:      self.width = 180; self.height = 4
        case .rectangle: self.width = 160; self.height = 110
        case .triangle:  self.width = 140; self.height = 130
        case .polygon:   self.width = 140; self.height = 140
        case .circle:    self.width = 140; self.height = 140
        }
        self.rotation = 0
        self.strokeColorName = "primary"
        self.fillColorName = "blue"
        self.hasFill = false
        self.strokeWidth = 2.5
        self.hasArrowHead = false
        self.triangleVariantRaw = TriangleVariant.equilateral.rawValue
        self.polygonSides = 6
        self.createdAt = Date()
        self.updatedAt = Date()
        self.zIndex = 0
    }

    var layerTitle: String { shapeKind.title }
    var layerIcon: String { shapeKind.icon }
    var layerTint: Color { .purple }
}
