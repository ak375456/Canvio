//
//  CanvasViewModel.swift
//  Canvio
//

import SwiftUI
import Combine
import PhotosUI

let canvasMinimumZoomScale: CGFloat = 0.55

@MainActor
final class CanvasNavigationState: ObservableObject {
    @Published var offset: CGSize = .zero
    @Published var scale: CGFloat = 1

    // Gesture baselines do not affect rendering and therefore should not publish.
    var lastOffset: CGSize = .zero
    var lastScale: CGFloat = 1
    var panTranslation: CGSize = .zero
    var magnification: CGFloat = 1
    var focalPoint: CGPoint?
    var pendingViewportRefreshID = UUID()
}

/// Publishes a transient drag translation independently from the canvas view
/// model. The canvas passes these objects only to lightweight offset wrappers,
/// so pointer updates do not invalidate the complete document tree.
@MainActor
final class CanvasDragTranslationState: ObservableObject {
    @Published var offset: CGSize = .zero

    func reset() {
        offset = .zero
    }
}

@MainActor
class CanvasViewModel: ObservableObject {
    let navigation = CanvasNavigationState()
    let selectionDrag = CanvasDragTranslationState()
    let groupDrag = CanvasDragTranslationState()

    var offset: CGSize {
        get { navigation.offset }
        set { navigation.offset = newValue }
    }
    var lastOffset: CGSize {
        get { navigation.lastOffset }
        set { navigation.lastOffset = newValue }
    }
    var scale: CGFloat {
        get { navigation.scale }
        set { navigation.scale = max(canvasMinimumZoomScale, newValue) }
    }
    var lastScale: CGFloat {
        get { navigation.lastScale }
        set { navigation.lastScale = max(canvasMinimumZoomScale, newValue) }
    }
    @Published var showTextSheet: Bool = false
    @Published var showShapePicker: Bool = false
    @Published var showSymbolPicker: Bool = false          // ← NEW
    @Published var showImagePicker: Bool = false
    @Published var showImageSourcePicker: Bool = false
    @Published var showCameraPicker: Bool = false
    @Published var showScanner: Bool = false
    @Published var showPDFPicker: Bool = false
    @Published var showAudioPicker: Bool = false
    @Published var showYouTubeLinkSheet: Bool = false
    @Published var showTemplatePicker: Bool = false
    @Published var showAudioRecorder: Bool = false
    @Published var showAudioImporter: Bool = false
    @Published var showCanvasDrawingOverlay: Bool = false
    @Published var pendingShapeLocation: CGPoint? = nil
    @Published var pendingSymbolLocation: CGPoint? = nil   // ← NEW
    @Published var pendingImageLocation: CGPoint? = nil
    @Published var pendingPDFLocation: CGPoint? = nil
    @Published var pendingAudioLocation: CGPoint? = nil
    @Published var pendingYouTubeLocation: CGPoint? = nil
    @Published var pendingTemplateLocation: CGPoint? = nil
    @Published var addMenuPosition: CGPoint? = nil
    @Published var isMinimapExpanded: Bool = false
    @Published var selectedPhotoItem: PhotosPickerItem? = nil
    @Published var showTableSizePicker: Bool = false
    @Published var pendingTableLocation: CGPoint? = nil
    @Published var showTableCSVImporter: Bool = false
    @Published var pendingCSVTableID: UUID? = nil

    let textVM      = TextElementViewModel()
    let stickyVM    = StickyNoteViewModel()
    let todoVM      = TodoListViewModel()
    let shapeVM     = ShapeElementViewModel()
    let imageVM     = ImageElementViewModel()
    let pdfVM       = PDFElementViewModel()
    let pdfPageVM   = PDFPageElementViewModel()
    let tableVM     = TableElementViewModel()
    let audioVM     = AudioElementViewModel()
    let youtubeVM   = YouTubeElementViewModel()
    let drawingVM   = DrawingElementViewModel()
    let connectorVM = ConnectorViewModel()
    let symbolVM    = SymbolElementViewModel()             // ← NEW

    let undoManager = CanvasUndoManager()
    let selection   = SelectionViewModel()

    func handleDragChange(_ value: DragGesture.Value) {
        offset = CGSize(
            width:  lastOffset.width  + value.translation.width,
            height: lastOffset.height + value.translation.height
        )
    }

    func handleDragEnd() { lastOffset = offset }

    func handleMagnification(_ magnification: CGFloat, focalPoint: CGPoint) {
        let newScale   = max(canvasMinimumZoomScale, min(lastScale * magnification, 5.0))
        let scaleDelta = newScale / scale
        let dx = focalPoint.x - offset.width
        let dy = focalPoint.y - offset.height
        offset = CGSize(
            width:  focalPoint.x - dx * scaleDelta,
            height: focalPoint.y - dy * scaleDelta
        )
        scale = newScale
    }

    func handleMagnificationEnd() {
        lastScale  = scale
        lastOffset = offset
    }

    func showAddMenu(at point: CGPoint) { addMenuPosition = point }
    func hideAddMenu() { addMenuPosition = nil }

    func centerOn(canvasPoint: CGPoint, viewportSize: CGSize) {
        let x = viewportSize.width  / 2 - canvasPoint.x * scale
        let y = viewportSize.height / 2 - canvasPoint.y * scale
        withAnimation(.spring(duration: 0.4)) {
            offset = CGSize(width: x, height: y)
        }
        lastOffset = CGSize(width: x, height: y)
    }

    func clampOffset(to boundary: CGSize, viewportSize: CGSize, scale: CGFloat) {
        guard boundary != .zero else { return }
        let scaledW    = boundary.width  * scale
        let scaledH    = boundary.height * scale
        let overscroll = max(viewportSize.width, viewportSize.height) / 2
        let minX = viewportSize.width  - scaledW - overscroll
        let maxX = overscroll
        let minY = viewportSize.height - scaledH - overscroll
        let maxY = overscroll
        let cx = max(minX, min(maxX, offset.width))
        let cy = max(minY, min(maxY, offset.height))
        guard cx != offset.width || cy != offset.height else { return }
        withAnimation(.spring(duration: 0.3)) {
            offset = CGSize(width: cx, height: cy)
        }
        lastOffset = CGSize(width: cx, height: cy)
    }

    func centerPage(boundary: CGSize, viewportSize: CGSize) {
        guard boundary != .zero, viewportSize.width > 0, viewportSize.height > 0 else { return }
        let padding: CGFloat = 40
        let scaleX   = (viewportSize.width  - padding * 2) / boundary.width
        let scaleY   = (viewportSize.height - padding * 2) / boundary.height
        let fitScale = max(canvasMinimumZoomScale, min(scaleX, scaleY, 1.0))
        scale      = fitScale
        lastScale  = fitScale
        let x = (viewportSize.width  - boundary.width  * fitScale) / 2
        let y = (viewportSize.height - boundary.height * fitScale) / 2
        offset     = CGSize(width: x, height: y)
        lastOffset = offset
    }
}
