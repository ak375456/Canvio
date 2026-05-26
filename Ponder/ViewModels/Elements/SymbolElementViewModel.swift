//
//  SymbolElementViewModel.swift
//  Canvio
//

import SwiftUI
import SwiftData
import Combine

@MainActor
class SymbolElementViewModel: ObservableObject {
    @Published var editingID: UUID? = nil

    // MARK: - Add

    func addSymbol(canvasID: UUID, symbolName: String, colorName: String,
                   fontSize: Double, center: CGPoint,
                   offset: CGSize, scale: CGFloat, zIndex: Int,
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let x = (center.x - offset.width)  / scale
        let y = (center.y - offset.height) / scale
        let el = SymbolElementModel(canvasID: canvasID, symbolName: symbolName,
                                    colorName: colorName, fontSize: fontSize,
                                    x: x, y: y)
        el.zIndex    = zIndex
        el.updatedAt = Date()
        context.insert(el); try? context.save()
        editingID = el.id
        Task { await SymbolSyncService.shared.upsert(el) }

        let id = el.id
        undoManager?.push(CanvasAction(
            undo: {
                if let e = try? context.fetch(FetchDescriptor<SymbolElementModel>())
                    .first(where: { $0.id == id }) {
                    context.delete(e); try? context.save()
                    Task { await SymbolSyncService.shared.delete(e) }
                }
            },
            redo: {
                let e = SymbolElementModel(canvasID: canvasID, symbolName: symbolName,
                                           colorName: colorName, fontSize: fontSize,
                                           x: x, y: y)
                e.id = id; e.zIndex = zIndex; e.updatedAt = Date()
                context.insert(e); try? context.save()
                Task { await SymbolSyncService.shared.upsert(e) }
            }
        ))
    }

    // MARK: - Position

    func updatePosition(element: SymbolElementModel, translation: CGSize,
                        scale: CGFloat = 1, boundary: CGSize = .zero,
                        context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldX = element.x, oldY = element.y
        let newX = element.x + Double(translation.width)
        let newY = element.y + Double(translation.height)
        let clamped = CanvasBoundaryHelper.clamp(x: newX, y: newY, boundary: boundary,
                                                  elementSize: CGSize(width: element.fontSize,
                                                                      height: element.fontSize))
        element.x = clamped.x; element.y = clamped.y
        element.updatedAt = Date(); try? context.save()
        Task { await SymbolSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let e = try? context.fetch(FetchDescriptor<SymbolElementModel>())
                    .first(where: { $0.id == id }) {
                    e.x = oldX; e.y = oldY; e.updatedAt = Date()
                    try? context.save()
                    Task { await SymbolSyncService.shared.upsert(e) }
                }
            },
            redo: {
                if let e = try? context.fetch(FetchDescriptor<SymbolElementModel>())
                    .first(where: { $0.id == id }) {
                    e.x = clamped.x; e.y = clamped.y; e.updatedAt = Date()
                    try? context.save()
                    Task { await SymbolSyncService.shared.upsert(e) }
                }
            }
        ))
    }

    // MARK: - Formatting

    func setColor(_ colorName: String, element: SymbolElementModel, context: ModelContext) {
        element.colorName = colorName; element.updatedAt = Date(); try? context.save()
        Task { await SymbolSyncService.shared.upsert(element) }
    }

    func setFontSize(_ size: Double, element: SymbolElementModel, context: ModelContext) {
        element.fontSize  = max(16, min(200, size)); element.updatedAt = Date(); try? context.save()
        Task { await SymbolSyncService.shared.upsert(element) }
    }

    // MARK: - Duplicate

    @discardableResult
    func duplicate(element: SymbolElementModel, zIndex: Int,
                   offset: CGSize = CGSize(width: 30, height: 30),
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) -> UUID? {
        let copy = SymbolElementModel(canvasID: element.canvasID,
                                      symbolName: element.symbolName,
                                      colorName:  element.colorName,
                                      fontSize:   element.fontSize,
                                      x: element.x + Double(offset.width),
                                      y: element.y + Double(offset.height))
        copy.zIndex = zIndex; copy.updatedAt = Date()
        context.insert(copy); try? context.save()
        Task { await SymbolSyncService.shared.upsert(copy) }

        let id = copy.id
        undoManager?.push(CanvasAction(
            undo: {
                if let e = try? context.fetch(FetchDescriptor<SymbolElementModel>())
                    .first(where: { $0.id == id }) {
                    context.delete(e); try? context.save()
                    Task { await SymbolSyncService.shared.delete(e) }
                }
            },
            redo: {
                let e = SymbolElementModel(canvasID: element.canvasID,
                                           symbolName: element.symbolName,
                                           colorName:  element.colorName,
                                           fontSize:   element.fontSize,
                                           x: element.x + Double(offset.width),
                                           y: element.y + Double(offset.height))
                e.id = id; e.zIndex = zIndex; e.updatedAt = Date()
                context.insert(e); try? context.save()
                Task { await SymbolSyncService.shared.upsert(e) }
            }
        ))
        return id
    }

    // MARK: - Delete

    func delete(element: SymbolElementModel, context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snap = (id: element.id, canvasID: element.canvasID,
                    symbolName: element.symbolName, colorName: element.colorName,
                    fontSize: element.fontSize, x: element.x, y: element.y,
                    zIndex: element.zIndex)
        Task { await SymbolSyncService.shared.delete(element) }
        context.delete(element); try? context.save()
        if editingID == snap.id { editingID = nil }

        undoManager?.push(CanvasAction(
            undo: {
                let e = SymbolElementModel(canvasID: snap.canvasID,
                                           symbolName: snap.symbolName,
                                           colorName:  snap.colorName,
                                           fontSize:   snap.fontSize,
                                           x: snap.x, y: snap.y)
                e.id = snap.id; e.zIndex = snap.zIndex; e.updatedAt = Date()
                context.insert(e); try? context.save()
                Task { await SymbolSyncService.shared.upsert(e) }
            },
            redo: {
                if let e = try? context.fetch(FetchDescriptor<SymbolElementModel>())
                    .first(where: { $0.id == snap.id }) {
                    context.delete(e); try? context.save()
                    Task { await SymbolSyncService.shared.delete(e) }
                }
            }
        ))
    }

    func stopEditing() { editingID = nil }

    // MARK: - Color helpers

    func colorFromName(_ name: String) -> Color {
        switch name {
        case "blue":    return .blue
        case "red":     return .red
        case "green":   return .green
        case "orange":  return .orange
        case "purple":  return .purple
        case "pink":    return .pink
        case "teal":    return .teal
        case "yellow":  return .yellow
        case "indigo":  return .indigo
        case "mint":    return .mint
        case "cyan":    return .cyan
        case "brown":   return .brown
        case "gray":    return .gray
        case "black":   return Color(white: 0.1)
        case "white":   return .white
        default:        return .primary
        }
    }

    let colorOptions: [(name: String, color: Color)] = [
        ("primary", .primary), ("blue",   .blue),   ("red",    .red),
        ("green",   .green),   ("orange", .orange),  ("purple", .purple),
        ("pink",    .pink),    ("teal",   .teal),    ("yellow", .yellow),
        ("indigo",  .indigo),  ("mint",   .mint),    ("cyan",   .cyan),
        ("brown",   .brown),   ("gray",   .gray),
    ]
}
