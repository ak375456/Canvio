//
//  TextElementViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import Combine

@MainActor
class TextElementViewModel: ObservableObject {
    @Published var editingID: UUID?       = nil
    @Published var inlineEditingID: UUID? = nil

    // MARK: - Add (from sheet)

    func addText(canvasID: UUID, style: TextStyle, center: CGPoint,
                 offset: CGSize, scale: CGFloat, zIndex: Int,
                 context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let canvasX = (center.x - offset.width)  / scale
        let canvasY = (center.y - offset.height) / scale
        let element = TextElementModel(canvasID: canvasID, text: style.text,
                                       x: canvasX, y: canvasY)
        element.fontSize      = style.fontSize
        element.isBold        = style.isBold
        element.isItalic      = style.isItalic
        element.colorName     = style.colorName
        element.fontName      = style.fontName
        element.zIndex        = zIndex
        element.updatedAt     = Date()
        context.insert(element)
        try? context.save()

        // Sync to Supabase
        Task { await TextSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TextElementModel>())
                    .first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await TextSyncService.shared.delete(el) }
                }
            },
            redo: {
                let el = TextElementModel(canvasID: canvasID, text: style.text,
                                          x: canvasX, y: canvasY)
                el.id = id; el.fontSize = style.fontSize; el.isBold = style.isBold
                el.isItalic = style.isItalic; el.colorName = style.colorName
                el.fontName = style.fontName; el.zIndex = zIndex
                el.updatedAt = Date()
                context.insert(el); try? context.save()
                Task { await TextSyncService.shared.upsert(el) }
            }
        ))
    }

    // MARK: - Add inline (double-tap on canvas)

    func addInlineText(canvasID: UUID, canvasPoint: CGPoint, zIndex: Int,
                       context: ModelContext,
                       undoManager: CanvasUndoManager? = nil) -> TextElementModel {
        let element = TextElementModel(canvasID: canvasID, text: "",
                                       x: canvasPoint.x, y: canvasPoint.y)
        element.fontSize  = 16
        element.zIndex    = zIndex
        element.updatedAt = Date()
        context.insert(element)
        try? context.save()
        inlineEditingID = element.id
        editingID       = element.id

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TextElementModel>())
                    .first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await TextSyncService.shared.delete(el) }
                }
            },
            redo: {
                let el = TextElementModel(canvasID: canvasID, text: "",
                                          x: canvasPoint.x, y: canvasPoint.y)
                el.id = id; el.zIndex = zIndex; el.updatedAt = Date()
                context.insert(el); try? context.save()
                Task { await TextSyncService.shared.upsert(el) }
            }
        ))
        return element
    }

    // MARK: - Position

    func updatePosition(element: TextElementModel, translation: CGSize,
                        scale: CGFloat = 1, boundary: CGSize = .zero,
                        context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldX = element.x, oldY = element.y
        let newX = element.x + Double(translation.width  / scale)
        let newY = element.y + Double(translation.height / scale)
        let clamped = CanvasBoundaryHelper.clamp(x: newX, y: newY, boundary: boundary,
                                                  elementSize: CGSize(width: 200, height: 60))
        element.x = clamped.x; element.y = clamped.y
        element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TextElementModel>())
                    .first(where: { $0.id == id }) {
                    el.x = oldX; el.y = oldY; el.updatedAt = Date()
                    try? context.save()
                    Task { await TextSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<TextElementModel>())
                    .first(where: { $0.id == id }) {
                    el.x = clamped.x; el.y = clamped.y; el.updatedAt = Date()
                    try? context.save()
                    Task { await TextSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    // MARK: - Inline formatting (live toggles — sync each change)

    func toggleBold(element: TextElementModel, context: ModelContext) {
        element.isBold    = !element.isBold
        element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
    }

    func toggleItalic(element: TextElementModel, context: ModelContext) {
        element.isItalic  = !element.isItalic
        element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
    }

    func toggleUnderline(element: TextElementModel, context: ModelContext) {
        element.isUnderline = !element.isUnderline
        element.updatedAt   = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
    }

    func setAlignment(_ alignment: TextAlignment, element: TextElementModel,
                      context: ModelContext) {
        element.textAlignment = alignment
        element.updatedAt     = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
    }

    func adjustFontSize(by delta: Double, element: TextElementModel,
                        context: ModelContext) {
        element.fontSize  = max(10, min(72, element.fontSize + delta))
        element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
    }

    func setColor(_ colorName: String, element: TextElementModel,
                  context: ModelContext) {
        element.colorName = colorName
        element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
    }

    // MARK: - Duplicate

    func duplicate(element: TextElementModel, zIndex: Int,
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let copy = TextElementModel(canvasID: element.canvasID,
                                    text: element.text,
                                    x: element.x + 30,
                                    y: element.y + 30)
        copy.fontSize      = element.fontSize
        copy.isBold        = element.isBold
        copy.isItalic      = element.isItalic
        copy.isUnderline   = element.isUnderline
        copy.colorName     = element.colorName
        copy.fontName      = element.fontName
        copy.alignmentRaw  = element.alignmentRaw
        copy.zIndex        = zIndex
        copy.updatedAt     = Date()
        context.insert(copy); try? context.save()
        Task { await TextSyncService.shared.upsert(copy) }

        let id = copy.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TextElementModel>())
                    .first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await TextSyncService.shared.delete(el) }
                }
            },
            redo: {
                let el = TextElementModel(canvasID: element.canvasID,
                                          text: element.text,
                                          x: element.x + 30, y: element.y + 30)
                el.id = id; el.zIndex = zIndex; el.updatedAt = Date()
                context.insert(el); try? context.save()
                Task { await TextSyncService.shared.upsert(el) }
            }
        ))
    }

    // MARK: - Delete

    func delete(element: TextElementModel, context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snap = (
            id: element.id, canvasID: element.canvasID, text: element.text,
            x: element.x, y: element.y, fontSize: element.fontSize,
            isBold: element.isBold, isItalic: element.isItalic,
            isUnderline: element.isUnderline,
            colorName: element.colorName, fontName: element.fontName,
            alignmentRaw: element.alignmentRaw, zIndex: element.zIndex
        )
        // Soft-delete on Supabase before removing locally
        Task { await TextSyncService.shared.delete(element) }
        context.delete(element); try? context.save()
        if editingID       == snap.id { editingID       = nil }
        if inlineEditingID == snap.id { inlineEditingID = nil }

        undoManager?.push(CanvasAction(
            undo: {
                let el = TextElementModel(canvasID: snap.canvasID, text: snap.text,
                                          x: snap.x, y: snap.y)
                el.id = snap.id; el.fontSize = snap.fontSize; el.isBold = snap.isBold
                el.isItalic = snap.isItalic; el.isUnderline = snap.isUnderline
                el.colorName = snap.colorName; el.fontName = snap.fontName
                el.alignmentRaw = snap.alignmentRaw; el.zIndex = snap.zIndex
                el.updatedAt = Date()
                context.insert(el); try? context.save()
                Task { await TextSyncService.shared.upsert(el) }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<TextElementModel>())
                    .first(where: { $0.id == snap.id }) {
                    context.delete(el); try? context.save()
                    Task { await TextSyncService.shared.delete(el) }
                }
            }
        ))
    }

    func stopEditing() {
        editingID       = nil
        inlineEditingID = nil
    }

    func colorFromName(_ name: String) -> Color {
        TextStyle.colorOptions.first { $0.name == name }?.color ?? .primary
    }
}
