//
//  DrawingElementModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI
import PencilKit
import Combine

@Model
class DrawingElementModel: LayerableElement {
    var id: UUID
    var canvasID: UUID
    var drawingData: Data
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double
    var zIndex: Int
    var groupID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var isCanvasDrawing: Bool   // ← true = no background card (Draw mode)

    init(canvasID: UUID, x: Double = 0, y: Double = 0,
         width: Double = 340, height: Double = 240,
         isCanvasDrawing: Bool = false) {
        self.id = UUID()
        self.canvasID = canvasID
        self.drawingData = Data()
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = 0
        self.zIndex = 0
        self.groupID = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isCanvasDrawing = isCanvasDrawing
    }

    var layerTitle: String { "Drawing" }
    var layerIcon: String { "pencil.and.scribble" }
    var layerTint: Color { .orange }

    var pkDrawing: PKDrawing {
        get { (try? PKDrawing(data: drawingData)) ?? PKDrawing() }
        set { drawingData = (try? newValue.dataRepresentation()) ?? Data() }
    }
}
