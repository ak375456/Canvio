//
//  AudioElementModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI

@Model
class AudioElementModel: LayerableElement {
    var id: UUID
    var canvasID: UUID
    var audioFileName: String      // stored in Documents/CanvasAudio/
    var originalName: String       // display name
    var duration: Double           // seconds
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double
    var zIndex: Int
    var groupID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(canvasID: UUID, audioFileName: String, originalName: String,
         duration: Double, x: Double = 0, y: Double = 0) {
        self.id = UUID()
        self.canvasID = canvasID
        self.audioFileName = audioFileName
        self.originalName = originalName
        self.duration = duration
        self.x = x
        self.y = y
        self.width = 260
        self.height = 90
        self.rotation = 0
        self.zIndex = 0
        self.groupID = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var layerTitle: String { originalName.isEmpty ? "Audio" : originalName }
    var layerIcon: String { "waveform" }
    var layerTint: Color { .pink }
}
