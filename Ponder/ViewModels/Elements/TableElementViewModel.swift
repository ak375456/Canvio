//
//  TableElementViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

@MainActor
class TableElementViewModel: ObservableObject {
    @Published var selectedTableID: UUID? = nil
    @Published var selectedCellID: UUID? = nil
    @Published var editingCellID: UUID? = nil

    func addTable(canvasID: UUID, rows: Int, cols: Int, center: CGPoint,
                  offset: CGSize, scale: CGFloat, zIndex: Int,
                  context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let canvasX = (center.x - offset.width) / scale
        let canvasY = (center.y - offset.height) / scale
        let table = TableElementModel(canvasID: canvasID, rows: rows, cols: cols, x: canvasX, y: canvasY)
        table.zIndex = zIndex
        context.insert(table)
        var newCells: [TableCellModel] = []
        for r in 0..<rows {
            for c in 0..<cols {
                let cell = TableCellModel(tableID: table.id, row: r, col: c)
                context.insert(cell)
                newCells.append(cell)
            }
        }
        try? context.save()
        selectedTableID = table.id

        Task {
            await TableSyncService.shared.upsertTable(table)
            await TableSyncService.shared.upsertCells(newCells)
        }

        let id = table.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TableElementModel>()).first(where: { $0.id == id }) {
                    let cells = (try? context.fetch(FetchDescriptor<TableCellModel>())) ?? []
                    let tableCells = cells.filter { $0.tableID == id }
                    tableCells.forEach { context.delete($0) }
                    context.delete(el); try? context.save()
                    Task { await TableSyncService.shared.deleteTable(el, cells: tableCells) }
                }
            },
            redo: {
                let el = TableElementModel(canvasID: canvasID, rows: rows, cols: cols, x: canvasX, y: canvasY)
                el.id = id; el.zIndex = zIndex
                context.insert(el)
                var redoCells: [TableCellModel] = []
                for r in 0..<rows {
                    for c in 0..<cols {
                        let cell = TableCellModel(tableID: id, row: r, col: c)
                        context.insert(cell)
                        redoCells.append(cell)
                    }
                }
                try? context.save()
                Task {
                    await TableSyncService.shared.upsertTable(el)
                    await TableSyncService.shared.upsertCells(redoCells)
                }
            }
        ))
    }

    func updatePosition(table: TableElementModel, translation: CGSize,
                        scale: CGFloat = 1, boundary: CGSize = .zero,
                        context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldX = table.x, oldY = table.y
        let tableW = table.cellWidth * Double(table.colCount) + 36
        let tableH = table.cellHeight * Double(table.rowCount) + 28
        let newX = table.x + Double(translation.width)
        let newY = table.y + Double(translation.height)
        let clamped = CanvasBoundaryHelper.clamp(x: newX, y: newY, boundary: boundary,
                                                  elementSize: CGSize(width: tableW, height: tableH))
        table.x = clamped.x; table.y = clamped.y
        table.updatedAt = Date(); try? context.save()
        Task { await TableSyncService.shared.upsertTable(table) }

        let id = table.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TableElementModel>()).first(where: { $0.id == id }) {
                    el.x = oldX; el.y = oldY; el.updatedAt = Date(); try? context.save()
                    Task { await TableSyncService.shared.upsertTable(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<TableElementModel>()).first(where: { $0.id == id }) {
                    el.x = clamped.x; el.y = clamped.y; el.updatedAt = Date(); try? context.save()
                    Task { await TableSyncService.shared.upsertTable(el) }
                }
            }
        ))
    }

    func duplicate(table: TableElementModel, cells: [TableCellModel], zIndex: Int,
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let copy = TableElementModel(canvasID: table.canvasID,
                                     rows: table.rowCount, cols: table.colCount,
                                     x: table.x + 30, y: table.y + 30)
        copy.cellWidth = table.cellWidth; copy.cellHeight = table.cellHeight
        copy.showColHeaders = table.showColHeaders; copy.showRowHeaders = table.showRowHeaders
        copy.zIndex = zIndex
        context.insert(copy)
        var copiedCells: [TableCellModel] = []
        let tableCells = cells.filter { $0.tableID == table.id }
        for cell in tableCells {
            let newCell = TableCellModel(tableID: copy.id, row: cell.row, col: cell.col)
            newCell.value = cell.value; newCell.isBold = cell.isBold
            newCell.alignmentRaw = cell.alignmentRaw
            context.insert(newCell)
            copiedCells.append(newCell)
        }
        try? context.save()
        Task {
            await TableSyncService.shared.upsertTable(copy)
            await TableSyncService.shared.upsertCells(copiedCells)
        }

        let id = copy.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TableElementModel>()).first(where: { $0.id == id }) {
                    let allCells = (try? context.fetch(FetchDescriptor<TableCellModel>())) ?? []
                    let elCells = allCells.filter { $0.tableID == id }
                    elCells.forEach { context.delete($0) }
                    context.delete(el); try? context.save()
                    Task { await TableSyncService.shared.deleteTable(el, cells: elCells) }
                }
            },
            redo: {
                let el = TableElementModel(canvasID: table.canvasID,
                                           rows: table.rowCount, cols: table.colCount,
                                           x: table.x + 30, y: table.y + 30)
                el.id = id; el.zIndex = zIndex
                context.insert(el)
                var redoCells: [TableCellModel] = []
                for r in 0..<table.rowCount {
                    for c in 0..<table.colCount {
                        let cell = TableCellModel(tableID: id, row: r, col: c)
                        context.insert(cell)
                        redoCells.append(cell)
                    }
                }
                try? context.save()
                Task {
                    await TableSyncService.shared.upsertTable(el)
                    await TableSyncService.shared.upsertCells(redoCells)
                }
            }
        ))
    }

    func selectTable(id: UUID) { selectedTableID = id; selectedCellID = nil; editingCellID = nil }
    func selectCell(id: UUID)  { selectedCellID = id; editingCellID = nil }
    func startEditing(id: UUID){ editingCellID = id; selectedCellID = id }
    func stopEditing()         { editingCellID = nil }
    func stopAll()             { selectedTableID = nil; selectedCellID = nil; editingCellID = nil }

    func addRow(to table: TableElementModel, cells: [TableCellModel], context: ModelContext) {
        let newRow = table.rowCount
        var newCells: [TableCellModel] = []
        for c in 0..<table.colCount {
            let cell = TableCellModel(tableID: table.id, row: newRow, col: c)
            context.insert(cell)
            newCells.append(cell)
        }
        table.rowCount += 1; table.updatedAt = Date(); try? context.save()
        Task {
            await TableSyncService.shared.upsertTable(table)
            await TableSyncService.shared.upsertCells(newCells)
        }
    }

    func addColumn(to table: TableElementModel, cells: [TableCellModel], context: ModelContext) {
        let newCol = table.colCount
        var newCells: [TableCellModel] = []
        for r in 0..<table.rowCount {
            let cell = TableCellModel(tableID: table.id, row: r, col: newCol)
            context.insert(cell)
            newCells.append(cell)
        }
        table.colCount += 1; table.updatedAt = Date(); try? context.save()
        Task {
            await TableSyncService.shared.upsertTable(table)
            await TableSyncService.shared.upsertCells(newCells)
        }
    }

    func deleteLastRow(from table: TableElementModel, cells: [TableCellModel], context: ModelContext) {
        guard table.rowCount > 1 else { return }
        let lastRow = table.rowCount - 1
        let toDelete = cells.filter { $0.row == lastRow }
        toDelete.forEach { context.delete($0) }
        table.rowCount -= 1; table.updatedAt = Date(); try? context.save()
        Task {
            await TableSyncService.shared.upsertTable(table)
            for cell in toDelete { await TableSyncService.shared.deleteCell(cell) }
        }
    }

    func deleteLastColumn(from table: TableElementModel, cells: [TableCellModel], context: ModelContext) {
        guard table.colCount > 1 else { return }
        let lastCol = table.colCount - 1
        let toDelete = cells.filter { $0.col == lastCol }
        toDelete.forEach { context.delete($0) }
        table.colCount -= 1; table.updatedAt = Date(); try? context.save()
        Task {
            await TableSyncService.shared.upsertTable(table)
            for cell in toDelete { await TableSyncService.shared.deleteCell(cell) }
        }
    }

    func setCellBackground(_ cell: TableCellModel, colorName: String, context: ModelContext) {
        cell.backgroundColorName = colorName
        cell.updatedAt = Date()
        try? context.save()
        Task { await TableSyncService.shared.upsertCell(cell) }
    }

    func setCellAlignment(_ cell: TableCellModel, alignment: TextAlignment, context: ModelContext) {
        cell.alignment = alignment
        cell.updatedAt = Date()
        try? context.save()
        Task { await TableSyncService.shared.upsertCell(cell) }
    }

    func toggleBold(_ cell: TableCellModel, context: ModelContext) {
        cell.isBold.toggle()
        cell.updatedAt = Date()
        try? context.save()
        Task { await TableSyncService.shared.upsertCell(cell) }
    }

    func mergeRight(_ cell: TableCellModel, table: TableElementModel, cells: [TableCellModel], context: ModelContext) {
        guard cell.col + cell.colSpan < table.colCount else { return }
        if let next = cells.first(where: { $0.row == cell.row && $0.col == cell.col + cell.colSpan }) {
            next.isMerged = true; next.mergeOriginRow = cell.row; next.mergeOriginCol = cell.col
            next.updatedAt = Date()
            Task { await TableSyncService.shared.upsertCell(next) }
        }
        cell.colSpan += 1
        cell.updatedAt = Date()
        try? context.save()
        Task { await TableSyncService.shared.upsertCell(cell) }
    }

    func splitCell(_ cell: TableCellModel, cells: [TableCellModel], context: ModelContext) {
        guard cell.colSpan > 1 else { return }
        var updatedCells: [TableCellModel] = []
        for c in (cell.col + 1)..<(cell.col + cell.colSpan) {
            if let absorbed = cells.first(where: { $0.row == cell.row && $0.col == c }) {
                absorbed.isMerged = false; absorbed.mergeOriginRow = -1; absorbed.mergeOriginCol = -1
                absorbed.updatedAt = Date()
                updatedCells.append(absorbed)
            }
        }
        cell.colSpan = 1
        cell.updatedAt = Date()
        try? context.save()
        Task {
            await TableSyncService.shared.upsertCell(cell)
            await TableSyncService.shared.upsertCells(updatedCells)
        }
    }

    func importCSV(_ csv: String, into table: TableElementModel, cells: [TableCellModel], context: ModelContext) {
        let parsed = CSVService.parse(csv)
        guard !parsed.isEmpty else { return }
        let csvRows = parsed.count, csvCols = parsed.map { $0.count }.max() ?? 0
        var newCells: [TableCellModel] = []

        while table.rowCount < csvRows {
            let r = table.rowCount
            for c in 0..<table.colCount {
                let cell = TableCellModel(tableID: table.id, row: r, col: c)
                context.insert(cell); newCells.append(cell)
            }
            table.rowCount += 1
        }
        while table.colCount < csvCols {
            let c = table.colCount
            for r in 0..<table.rowCount {
                let cell = TableCellModel(tableID: table.id, row: r, col: c)
                context.insert(cell); newCells.append(cell)
            }
            table.colCount += 1
        }

        var updatedCells: [TableCellModel] = []
        for (r, rowData) in parsed.enumerated() {
            for (c, val) in rowData.enumerated() {
                if let cell = cells.first(where: { $0.row == r && $0.col == c }) {
                    cell.value = val
                    cell.updatedAt = Date()
                    updatedCells.append(cell)
                }
            }
        }

        table.updatedAt = Date(); try? context.save()
        Task {
            await TableSyncService.shared.upsertTable(table)
            await TableSyncService.shared.upsertCells(newCells)
            await TableSyncService.shared.upsertCells(updatedCells)
        }
    }

    func delete(table: TableElementModel, cells: [TableCellModel], context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snap = (id: table.id, canvasID: table.canvasID, rows: table.rowCount, cols: table.colCount,
                    x: table.x, y: table.y, zIndex: table.zIndex)
        let tableCells = cells.filter { $0.tableID == table.id }

        Task { await TableSyncService.shared.deleteTable(table, cells: tableCells) }

        tableCells.forEach { context.delete($0) }
        context.delete(table); try? context.save()

        if selectedTableID == snap.id { stopAll() }

        undoManager?.push(CanvasAction(
            undo: {
                let el = TableElementModel(canvasID: snap.canvasID, rows: snap.rows, cols: snap.cols,
                                           x: snap.x, y: snap.y)
                el.id = snap.id; el.zIndex = snap.zIndex
                context.insert(el)
                var redoCells: [TableCellModel] = []
                for r in 0..<snap.rows {
                    for c in 0..<snap.cols {
                        let cell = TableCellModel(tableID: snap.id, row: r, col: c)
                        context.insert(cell); redoCells.append(cell)
                    }
                }
                try? context.save()
                Task {
                    await TableSyncService.shared.upsertTable(el)
                    await TableSyncService.shared.upsertCells(redoCells)
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<TableElementModel>()).first(where: { $0.id == snap.id }) {
                    let allCells = (try? context.fetch(FetchDescriptor<TableCellModel>())) ?? []
                    let cs = allCells.filter { $0.tableID == snap.id }
                    cs.forEach { context.delete($0) }
                    context.delete(el); try? context.save()
                    Task { await TableSyncService.shared.deleteTable(el, cells: cs) }
                }
            }
        ))
    }
}
