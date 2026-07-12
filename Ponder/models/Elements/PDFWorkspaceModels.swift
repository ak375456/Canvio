import Foundation
import SwiftData
import SwiftUI
import PencilKit

struct PDFNormalizedRect: Codable, Hashable, Identifiable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var id: String { "\(x)-\(y)-\(width)-\(height)" }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(x: Double(rect.minX), y: Double(rect.minY),
                  width: Double(rect.width), height: Double(rect.height))
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    static let fullPage = PDFNormalizedRect(x: 0, y: 0, width: 1, height: 1)
}

struct PDFPagePlacementRequest: Identifiable, Hashable {
    let id = UUID()
    var pageIndex: Int
    var cropRect: PDFNormalizedRect

    init(pageIndex: Int, cropRect: PDFNormalizedRect = .fullPage) {
        self.pageIndex = pageIndex
        self.cropRect = cropRect
    }
}

struct PDFSelectionPagePayload: Hashable {
    var pageIndex: Int
    var rects: [PDFNormalizedRect]
}

struct PDFSelectionPayload: Hashable {
    var text: String
    var pages: [PDFSelectionPagePayload]

    var firstPageIndex: Int? { pages.first?.pageIndex }
    var firstPageRects: [PDFNormalizedRect] { pages.first?.rects ?? [] }
}

@Model
final class PDFPageElementModel: LayerableElement {
    @Attribute(.unique) var id: UUID
    var documentID: UUID
    var canvasID: UUID
    var pdfFileName: String
    var originalName: String
    var pageIndex: Int
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double
    var cropX: Double
    var cropY: Double
    var cropWidth: Double
    var cropHeight: Double
    var showsAnnotations: Bool
    var zIndex: Int
    var groupID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var isLayerHidden: Bool = false
    var layerOpacity: Double = 1

    init(documentID: UUID, canvasID: UUID, pageIndex: Int,
         pdfFileName: String = "", originalName: String = "Document",
         cropRect: PDFNormalizedRect = .fullPage,
         x: Double = 0, y: Double = 0,
         width: Double = 320, height: Double = 420) {
        self.id = UUID()
        self.documentID = documentID
        self.canvasID = canvasID
        self.pdfFileName = pdfFileName
        self.originalName = originalName
        self.pageIndex = pageIndex
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = 0
        self.cropX = cropRect.x
        self.cropY = cropRect.y
        self.cropWidth = cropRect.width
        self.cropHeight = cropRect.height
        self.showsAnnotations = true
        self.zIndex = 0
        self.groupID = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var cropRect: PDFNormalizedRect {
        get { PDFNormalizedRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight) }
        set {
            cropX = newValue.x
            cropY = newValue.y
            cropWidth = newValue.width
            cropHeight = newValue.height
        }
    }

    var layerTitle: String {
        cropRect == .fullPage ? "PDF Page \(pageIndex + 1)" : "PDF Crop · Page \(pageIndex + 1)"
    }
    var layerIcon: String { cropRect == .fullPage ? "doc.text.image" : "crop" }
    var layerTint: Color { .red }
}

@Model
final class PDFHighlightModel {
    @Attribute(.unique) var id: UUID
    var documentID: UUID
    var canvasID: UUID
    var pageIndex: Int
    var selectedText: String
    var rectsData: Data
    var colorHex: String
    var opacity: Double
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(documentID: UUID, canvasID: UUID, pageIndex: Int,
         selectedText: String, rects: [PDFNormalizedRect],
         colorHex: String = "#FFD60A", opacity: Double = 0.35) {
        self.id = UUID()
        self.documentID = documentID
        self.canvasID = canvasID
        self.pageIndex = pageIndex
        self.selectedText = selectedText
        self.rectsData = (try? JSONEncoder().encode(rects)) ?? Data()
        self.colorHex = colorHex
        self.opacity = opacity
        self.note = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var rects: [PDFNormalizedRect] {
        get { (try? JSONDecoder().decode([PDFNormalizedRect].self, from: rectsData)) ?? [] }
        set { rectsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

@Model
final class PDFInkLayerModel {
    @Attribute(.unique) var id: UUID
    var documentID: UUID
    var canvasID: UUID
    var pageIndex: Int
    var drawingData: Data
    var coordinateWidth: Double
    var coordinateHeight: Double
    var formatVersion: Int
    var createdAt: Date
    var updatedAt: Date

    init(documentID: UUID, canvasID: UUID, pageIndex: Int,
         drawing: PKDrawing = PKDrawing(), coordinateSize: CGSize = CGSize(width: 1, height: 1)) {
        self.id = UUID()
        self.documentID = documentID
        self.canvasID = canvasID
        self.pageIndex = pageIndex
        self.drawingData = drawing.dataRepresentation()
        self.coordinateWidth = Double(max(1, coordinateSize.width))
        self.coordinateHeight = Double(max(1, coordinateSize.height))
        self.formatVersion = 1
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var pkDrawing: PKDrawing {
        get { (try? PKDrawing(data: drawingData)) ?? PKDrawing() }
        set { drawingData = newValue.dataRepresentation() }
    }
}

@Model
final class PDFReadingStateModel {
    @Attribute(.unique) var id: UUID
    var documentID: UUID
    var currentPageIndex: Int
    var scrollProgress: Double
    var zoomScale: Double
    var displayModeRaw: String
    var sidebarVisible: Bool
    var lastOpenedAt: Date
    var updatedAt: Date

    init(documentID: UUID) {
        self.id = documentID
        self.documentID = documentID
        self.currentPageIndex = 0
        self.scrollProgress = 0
        self.zoomScale = 1
        self.displayModeRaw = "paged"
        self.sidebarVisible = true
        self.lastOpenedAt = Date()
        self.updatedAt = Date()
    }
}
