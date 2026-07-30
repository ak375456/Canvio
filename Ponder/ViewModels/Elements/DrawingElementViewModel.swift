//
//  DrawingElementViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import PencilKit
import Combine

struct DrawingElementHistoryState: Equatable {
    let id: UUID
    let canvasID: UUID
    let drawingData: Data
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let rotation: Double
    let isCanvasDrawing: Bool
    let zIndex: Int
    let groupID: UUID?
    let isLayerHidden: Bool
    let layerOpacity: Double

    init(_ element: DrawingElementModel) {
        id = element.id
        canvasID = element.canvasID
        drawingData = element.drawingData
        x = element.x
        y = element.y
        width = element.width
        height = element.height
        rotation = element.rotation
        isCanvasDrawing = element.isCanvasDrawing
        zIndex = element.zIndex
        groupID = element.groupID
        isLayerHidden = element.isLayerHidden
        layerOpacity = element.layerOpacity
    }

    func apply(to element: DrawingElementModel) {
        element.drawingData = drawingData
        element.x = x
        element.y = y
        element.width = width
        element.height = height
        element.rotation = rotation
        element.isCanvasDrawing = isCanvasDrawing
        element.zIndex = zIndex
        element.groupID = groupID
        element.isLayerHidden = isLayerHidden
        element.layerOpacity = layerOpacity
        element.updatedAt = Date()
    }

    func makeModel() -> DrawingElementModel {
        let element = DrawingElementModel(
            canvasID: canvasID,
            x: x,
            y: y,
            width: width,
            height: height,
            isCanvasDrawing: isCanvasDrawing
        )
        element.id = id
        apply(to: element)
        return element
    }
}

@MainActor
class DrawingElementViewModel: ObservableObject {
    @Published var editingID: UUID? = nil
    @Published var isDrawingModeActive: Bool = false

    func addDrawing(canvasID: UUID, center: CGPoint, offset: CGSize,
                    scale: CGFloat, zIndex: Int, context: ModelContext,
                    undoManager: CanvasUndoManager? = nil) {
        let canvasX = (center.x - offset.width) / scale
        let canvasY = (center.y - offset.height) / scale
        let element = DrawingElementModel(canvasID: canvasID, x: canvasX, y: canvasY)
        element.zIndex = zIndex
        context.insert(element); try? context.save()
        editingID = element.id
        isDrawingModeActive = true

        Task { await DrawingSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<DrawingElementModel>()).first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await DrawingSyncService.shared.delete(el) }
                }
            },
            redo: {
                let el = DrawingElementModel(canvasID: canvasID, x: canvasX, y: canvasY)
                el.id = id; el.zIndex = zIndex
                context.insert(el); try? context.save()
                Task { await DrawingSyncService.shared.upsert(el) }
            }
        ))
    }

    func saveDrawing(element: DrawingElementModel, drawing: PKDrawing, context: ModelContext,
                     undoManager: CanvasUndoManager? = nil) {
        let oldData = element.drawingData
        element.pkDrawing = drawing
        element.updatedAt = Date()
        try? context.save()
        Task { await DrawingSyncService.shared.upsert(element) }
        undoManager?.recordElementChange(
            name: "Edit drawing",
            element: element,
            from: oldData,
            to: element.drawingData,
            context: context,
            coalescingKey: "drawing-data-\(element.id)"
        ) { $0.drawingData = $1 }
    }

    func updatePosition(element: DrawingElementModel, translation: CGSize,
                        scale: CGFloat = 1, boundary: CGSize = .zero,
                        context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldX = element.x, oldY = element.y
        let newX = element.x + Double(translation.width)
        let newY = element.y + Double(translation.height)
        let clamped = CanvasBoundaryHelper.clamp(x: newX, y: newY, boundary: boundary,
                                                  elementSize: CGSize(width: element.width, height: element.height))
        element.x = clamped.x; element.y = clamped.y
        element.updatedAt = Date(); try? context.save()
        Task { await DrawingSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<DrawingElementModel>()).first(where: { $0.id == id }) {
                    el.x = oldX; el.y = oldY; el.updatedAt = Date(); try? context.save()
                    Task { await DrawingSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<DrawingElementModel>()).first(where: { $0.id == id }) {
                    el.x = clamped.x; el.y = clamped.y; el.updatedAt = Date(); try? context.save()
                    Task { await DrawingSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    @discardableResult
    func duplicate(element: DrawingElementModel, zIndex: Int,
                   offset: CGSize = CGSize(width: 30, height: 30),
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) -> UUID? {
        let copy = DrawingElementModel(canvasID: element.canvasID,
                                       x: element.x + Double(offset.width),
                                       y: element.y + Double(offset.height),
                                       width: element.width, height: element.height,
                                       isCanvasDrawing: element.isCanvasDrawing)
        copy.drawingData = element.drawingData
        copy.rotation = element.rotation
        copy.zIndex = zIndex
        context.insert(copy); try? context.save()
        Task { await DrawingSyncService.shared.upsert(copy) }

        let id = copy.id
        let snapshot = DrawingElementHistoryState(copy)
        undoManager?.push(CanvasAction(
            name: "Duplicate drawing",
            undo: {
                if let el = try? context.fetch(FetchDescriptor<DrawingElementModel>()).first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await DrawingSyncService.shared.delete(el) }
                }
            },
            redo: {
                let el = snapshot.makeModel()
                context.insert(el); try? context.save()
                Task { await DrawingSyncService.shared.upsert(el) }
            }
        ))
        return id
    }

    func updateSize(element: DrawingElementModel, width: Double, height: Double,
                    context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldW = element.width, oldH = element.height
        element.width = max(100, min(1200, width))
        element.height = max(80, min(1200, height))
        element.updatedAt = Date(); try? context.save()
        Task { await DrawingSyncService.shared.upsert(element) }

        let id = element.id; let newW = element.width, newH = element.height
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<DrawingElementModel>()).first(where: { $0.id == id }) {
                    el.width = oldW; el.height = oldH; el.updatedAt = Date(); try? context.save()
                    Task { await DrawingSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<DrawingElementModel>()).first(where: { $0.id == id }) {
                    el.width = newW; el.height = newH; el.updatedAt = Date(); try? context.save()
                    Task { await DrawingSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    func delete(element: DrawingElementModel, context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snapshot = DrawingElementHistoryState(element)

        Task { await DrawingSyncService.shared.delete(element) }
        context.delete(element); try? context.save()
        if editingID == snapshot.id { stopEditing() }

        undoManager?.push(CanvasAction(
            name: "Delete drawing",
            undo: {
                let el = snapshot.makeModel()
                context.insert(el); try? context.save()
                Task { await DrawingSyncService.shared.upsert(el) }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<DrawingElementModel>()).first(where: { $0.id == snapshot.id }) {
                    context.delete(el); try? context.save()
                    Task { await DrawingSyncService.shared.delete(el) }
                }
            }
        ))
    }

    func stopEditing() { editingID = nil; isDrawingModeActive = false }
    func exitDrawMode() { isDrawingModeActive = false }
}
