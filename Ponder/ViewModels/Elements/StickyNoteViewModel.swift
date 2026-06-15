//
//  StickyNoteViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import Combine

@MainActor
class StickyNoteViewModel: ObservableObject {
    @Published var editingID: UUID? = nil {
        didSet {
            if editingID != writingID {
                writingID = nil
            }
        }
    }
    @Published var writingID: UUID? = nil

    func addNote(canvasID: UUID, center: CGPoint, offset: CGSize,
                 scale: CGFloat, zIndex: Int, context: ModelContext,
                 undoManager: CanvasUndoManager? = nil) {
        let x = (center.x - offset.width) / scale
        let y = (center.y - offset.height) / scale
        let note = StickyNoteModel(canvasID: canvasID, x: x, y: y)
        note.zIndex = zIndex
        context.insert(note); try? context.save()
        editingID = note.id
        writingID = note.id

        // Sync to Supabase
        Task { await StickyNoteSyncService.shared.upsert(note) }

        let id = note.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<StickyNoteModel>()).first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await StickyNoteSyncService.shared.delete(el) }
                }
            },
            redo: {
                let el = StickyNoteModel(canvasID: canvasID, x: x, y: y)
                el.id = id; el.zIndex = zIndex
                context.insert(el); try? context.save()
                Task { await StickyNoteSyncService.shared.upsert(el) }
            }
        ))
    }

    func updatePosition(note: StickyNoteModel, translation: CGSize,
                        scale: CGFloat = 1, boundary: CGSize = .zero,
                        context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldX = note.x, oldY = note.y
        let newX = note.x + Double(translation.width)
        let newY = note.y + Double(translation.height)
        let clamped = CanvasBoundaryHelper.clamp(x: newX, y: newY, boundary: boundary,
                                                  elementSize: CGSize(width: note.width, height: note.height))
        note.x = clamped.x; note.y = clamped.y
        note.updatedAt = Date(); try? context.save()
        Task { await StickyNoteSyncService.shared.upsert(note) }

        let id = note.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<StickyNoteModel>()).first(where: { $0.id == id }) {
                    el.x = oldX; el.y = oldY; el.updatedAt = Date(); try? context.save()
                    Task { await StickyNoteSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<StickyNoteModel>()).first(where: { $0.id == id }) {
                    el.x = clamped.x; el.y = clamped.y; el.updatedAt = Date(); try? context.save()
                    Task { await StickyNoteSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    @discardableResult
    func duplicate(note: StickyNoteModel, zIndex: Int,
                   offset: CGSize = CGSize(width: 30, height: 30),
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) -> UUID? {
        let copy = StickyNoteModel(canvasID: note.canvasID,
                                   x: note.x + Double(offset.width),
                                   y: note.y + Double(offset.height))
        copy.text = note.text; copy.colorName = note.colorName
        copy.fontSize = note.fontSize; copy.isBold = note.isBold
        copy.isItalic = note.isItalic; copy.width = note.width
        copy.height = note.height; copy.isCollapsed = note.isCollapsed
        copy.zIndex = zIndex
        context.insert(copy); try? context.save()
        Task { await StickyNoteSyncService.shared.upsert(copy) }

        let id = copy.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<StickyNoteModel>()).first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await StickyNoteSyncService.shared.delete(el) }
                }
            },
            redo: {
                let el = StickyNoteModel(canvasID: note.canvasID,
                                         x: note.x + Double(offset.width),
                                         y: note.y + Double(offset.height))
                el.id = id; el.zIndex = zIndex
                context.insert(el); try? context.save()
                Task { await StickyNoteSyncService.shared.upsert(el) }
            }
        ))
        return id
    }

    func updateSize(note: StickyNoteModel, width: Double, height: Double,
                    context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldW = note.width, oldH = note.height
        note.width = max(96, width); note.height = max(72, height)
        note.updatedAt = Date(); try? context.save()
        Task { await StickyNoteSyncService.shared.upsert(note) }

        let id = note.id
        let newW = note.width, newH = note.height
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<StickyNoteModel>()).first(where: { $0.id == id }) {
                    el.width = oldW; el.height = oldH; el.updatedAt = Date(); try? context.save()
                    Task { await StickyNoteSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<StickyNoteModel>()).first(where: { $0.id == id }) {
                    el.width = newW; el.height = newH; el.updatedAt = Date(); try? context.save()
                    Task { await StickyNoteSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    func updateText(note: StickyNoteModel, text: String, context: ModelContext) {
        note.text = text; note.updatedAt = Date(); try? context.save()
        Task { await StickyNoteSyncService.shared.upsert(note) }
    }

    func startWriting(noteID: UUID) {
        editingID = noteID
        writingID = noteID
    }

    func setCollapsed(note: StickyNoteModel, collapsed: Bool, context: ModelContext) {
        note.isCollapsed = collapsed
        note.updatedAt = Date()
        if collapsed, writingID == note.id {
            writingID = nil
        }
        try? context.save()
        Task { await StickyNoteSyncService.shared.upsert(note) }
    }

    func delete(note: StickyNoteModel, context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snap = (id: note.id, canvasID: note.canvasID, text: note.text,
                    x: note.x, y: note.y, width: note.width, height: note.height,
                    colorName: note.colorName, fontSize: note.fontSize,
                    isBold: note.isBold, isItalic: note.isItalic,
                    isCollapsed: note.isCollapsed, zIndex: note.zIndex)

        // Soft-delete on Supabase before removing locally
        Task { await StickyNoteSyncService.shared.delete(note) }
        context.delete(note); try? context.save()
        if editingID == snap.id { editingID = nil }
        if writingID == snap.id { writingID = nil }

        undoManager?.push(CanvasAction(
            undo: {
                let el = StickyNoteModel(canvasID: snap.canvasID, x: snap.x, y: snap.y)
                el.id = snap.id; el.text = snap.text; el.colorName = snap.colorName
                el.fontSize = snap.fontSize; el.isBold = snap.isBold
                el.isItalic = snap.isItalic; el.width = snap.width
                el.height = snap.height; el.isCollapsed = snap.isCollapsed
                el.zIndex = snap.zIndex
                context.insert(el); try? context.save()
                Task { await StickyNoteSyncService.shared.upsert(el) }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<StickyNoteModel>()).first(where: { $0.id == snap.id }) {
                    context.delete(el); try? context.save()
                    Task { await StickyNoteSyncService.shared.delete(el) }
                }
            }
        ))
    }

    func stopEditing() {
        editingID = nil
        writingID = nil
    }
}
