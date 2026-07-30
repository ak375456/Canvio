import CoreGraphics
import Foundation
import SwiftData

enum CanvasElementKind {
    case text
    case stickyNote
    case todoList
    case shape
    case image
    case pdf
    case pdfPage
    case table
    case audio
    case youtube
    case drawing
    case symbol
}

struct CanvasElementCollection {
    let textElements: [TextElementModel]
    let stickyNotes: [StickyNoteModel]
    let todoLists: [TodoListModel]
    let shapes: [ShapeElementModel]
    let images: [ImageElementModel]
    let pdfs: [PDFElementModel]
    let pdfPages: [PDFPageElementModel]
    let tables: [TableElementModel]
    let audioElements: [AudioElementModel]
    let youtubeElements: [YouTubeElementModel]
    let drawings: [DrawingElementModel]
    let symbols: [SymbolElementModel]

    var layerableElements: [any LayerableElement] {
        var elements: [any LayerableElement] = []
        elements += textElements as [any LayerableElement]
        elements += stickyNotes as [any LayerableElement]
        elements += todoLists as [any LayerableElement]
        elements += shapes as [any LayerableElement]
        elements += images as [any LayerableElement]
        elements += pdfs as [any LayerableElement]
        elements += pdfPages as [any LayerableElement]
        elements += tables as [any LayerableElement]
        elements += audioElements as [any LayerableElement]
        elements += youtubeElements as [any LayerableElement]
        elements += drawings as [any LayerableElement]
        elements += symbols as [any LayerableElement]
        return elements
    }

    func element(withID id: UUID) -> (any LayerableElement)? {
        if let element = textElements.first(where: { $0.id == id }) { return element }
        if let element = stickyNotes.first(where: { $0.id == id }) { return element }
        if let element = todoLists.first(where: { $0.id == id }) { return element }
        if let element = shapes.first(where: { $0.id == id }) { return element }
        if let element = images.first(where: { $0.id == id }) { return element }
        if let element = pdfs.first(where: { $0.id == id }) { return element }
        if let element = pdfPages.first(where: { $0.id == id }) { return element }
        if let element = tables.first(where: { $0.id == id }) { return element }
        if let element = audioElements.first(where: { $0.id == id }) { return element }
        if let element = youtubeElements.first(where: { $0.id == id }) { return element }
        if let element = drawings.first(where: { $0.id == id }) { return element }
        if let element = symbols.first(where: { $0.id == id }) { return element }
        return nil
    }

    func kind(forID id: UUID) -> CanvasElementKind? {
        if textElements.contains(where: { $0.id == id }) { return .text }
        if stickyNotes.contains(where: { $0.id == id }) { return .stickyNote }
        if todoLists.contains(where: { $0.id == id }) { return .todoList }
        if shapes.contains(where: { $0.id == id }) { return .shape }
        if images.contains(where: { $0.id == id }) { return .image }
        if pdfs.contains(where: { $0.id == id }) { return .pdf }
        if pdfPages.contains(where: { $0.id == id }) { return .pdfPage }
        if tables.contains(where: { $0.id == id }) { return .table }
        if audioElements.contains(where: { $0.id == id }) { return .audio }
        if youtubeElements.contains(where: { $0.id == id }) { return .youtube }
        if drawings.contains(where: { $0.id == id }) { return .drawing }
        if symbols.contains(where: { $0.id == id }) { return .symbol }
        return nil
    }

    func bounds(for element: any LayerableElement) -> ElementBounds {
        if let text = element as? TextElementModel {
            let lines = text.text.split(separator: "\n", omittingEmptySubsequences: false)
            let longestLine = lines.map(\.count).max() ?? 4
            let width = max(
                160,
                min(20_000, Double(longestLine) * Double(text.fontSize) * 0.62 + 32)
            )
            let height = max(40, Double(max(lines.count, 1)) * Double(text.fontSize) * 1.35 + 24)
            return ElementBounds(id: text.id, cx: text.x, cy: text.y, width: width, height: height)
        } else if let sticky = element as? StickyNoteModel {
            return ElementBounds(id: sticky.id, cx: sticky.x, cy: sticky.y, width: sticky.width, height: sticky.height)
        } else if let todo = element as? TodoListModel {
            return ElementBounds(id: todo.id, cx: todo.x, cy: todo.y, width: todo.width, height: todo.height)
        } else if let shape = element as? ShapeElementModel {
            return ElementBounds(id: shape.id, cx: shape.x, cy: shape.y, width: shape.width, height: shape.height)
        } else if let image = element as? ImageElementModel {
            return ElementBounds(id: image.id, cx: image.x, cy: image.y, width: image.width, height: image.height)
        } else if let pdf = element as? PDFElementModel {
            return ElementBounds(id: pdf.id, cx: pdf.x, cy: pdf.y, width: pdf.width, height: pdf.height)
        } else if let page = element as? PDFPageElementModel {
            return ElementBounds(id: page.id, cx: page.x, cy: page.y, width: page.width, height: page.height)
        } else if let table = element as? TableElementModel {
            return ElementBounds(id: table.id, cx: table.x, cy: table.y, width: table.totalWidth, height: table.totalHeight)
        } else if let audio = element as? AudioElementModel {
            return ElementBounds(id: audio.id, cx: audio.x, cy: audio.y, width: audio.width, height: audio.height)
        } else if let youtube = element as? YouTubeElementModel {
            return ElementBounds(id: youtube.id, cx: youtube.x, cy: youtube.y, width: youtube.width, height: youtube.height)
        } else if let drawing = element as? DrawingElementModel {
            return ElementBounds(id: drawing.id, cx: drawing.x, cy: drawing.y, width: drawing.width, height: drawing.height)
        } else if let symbol = element as? SymbolElementModel {
            let size = symbol.fontSize + 24
            return ElementBounds(id: symbol.id, cx: symbol.x, cy: symbol.y, width: size, height: size)
        }

        return ElementBounds(id: element.id, cx: 0, cy: 0, width: 80, height: 80)
    }
}

@MainActor
enum CanvasElementSyncRouter {
    static func upsert(_ element: any LayerableElement) async {
        if let element = element as? TextElementModel {
            await TextSyncService.shared.upsert(element)
        } else if let element = element as? StickyNoteModel {
            await StickyNoteSyncService.shared.upsert(element)
        } else if let element = element as? TodoListModel {
            await TodoSyncService.shared.upsertList(element)
        } else if let element = element as? ShapeElementModel {
            await ShapeSyncService.shared.upsert(element)
        } else if let element = element as? ImageElementModel {
            await ImageSyncService.shared.upsert(element)
        } else if let element = element as? PDFElementModel {
            await PDFSyncService.shared.upsert(element)
        } else if let element = element as? PDFPageElementModel {
            await PDFWorkspaceSyncService.shared.upsert(element)
        } else if let element = element as? TableElementModel {
            await TableSyncService.shared.upsertTable(element)
        } else if let element = element as? AudioElementModel {
            await AudioSyncService.shared.upsert(element)
        } else if let element = element as? YouTubeElementModel {
            await YouTubeSyncService.shared.upsert(element)
        } else if let element = element as? DrawingElementModel {
            await DrawingSyncService.shared.upsert(element)
        } else if let element = element as? SymbolElementModel {
            await SymbolSyncService.shared.upsert(element)
        }
    }
}

extension CanvasViewModel {
    func deleteLayerableElement(_ element: any LayerableElement,
                                todoTasks: [TodoTaskModel],
                                tableCells: [TableCellModel],
                                connectors: [ConnectorModel],
                                context: ModelContext) {
        undoManager.beginGrouping(name: "Delete canvas item")
        defer { undoManager.endGrouping() }

        if let element = element as? TextElementModel {
            textVM.delete(element: element, context: context, undoManager: undoManager)
        } else if let element = element as? StickyNoteModel {
            stickyVM.delete(note: element, context: context, undoManager: undoManager)
        } else if let element = element as? TodoListModel {
            todoVM.delete(
                list: element,
                tasks: todoTasks.filter { $0.listID == element.id },
                context: context,
                undoManager: undoManager
            )
        } else if let element = element as? ShapeElementModel {
            shapeVM.delete(shape: element, context: context, undoManager: undoManager)
        } else if let element = element as? ImageElementModel {
            imageVM.delete(element: element, context: context, undoManager: undoManager)
        } else if let element = element as? PDFElementModel {
            pdfVM.delete(element: element, context: context, undoManager: undoManager)
        } else if let element = element as? PDFPageElementModel {
            pdfPageVM.delete(element: element, context: context, undoManager: undoManager)
        } else if let element = element as? TableElementModel {
            tableVM.delete(
                table: element,
                cells: tableCells.filter { $0.tableID == element.id },
                context: context,
                undoManager: undoManager
            )
        } else if let element = element as? AudioElementModel {
            audioVM.delete(element: element, context: context, undoManager: undoManager)
        } else if let element = element as? YouTubeElementModel {
            youtubeVM.delete(element: element, context: context, undoManager: undoManager)
        } else if let element = element as? DrawingElementModel {
            drawingVM.delete(element: element, context: context, undoManager: undoManager)
        } else if let element = element as? SymbolElementModel {
            symbolVM.delete(element: element, context: context, undoManager: undoManager)
        } else {
            return
        }

        connectorVM.deleteOrphanedConnectors(
            for: element.id,
            allConnectors: connectors,
            context: context,
            undoManager: undoManager
        )
    }
}
