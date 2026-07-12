//
//  YouTubeElementModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI

@Model
class YouTubeElementModel: LayerableElement {
    var id: UUID
    var canvasID: UUID
    var videoID: String
    var originalURL: String
    var title: String
    var thumbnailURL: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var playbackSeconds: Double = 0
    var zIndex: Int
    var groupID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var isLayerHidden: Bool = false
    var layerOpacity: Double = 1

    init(canvasID: UUID, videoID: String, originalURL: String,
         title: String = "", thumbnailURL: String = "",
         x: Double = 0, y: Double = 0, width: Double = 320, height: Double = 220) {
        self.id = UUID()
        self.canvasID = canvasID
        self.videoID = videoID
        self.originalURL = originalURL
        self.title = title
        self.thumbnailURL = thumbnailURL.isEmpty
            ? "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg"
            : thumbnailURL
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.playbackSeconds = 0
        self.zIndex = 0
        self.groupID = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var embedURL: URL? {
        URL(string: "https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0&modestbranding=1&enablejsapi=1")
    }

    var watchURL: URL? {
        URL(string: originalURL.isEmpty ? "https://www.youtube.com/watch?v=\(videoID)" : originalURL)
    }

    var layerTitle: String { title.isEmpty ? "YouTube Video" : title }
    var layerIcon: String { "play.rectangle.fill" }
    var layerTint: Color { .red }
}
