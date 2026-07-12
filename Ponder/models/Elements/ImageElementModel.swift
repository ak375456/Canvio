//
//  ImageElementModel.swift
//  Ponder
//
//  Created by aftab fazal qayum on 12/05/2026.
//

//
//  ImageElementModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI

@Model
class ImageElementModel: LayerableElement {
    var id: UUID
    var canvasID: UUID
    var imageFileName: String   // filename only — resolved via ImageStorageService
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double
    var cornerRadius: Double
    var opacity: Double
    var zIndex: Int
    var groupID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var isLayerHidden: Bool = false
    var layerOpacity: Double = 1

    init(canvasID: UUID, imageFileName: String, x: Double = 0, y: Double = 0,
         width: Double = 240, height: Double = 180) {
        self.id = UUID()
        self.canvasID = canvasID
        self.imageFileName = imageFileName
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = 0
        self.cornerRadius = 0
        self.opacity = 1.0
        self.zIndex = 0
        self.groupID = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - LayerableElement
    var layerTitle: String { "Image" }
    var layerIcon: String { "photo" }
    var layerTint: Color { .cyan }
}
