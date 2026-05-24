//
//  CanvasViewModel.swift
//  Canvio
//

import SwiftUI
import Combine
import PhotosUI

@MainActor
class CanvasViewModel: ObservableObject {
    @Published var offset: CGSize = .zero
    @Published var lastOffset: CGSize = .zero
    @Published var scale: CGFloat = 1.0
    @Published var lastScale: CGFloat = 1.0
    @Published var showTextSheet: Bool = false
    @Published var showShapePicker: Bool = false
    @Published var showSymbolPicker: Bool = false          // ← NEW
    @Published var showImagePicker: Bool = false
    @Published var showImageSourcePicker: Bool = false
    @Published var showCameraPicker: Bool = false
    @Published var showPDFPicker: Bool = false
    @Published var showAudioPicker: Bool = false
    @Published var showAudioRecorder: Bool = false
    @Published var showAudioImporter: Bool = false
    @Published var showCanvasDrawingOverlay: Bool = false
    @Published var pendingShapeLocation: CGPoint? = nil
    @Published var pendingSymbolLocation: CGPoint? = nil   // ← NEW
    @Published var pendingImageLocation: CGPoint? = nil
    @Published var pendingPDFLocation: CGPoint? = nil
    @Published var pendingAudioLocation: CGPoint? = nil
    @Published var pendingDrawingLocation: CGPoint? = nil
    @Published var addMenuPosition: CGPoint? = nil
    @Published var isMinimapExpanded: Bool = true
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
    let tableVM     = TableElementViewModel()
    let audioVM     = AudioElementViewModel()
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
        let newScale   = max(0.3, min(lastScale * magnification, 5.0))
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
        let fitScale = min(scaleX, scaleY, 1.0)
        scale      = fitScale
        lastScale  = fitScale
        let x = (viewportSize.width  - boundary.width  * fitScale) / 2
        let y = (viewportSize.height - boundary.height * fitScale) / 2
        offset     = CGSize(width: x, height: y)
        lastOffset = offset
    }
}
