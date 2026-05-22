//
//  DrawingElementViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import PencilKit
import Combine

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

    func saveDrawing(element: DrawingElementModel, drawing: PKDrawing, context: ModelContext) {
        element.pkDrawing = drawing
        element.updatedAt = Date()
        try? context.save()
        Task { await DrawingSyncService.shared.upsert(element) }
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

    func duplicate(element: DrawingElementModel, zIndex: Int,
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let copy = DrawingElementModel(canvasID: element.canvasID,
                                       x: element.x + 30, y: element.y + 30,
                                       width: element.width, height: element.height,
                                       isCanvasDrawing: element.isCanvasDrawing)
        copy.drawingData = element.drawingData
        copy.zIndex = zIndex
        context.insert(copy); try? context.save()
        Task { await DrawingSyncService.shared.upsert(copy) }

        let id = copy.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<DrawingElementModel>()).first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await DrawingSyncService.shared.delete(el) }
                }
            },
            redo: {
                let el = DrawingElementModel(canvasID: element.canvasID,
                                             x: element.x + 30, y: element.y + 30,
                                             width: element.width, height: element.height)
                el.id = id; el.drawingData = element.drawingData; el.zIndex = zIndex
                context.insert(el); try? context.save()
                Task { await DrawingSyncService.shared.upsert(el) }
            }
        ))
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
        let snap = (id: element.id, canvasID: element.canvasID,
                    x: element.x, y: element.y, width: element.width, height: element.height,
                    drawingData: element.drawingData, isCanvasDrawing: element.isCanvasDrawing,
                    zIndex: element.zIndex)

        Task { await DrawingSyncService.shared.delete(element) }
        context.delete(element); try? context.save()
        if editingID == snap.id { stopEditing() }

        undoManager?.push(CanvasAction(
            undo: {
                let el = DrawingElementModel(canvasID: snap.canvasID, x: snap.x, y: snap.y,
                                             width: snap.width, height: snap.height,
                                             isCanvasDrawing: snap.isCanvasDrawing)
                el.id = snap.id; el.drawingData = snap.drawingData; el.zIndex = snap.zIndex
                context.insert(el); try? context.save()
                Task { await DrawingSyncService.shared.upsert(el) }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<DrawingElementModel>()).first(where: { $0.id == snap.id }) {
                    context.delete(el); try? context.save()
                    Task { await DrawingSyncService.shared.delete(el) }
                }
            }
        ))
    }

    func stopEditing() { editingID = nil; isDrawingModeActive = false }
    func exitDrawMode() { isDrawingModeActive = false }
}
