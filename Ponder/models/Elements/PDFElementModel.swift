//
//  PDFElementModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI

@Model
class PDFElementModel: LayerableElement {
    var id: UUID
    var canvasID: UUID
    // The reusable document asset. Existing records resolve to `id` until the
    // PDF workspace migration has synced them.
    var documentID: UUID?
    var pdfFileName: String
    var thumbnailFileName: String
    var originalName: String
    var pageCount: Int
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double
    var zIndex: Int
    var groupID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(canvasID: UUID, pdfFileName: String, thumbnailFileName: String,
         originalName: String, pageCount: Int,
         x: Double = 0, y: Double = 0) {
        let newID = UUID()
        self.id = newID
        self.canvasID = canvasID
        self.documentID = newID
        self.pdfFileName = pdfFileName
        self.thumbnailFileName = thumbnailFileName
        self.originalName = originalName
        self.pageCount = pageCount
        self.x = x
        self.y = y
        self.width = 220
        self.height = 280
        self.rotation = 0
        self.zIndex = 0
        self.groupID = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var layerTitle: String { originalName.isEmpty ? "PDF" : originalName }
    var layerIcon: String { "doc.richtext" }
    var layerTint: Color { .red }

    var resolvedDocumentID: UUID { documentID ?? id }
}
