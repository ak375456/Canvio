//
//  ShapeElementViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import Combine

@MainActor
class ShapeElementViewModel: ObservableObject {
    @Published var editingID: UUID? = nil

    func addShape(canvasID: UUID, kind: ShapeKind, center: CGPoint,
                  offset: CGSize, scale: CGFloat, zIndex: Int,
                  context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let x = (center.x - offset.width) / scale
        let y = (center.y - offset.height) / scale
        let shape = ShapeElementModel(canvasID: canvasID, kind: kind, x: x, y: y)
        shape.zIndex = zIndex
        context.insert(shape); try? context.save()
        editingID = shape.id

        Task { await ShapeSyncService.shared.upsert(shape) }

        let id = shape.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<ShapeElementModel>()).first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await ShapeSyncService.shared.delete(el) }
                }
            },
            redo: {
                let el = ShapeElementModel(canvasID: canvasID, kind: kind, x: x, y: y)
                el.id = id; el.zIndex = zIndex
                context.insert(el); try? context.save()
                Task { await ShapeSyncService.shared.upsert(el) }
            }
        ))
    }

    func updatePosition(shape: ShapeElementModel, translation: CGSize,
                        scale: CGFloat = 1, boundary: CGSize = .zero,
                        context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldX = shape.x, oldY = shape.y
        let newX = shape.x + Double(translation.width)
        let newY = shape.y + Double(translation.height)
        let clamped = CanvasBoundaryHelper.clamp(x: newX, y: newY, boundary: boundary,
                                                  elementSize: CGSize(width: shape.width, height: shape.height))
        shape.x = clamped.x; shape.y = clamped.y
        shape.updatedAt = Date(); try? context.save()
        Task { await ShapeSyncService.shared.upsert(shape) }

        let id = shape.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<ShapeElementModel>()).first(where: { $0.id == id }) {
                    el.x = oldX; el.y = oldY; el.updatedAt = Date(); try? context.save()
                    Task { await ShapeSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<ShapeElementModel>()).first(where: { $0.id == id }) {
                    el.x = clamped.x; el.y = clamped.y; el.updatedAt = Date(); try? context.save()
                    Task { await ShapeSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    @discardableResult
    func duplicate(shape: ShapeElementModel, zIndex: Int,
                   offset: CGSize = CGSize(width: 30, height: 30),
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) -> UUID? {
        let copy = ShapeElementModel(canvasID: shape.canvasID, kind: shape.shapeKind,
                                     x: shape.x + Double(offset.width),
                                     y: shape.y + Double(offset.height))
        copy.width = shape.width; copy.height = shape.height
        copy.strokeColorName = shape.strokeColorName; copy.fillColorName = shape.fillColorName
        copy.hasFill = shape.hasFill; copy.strokeWidth = shape.strokeWidth
        copy.hasArrowHead = shape.hasArrowHead; copy.polygonSides = shape.polygonSides
        copy.zIndex = zIndex
        context.insert(copy); try? context.save()
        Task { await ShapeSyncService.shared.upsert(copy) }

        let id = copy.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<ShapeElementModel>()).first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await ShapeSyncService.shared.delete(el) }
                }
            },
            redo: {
                let el = ShapeElementModel(canvasID: shape.canvasID, kind: shape.shapeKind,
                                           x: shape.x + Double(offset.width),
                                           y: shape.y + Double(offset.height))
                el.id = id; el.zIndex = zIndex
                context.insert(el); try? context.save()
                Task { await ShapeSyncService.shared.upsert(el) }
            }
        ))
        return id
    }

    func updateSize(shape: ShapeElementModel, width: Double, height: Double,
                    context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldW = shape.width, oldH = shape.height
        if shape.shapeKind == .line {
            shape.width = max(40, width); shape.height = max(2, min(40, height))
        } else {
            shape.width = max(40, width); shape.height = max(40, height)
        }
        shape.updatedAt = Date(); try? context.save()
        Task { await ShapeSyncService.shared.upsert(shape) }

        let id = shape.id; let newW = shape.width, newH = shape.height
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<ShapeElementModel>()).first(where: { $0.id == id }) {
                    el.width = oldW; el.height = oldH; el.updatedAt = Date(); try? context.save()
                    Task { await ShapeSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<ShapeElementModel>()).first(where: { $0.id == id }) {
                    el.width = newW; el.height = newH; el.updatedAt = Date(); try? context.save()
                    Task { await ShapeSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    func delete(shape: ShapeElementModel, context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snap = (id: shape.id, canvasID: shape.canvasID, kind: shape.shapeKind,
                    x: shape.x, y: shape.y, width: shape.width, height: shape.height,
                    zIndex: shape.zIndex)

        Task { await ShapeSyncService.shared.delete(shape) }
        context.delete(shape); try? context.save()
        if editingID == snap.id { editingID = nil }

        undoManager?.push(CanvasAction(
            undo: {
                let el = ShapeElementModel(canvasID: snap.canvasID, kind: snap.kind,
                                           x: snap.x, y: snap.y)
                el.id = snap.id; el.width = snap.width; el.height = snap.height
                el.zIndex = snap.zIndex
                context.insert(el); try? context.save()
                Task { await ShapeSyncService.shared.upsert(el) }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<ShapeElementModel>()).first(where: { $0.id == snap.id }) {
                    context.delete(el); try? context.save()
                    Task { await ShapeSyncService.shared.delete(el) }
                }
            }
        ))
    }

    func stopEditing() { editingID = nil }
}
