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

    func addShape(canvasID: UUID, preset: ShapePreset, center: CGPoint,
                  offset: CGSize, scale: CGFloat, zIndex: Int,
                  context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let x = (center.x - offset.width) / scale
        let y = (center.y - offset.height) / scale
        let shape = ShapeElementModel(canvasID: canvasID, kind: preset.kind, x: x, y: y)
        Self.apply(preset, to: shape)
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
                let el = ShapeElementModel(canvasID: canvasID, kind: preset.kind, x: x, y: y)
                Self.apply(preset, to: el)
                el.id = id; el.zIndex = zIndex
                context.insert(el); try? context.save()
                Task { await ShapeSyncService.shared.upsert(el) }
            }
        ))
    }

    private static func apply(_ preset: ShapePreset, to shape: ShapeElementModel) {
        if let triangleVariant = preset.triangleVariant {
            shape.triangleVariant = triangleVariant
        }
        if let polygonSides = preset.polygonSides {
            shape.polygonSides = polygonSides
        }
        if shape.shapeKind == .line {
            shape.setLineAppearance(
                ending: preset.lineEnding ?? .none,
                style: preset.lineStyle ?? .solid
            )
        }
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
        copy.rotation = shape.rotation; copy.triangleVariantRaw = shape.triangleVariantRaw
        copy.zIndex = zIndex
        context.insert(copy); try? context.save()
        Task { await ShapeSyncService.shared.upsert(copy) }

        let id = copy.id
        let snapshot = (
            canvasID: copy.canvasID, kind: copy.shapeKind,
            x: copy.x, y: copy.y, width: copy.width, height: copy.height,
            rotation: copy.rotation, strokeColorName: copy.strokeColorName,
            fillColorName: copy.fillColorName, hasFill: copy.hasFill,
            strokeWidth: copy.strokeWidth, hasArrowHead: copy.hasArrowHead,
            triangleVariantRaw: copy.triangleVariantRaw,
            polygonSides: copy.polygonSides, zIndex: copy.zIndex
        )
        undoManager?.push(CanvasAction(
            name: "Duplicate shape",
            undo: {
                if let el = try? context.fetch(FetchDescriptor<ShapeElementModel>()).first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await ShapeSyncService.shared.delete(el) }
                }
            },
            redo: {
                let el = ShapeElementModel(
                    canvasID: snapshot.canvasID, kind: snapshot.kind,
                    x: snapshot.x, y: snapshot.y
                )
                el.id = id; el.width = snapshot.width; el.height = snapshot.height
                el.rotation = snapshot.rotation
                el.strokeColorName = snapshot.strokeColorName
                el.fillColorName = snapshot.fillColorName; el.hasFill = snapshot.hasFill
                el.strokeWidth = snapshot.strokeWidth; el.hasArrowHead = snapshot.hasArrowHead
                el.triangleVariantRaw = snapshot.triangleVariantRaw
                el.polygonSides = snapshot.polygonSides; el.zIndex = snapshot.zIndex
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
                    rotation: shape.rotation, strokeColorName: shape.strokeColorName,
                    fillColorName: shape.fillColorName, hasFill: shape.hasFill,
                    strokeWidth: shape.strokeWidth, hasArrowHead: shape.hasArrowHead,
                    triangleVariantRaw: shape.triangleVariantRaw,
                    polygonSides: shape.polygonSides, zIndex: shape.zIndex,
                    groupID: shape.groupID, isLayerHidden: shape.isLayerHidden,
                    layerOpacity: shape.layerOpacity)

        Task { await ShapeSyncService.shared.delete(shape) }
        context.delete(shape); try? context.save()
        if editingID == snap.id { editingID = nil }

        undoManager?.push(CanvasAction(
            name: "Delete shape",
            undo: {
                let el = ShapeElementModel(canvasID: snap.canvasID, kind: snap.kind,
                                           x: snap.x, y: snap.y)
                el.id = snap.id; el.width = snap.width; el.height = snap.height
                el.zIndex = snap.zIndex
                el.rotation = snap.rotation
                el.strokeColorName = snap.strokeColorName
                el.fillColorName = snap.fillColorName
                el.hasFill = snap.hasFill
                el.strokeWidth = snap.strokeWidth
                el.hasArrowHead = snap.hasArrowHead
                el.triangleVariantRaw = snap.triangleVariantRaw
                el.polygonSides = snap.polygonSides
                el.groupID = snap.groupID
                el.isLayerHidden = snap.isLayerHidden
                el.layerOpacity = snap.layerOpacity
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
