import SwiftUI
import SwiftData
import PDFKit
import Combine

@MainActor
final class PDFPageElementViewModel: ObservableObject {
    @Published var editingID: UUID?

    @discardableResult
    func addPages(source: PDFElementModel,
                  requests: [PDFPagePlacementRequest],
                  canvasID: UUID,
                  zIndex: Int,
                  boundary: CGSize,
                  context: ModelContext,
                  undoManager: CanvasUndoManager? = nil) -> [UUID] {
        guard !requests.isEmpty,
              let document = PDFStorageService.loadPDF(fileName: source.pdfFileName) else { return [] }

        let records = requests.enumerated().compactMap { index, request -> PDFPageElementModel? in
            guard let page = document.page(at: request.pageIndex) else { return nil }
            let pageBounds = page.bounds(for: .cropBox)
            let croppedWidth = max(1, pageBounds.width * request.cropRect.cgRect.width)
            let croppedHeight = max(1, pageBounds.height * request.cropRect.cgRect.height)
            let tileWidth: CGFloat = request.cropRect == .fullPage ? 300 : min(420, max(240, croppedWidth * 0.75))
            let tileHeight = max(120, tileWidth * croppedHeight / croppedWidth)
            let column = index % 3
            let row = index / 3
            let proposedX = source.x + source.width / 2 + 70 + Double(tileWidth / 2)
                + Double(column) * Double(tileWidth + 34)
            let proposedY = source.y + Double(row) * Double(tileHeight + 34)
            let clamped = CanvasBoundaryHelper.clamp(
                x: proposedX,
                y: proposedY,
                boundary: boundary,
                elementSize: CGSize(width: tileWidth, height: tileHeight)
            )
            let tile = PDFPageElementModel(
                documentID: source.resolvedDocumentID,
                canvasID: canvasID,
                pageIndex: request.pageIndex,
                pdfFileName: source.pdfFileName,
                originalName: source.originalName,
                cropRect: request.cropRect,
                x: clamped.x,
                y: clamped.y,
                width: Double(tileWidth),
                height: Double(tileHeight)
            )
            tile.zIndex = zIndex + index
            return tile
        }

        for record in records { context.insert(record) }
        try? context.save()
        editingID = records.last?.id
        Task {
            for record in records { await PDFWorkspaceSyncService.shared.upsert(record) }
        }

        let ids = records.map(\.id)
        undoManager?.push(CanvasAction(
            undo: {
                let all = (try? context.fetch(FetchDescriptor<PDFPageElementModel>())) ?? []
                for record in all where ids.contains(record.id) {
                    Task { await PDFWorkspaceSyncService.shared.delete(record) }
                    context.delete(record)
                }
                try? context.save()
            },
            redo: {
                for old in records {
                    let restored = PDFPageElementModel(
                        documentID: old.documentID,
                        canvasID: old.canvasID,
                        pageIndex: old.pageIndex,
                        pdfFileName: old.pdfFileName,
                        originalName: old.originalName,
                        cropRect: old.cropRect,
                        x: old.x, y: old.y,
                        width: old.width, height: old.height
                    )
                    restored.id = old.id
                    restored.rotation = old.rotation
                    restored.zIndex = old.zIndex
                    context.insert(restored)
                    Task { await PDFWorkspaceSyncService.shared.upsert(restored) }
                }
                try? context.save()
            }
        ))
        return ids
    }

    func updatePosition(element: PDFPageElementModel, translation: CGSize,
                        boundary: CGSize, context: ModelContext) {
        let clamped = CanvasBoundaryHelper.clamp(
            x: element.x + Double(translation.width),
            y: element.y + Double(translation.height),
            boundary: boundary,
            elementSize: CGSize(width: element.width, height: element.height)
        )
        element.x = clamped.x
        element.y = clamped.y
        persist(element, context: context)
    }

    func updateSize(element: PDFPageElementModel, width: Double, height: Double,
                    context: ModelContext) {
        element.width = max(120, width)
        element.height = max(90, height)
        persist(element, context: context)
    }

    func updateCrop(element: PDFPageElementModel, cropRect: PDFNormalizedRect,
                    context: ModelContext) {
        element.cropRect = cropRect
        persist(element, context: context)
    }

    func updateRotation(element: PDFPageElementModel, rotation: Double,
                        context: ModelContext) {
        element.rotation = rotation
        persist(element, context: context)
    }

    func delete(element: PDFPageElementModel, context: ModelContext) {
        Task { await PDFWorkspaceSyncService.shared.delete(element) }
        context.delete(element)
        try? context.save()
        if editingID == element.id { editingID = nil }
    }

    @discardableResult
    func duplicate(element: PDFPageElementModel, zIndex: Int,
                   offset: CGSize = CGSize(width: 30, height: 30),
                   context: ModelContext) -> UUID {
        let copy = PDFPageElementModel(
            documentID: element.documentID,
            canvasID: element.canvasID,
            pageIndex: element.pageIndex,
            pdfFileName: element.pdfFileName,
            originalName: element.originalName,
            cropRect: element.cropRect,
            x: element.x + offset.width,
            y: element.y + offset.height,
            width: element.width,
            height: element.height
        )
        copy.rotation = element.rotation
        copy.showsAnnotations = element.showsAnnotations
        copy.zIndex = zIndex
        context.insert(copy)
        try? context.save()
        Task { await PDFWorkspaceSyncService.shared.upsert(copy) }
        editingID = copy.id
        return copy.id
    }

    func stopEditing() { editingID = nil }

    private func persist(_ element: PDFPageElementModel, context: ModelContext) {
        element.updatedAt = Date()
        try? context.save()
        Task { await PDFWorkspaceSyncService.shared.upsert(element) }
    }
}
