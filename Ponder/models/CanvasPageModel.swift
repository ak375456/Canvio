//
//  CanvasPageModel.swift
//  Ponder
//

import Foundation
import CoreGraphics
import SwiftData

@Model
class CanvasPageModel {
    @Attribute(.unique) var id: UUID
    var canvasID: UUID
    var contentCanvasID: UUID?
    var name: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var orderIndex: Int
    var createdAt: Date
    var updatedAt: Date
    var thumbnailData: Data? = nil

    init(
        canvasID: UUID,
        contentCanvasID: UUID? = nil,
        name: String = "Page 1",
        x: Double = 0,
        y: Double = 0,
        width: Double = 800,
        height: Double = 600,
        orderIndex: Int = 0
    ) {
        self.id = UUID()
        self.canvasID = canvasID
        self.contentCanvasID = contentCanvasID ?? canvasID
        self.name = name
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.orderIndex = orderIndex
        self.createdAt = Date()
        self.updatedAt = Date()
        self.thumbnailData = nil
    }

    var resolvedContentCanvasID: UUID {
        contentCanvasID ?? canvasID
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var center: CGPoint {
        CGPoint(x: x + width / 2, y: y + height / 2)
    }
}
