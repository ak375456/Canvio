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
        let snapshots = records.map(PDFPageHistorySnapshot.init)
        undoManager?.push(CanvasAction(
            name: "Add PDF pages",
            undo: {
                let all = (try? context.fetch(FetchDescriptor<PDFPageElementModel>())) ?? []
                for record in all where ids.contains(record.id) {
                    Task { await PDFWorkspaceSyncService.shared.delete(record) }
                    context.delete(record)
                }
                try? context.save()
            },
            redo: {
                for snapshot in snapshots {
                    let restored = snapshot.makeModel()
                    context.insert(restored)
                    Task { await PDFWorkspaceSyncService.shared.upsert(restored) }
                }
                try? context.save()
            }
        ))
        return ids
    }

    func updatePosition(element: PDFPageElementModel, translation: CGSize,
                        boundary: CGSize, context: ModelContext,
                        undoManager: CanvasUndoManager? = nil) {
        let oldPosition = CGPoint(x: element.x, y: element.y)
        let clamped = CanvasBoundaryHelper.clamp(
            x: element.x + Double(translation.width),
            y: element.y + Double(translation.height),
            boundary: boundary,
            elementSize: CGSize(width: element.width, height: element.height)
        )
        element.x = clamped.x
        element.y = clamped.y
        persist(element, context: context)
        undoManager?.recordElementChange(
            name: "Move PDF page", element: element,
            from: oldPosition, to: CGPoint(x: element.x, y: element.y),
            context: context
        ) {
            $0.x = $1.x
            $0.y = $1.y
        }
    }

    func updateSize(element: PDFPageElementModel, width: Double, height: Double,
                    context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldSize = CGSize(width: element.width, height: element.height)
        element.width = max(120, width)
        element.height = max(90, height)
        persist(element, context: context)
        undoManager?.recordElementChange(
            name: "Resize PDF page", element: element,
            from: oldSize, to: CGSize(width: element.width, height: element.height),
            context: context
        ) {
            $0.width = $1.width
            $0.height = $1.height
        }
    }

    func updateCrop(element: PDFPageElementModel, cropRect: PDFNormalizedRect,
                    context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldValue = element.cropRect
        element.cropRect = cropRect
        persist(element, context: context)
        undoManager?.recordElementChange(
            name: "Crop PDF page", element: element,
            from: oldValue, to: element.cropRect, context: context
        ) { $0.cropRect = $1 }
    }

    func updateRotation(element: PDFPageElementModel, rotation: Double,
                        context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldValue = element.rotation
        element.rotation = rotation
        persist(element, context: context)
        undoManager?.recordElementChange(
            name: "Rotate PDF page", element: element,
            from: oldValue, to: element.rotation, context: context
        ) { $0.rotation = $1 }
    }

    func delete(element: PDFPageElementModel, context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snapshot = PDFPageHistorySnapshot(element: element)
        Task { await PDFWorkspaceSyncService.shared.delete(element) }
        context.delete(element)
        try? context.save()
        if editingID == element.id { editingID = nil }

        undoManager?.push(CanvasAction(
            name: "Delete PDF page",
            undo: {
                let restored = snapshot.makeModel()
                context.insert(restored)
                try? context.save()
                Task { await PDFWorkspaceSyncService.shared.upsert(restored) }
            },
            redo: {
                guard let values = try? context.fetch(FetchDescriptor<PDFPageElementModel>()),
                      let current = values.first(where: { $0.id == snapshot.id }) else { return }
                Task { await PDFWorkspaceSyncService.shared.delete(current) }
                context.delete(current)
                try? context.save()
            }
        ))
    }

    @discardableResult
    func duplicate(element: PDFPageElementModel, zIndex: Int,
                   offset: CGSize = CGSize(width: 30, height: 30),
                   context: ModelContext,
                   undoManager: CanvasUndoManager? = nil) -> UUID {
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
        let snapshot = PDFPageHistorySnapshot(element: copy)
        undoManager?.push(CanvasAction(
            name: "Duplicate PDF page",
            undo: {
                guard let values = try? context.fetch(FetchDescriptor<PDFPageElementModel>()),
                      let current = values.first(where: { $0.id == snapshot.id }) else { return }
                context.delete(current)
                try? context.save()
                Task { await PDFWorkspaceSyncService.shared.delete(current) }
            },
            redo: {
                let restored = snapshot.makeModel()
                context.insert(restored)
                try? context.save()
                Task { await PDFWorkspaceSyncService.shared.upsert(restored) }
            }
        ))
        return copy.id
    }

    func stopEditing() { editingID = nil }

    private func persist(_ element: PDFPageElementModel, context: ModelContext) {
        element.updatedAt = Date()
        try? context.save()
        Task { await PDFWorkspaceSyncService.shared.upsert(element) }
    }
}

private struct PDFPageHistorySnapshot {
    let id: UUID
    let documentID: UUID
    let canvasID: UUID
    let pdfFileName: String
    let originalName: String
    let pageIndex: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let rotation: Double
    let cropRect: PDFNormalizedRect
    let showsAnnotations: Bool
    let zIndex: Int
    let groupID: UUID?
    let isLayerHidden: Bool
    let layerOpacity: Double

    init(element: PDFPageElementModel) {
        id = element.id
        documentID = element.documentID
        canvasID = element.canvasID
        pdfFileName = element.pdfFileName
        originalName = element.originalName
        pageIndex = element.pageIndex
        x = element.x
        y = element.y
        width = element.width
        height = element.height
        rotation = element.rotation
        cropRect = element.cropRect
        showsAnnotations = element.showsAnnotations
        zIndex = element.zIndex
        groupID = element.groupID
        isLayerHidden = element.isLayerHidden
        layerOpacity = element.layerOpacity
    }

    func makeModel() -> PDFPageElementModel {
        let model = PDFPageElementModel(
            documentID: documentID,
            canvasID: canvasID,
            pageIndex: pageIndex,
            pdfFileName: pdfFileName,
            originalName: originalName,
            cropRect: cropRect,
            x: x,
            y: y,
            width: width,
            height: height
        )
        model.id = id
        model.rotation = rotation
        model.showsAnnotations = showsAnnotations
        model.zIndex = zIndex
        model.groupID = groupID
        model.isLayerHidden = isLayerHidden
        model.layerOpacity = layerOpacity
        model.updatedAt = Date()
        return model
    }
}
