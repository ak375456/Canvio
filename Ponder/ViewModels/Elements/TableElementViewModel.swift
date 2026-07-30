//
//  TableElementViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

struct TableCellHistoryState: Equatable {
    let id: UUID
    let tableID: UUID
    let row: Int
    let col: Int
    let value: String
    let backgroundColorName: String
    let textColorName: String
    let alignmentRaw: String
    let isBold: Bool
    let isMerged: Bool
    let mergeOriginRow: Int
    let mergeOriginCol: Int
    let colSpan: Int
    let rowSpan: Int

    init(_ cell: TableCellModel) {
        id = cell.id
        tableID = cell.tableID
        row = cell.row
        col = cell.col
        value = cell.value
        backgroundColorName = cell.backgroundColorName
        textColorName = cell.textColorName
        alignmentRaw = cell.alignmentRaw
        isBold = cell.isBold
        isMerged = cell.isMerged
        mergeOriginRow = cell.mergeOriginRow
        mergeOriginCol = cell.mergeOriginCol
        colSpan = cell.colSpan
        rowSpan = cell.rowSpan
    }

    func apply(to cell: TableCellModel) {
        cell.row = row
        cell.col = col
        cell.value = value
        cell.backgroundColorName = backgroundColorName
        cell.textColorName = textColorName
        cell.alignmentRaw = alignmentRaw
        cell.isBold = isBold
        cell.isMerged = isMerged
        cell.mergeOriginRow = mergeOriginRow
        cell.mergeOriginCol = mergeOriginCol
        cell.colSpan = colSpan
        cell.rowSpan = rowSpan
        cell.updatedAt = Date()
    }

    func makeModel() -> TableCellModel {
        let cell = TableCellModel(tableID: tableID, row: row, col: col)
        cell.id = id
        apply(to: cell)
        return cell
    }
}

struct TableElementHistoryState: Equatable {
    let id: UUID
    let canvasID: UUID
    let x: Double
    let y: Double
    let rowCount: Int
    let colCount: Int
    let cellWidth: Double
    let cellHeight: Double
    let rotation: Double
    let zIndex: Int
    let groupID: UUID?
    let isLayerHidden: Bool
    let layerOpacity: Double
    let colHeaderColorName: String
    let rowHeaderColorName: String
    let showColHeaders: Bool
    let showRowHeaders: Bool
    let cells: [TableCellHistoryState]

    init(_ table: TableElementModel, cells: [TableCellModel]) {
        id = table.id
        canvasID = table.canvasID
        x = table.x
        y = table.y
        rowCount = table.rowCount
        colCount = table.colCount
        cellWidth = table.cellWidth
        cellHeight = table.cellHeight
        rotation = table.rotation
        zIndex = table.zIndex
        groupID = table.groupID
        isLayerHidden = table.isLayerHidden
        layerOpacity = table.layerOpacity
        colHeaderColorName = table.colHeaderColorName
        rowHeaderColorName = table.rowHeaderColorName
        showColHeaders = table.showColHeaders
        showRowHeaders = table.showRowHeaders
        self.cells = cells
            .filter { $0.tableID == table.id }
            .map(TableCellHistoryState.init)
            .sorted {
                if $0.row == $1.row { return $0.col < $1.col }
                return $0.row < $1.row
            }
    }

    func apply(to table: TableElementModel) {
        table.x = x
        table.y = y
        table.rowCount = rowCount
        table.colCount = colCount
        table.cellWidth = cellWidth
        table.cellHeight = cellHeight
        table.rotation = rotation
        table.zIndex = zIndex
        table.groupID = groupID
        table.isLayerHidden = isLayerHidden
        table.layerOpacity = layerOpacity
        table.colHeaderColorName = colHeaderColorName
        table.rowHeaderColorName = rowHeaderColorName
        table.showColHeaders = showColHeaders
        table.showRowHeaders = showRowHeaders
        table.updatedAt = Date()
    }

    func makeTable() -> TableElementModel {
        let table = TableElementModel(
            canvasID: canvasID,
            rows: rowCount,
            cols: colCount,
            x: x,
            y: y
        )
        table.id = id
        apply(to: table)
        return table
    }
}

@MainActor
private func applyTableHistoryState(_ state: TableElementHistoryState, context: ModelContext) {
    let allTables = (try? context.fetch(FetchDescriptor<TableElementModel>())) ?? []
    let table: TableElementModel
    if let existing = allTables.first(where: { $0.id == state.id }) {
        table = existing
        state.apply(to: existing)
    } else {
        table = state.makeTable()
        context.insert(table)
    }

    let allCells = (try? context.fetch(FetchDescriptor<TableCellModel>())) ?? []
    let currentCells = allCells.filter { $0.tableID == state.id }
    let desiredIDs = Set(state.cells.map(\.id))
    let currentByID = Dictionary(uniqueKeysWithValues: currentCells.map { ($0.id, $0) })

    for cell in currentCells where !desiredIDs.contains(cell.id) {
        context.delete(cell)
    }
    var restoredCells: [TableCellModel] = []
    for cellState in state.cells {
        if let current = currentByID[cellState.id] {
            cellState.apply(to: current)
            restoredCells.append(current)
        } else {
            let restored = cellState.makeModel()
            context.insert(restored)
            restoredCells.append(restored)
        }
    }
    try? context.save()
    Task {
        await TableSyncService.shared.upsertTable(table)
        await TableSyncService.shared.upsertCells(restoredCells)
        for cell in currentCells where !desiredIDs.contains(cell.id) {
            await TableSyncService.shared.deleteCell(cell)
        }
    }
}

@MainActor
private func recordTableChange(
    name: String,
    table: TableElementModel,
    cells: [TableCellModel],
    from oldState: TableElementHistoryState,
    context: ModelContext,
    undoManager: CanvasUndoManager?
) {
    guard let undoManager else { return }
    let currentCells = (try? context.fetch(FetchDescriptor<TableCellModel>())) ?? cells
    let newState = TableElementHistoryState(table, cells: currentCells)
    undoManager.recordChange(name: name, from: oldState, to: newState) {
        applyTableHistoryState($0, context: context)
    }
}

@MainActor
func recordTableCellChange(
    name: String,
    cell: TableCellModel,
    from oldState: TableCellHistoryState,
    context: ModelContext,
    undoManager: CanvasUndoManager,
    coalescingKey: String? = nil
) {
    let newState = TableCellHistoryState(cell)
    let id = cell.id
    undoManager.recordChange(
        name: name,
        from: oldState,
        to: newState,
        coalescingKey: coalescingKey
    ) { state in
        guard let values = try? context.fetch(FetchDescriptor<TableCellModel>()),
              let current = values.first(where: { $0.id == id }) else { return }
        state.apply(to: current)
        try? context.save()
        Task { await TableSyncService.shared.upsertCell(current) }
    }
}

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

    @discardableResult
    func duplicate(table: TableElementModel, cells: [TableCellModel], zIndex: Int,
                   offset: CGSize = CGSize(width: 30, height: 30),
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) -> UUID? {
        let copy = TableElementModel(canvasID: table.canvasID,
                                     rows: table.rowCount, cols: table.colCount,
                                     x: table.x + Double(offset.width),
                                     y: table.y + Double(offset.height))
        copy.cellWidth = table.cellWidth; copy.cellHeight = table.cellHeight
        copy.showColHeaders = table.showColHeaders; copy.showRowHeaders = table.showRowHeaders
        copy.zIndex = zIndex
        context.insert(copy)
        var copiedCells: [TableCellModel] = []
        let tableCells = cells.filter { $0.tableID == table.id }
        for cell in tableCells {
            let newCell = TableCellModel(tableID: copy.id, row: cell.row, col: cell.col)
            newCell.value = cell.value
            newCell.backgroundColorName = cell.backgroundColorName
            newCell.textColorName = cell.textColorName
            newCell.alignmentRaw = cell.alignmentRaw
            newCell.isBold = cell.isBold
            newCell.isMerged = cell.isMerged
            newCell.mergeOriginRow = cell.mergeOriginRow
            newCell.mergeOriginCol = cell.mergeOriginCol
            newCell.colSpan = cell.colSpan
            newCell.rowSpan = cell.rowSpan
            context.insert(newCell)
            copiedCells.append(newCell)
        }
        try? context.save()
        Task {
            await TableSyncService.shared.upsertTable(copy)
            await TableSyncService.shared.upsertCells(copiedCells)
        }

        let id = copy.id
        let snapshot = TableElementHistoryState(copy, cells: copiedCells)
        undoManager?.push(CanvasAction(name: "Duplicate table",
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
                applyTableHistoryState(snapshot, context: context)
            }
        ))
        return id
    }

    func selectTable(id: UUID) { selectedTableID = id; selectedCellID = nil; editingCellID = nil }
    func selectCell(id: UUID)  { selectedCellID = id; editingCellID = nil }
    func startEditing(id: UUID){ editingCellID = id; selectedCellID = id }
    func stopEditing()         { editingCellID = nil }
    func stopAll()             { selectedTableID = nil; selectedCellID = nil; editingCellID = nil }

    func addRow(to table: TableElementModel, cells: [TableCellModel], context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let oldState = TableElementHistoryState(table, cells: cells)
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
        recordTableChange(
            name: "Add table row", table: table, cells: cells + newCells,
            from: oldState, context: context, undoManager: undoManager
        )
    }

    func addColumn(to table: TableElementModel, cells: [TableCellModel], context: ModelContext,
                   undoManager: CanvasUndoManager? = nil) {
        let oldState = TableElementHistoryState(table, cells: cells)
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
        recordTableChange(
            name: "Add table column", table: table, cells: cells + newCells,
            from: oldState, context: context, undoManager: undoManager
        )
    }

    func deleteLastRow(from table: TableElementModel, cells: [TableCellModel], context: ModelContext,
                       undoManager: CanvasUndoManager? = nil) {
        guard table.rowCount > 1 else { return }
        let oldState = TableElementHistoryState(table, cells: cells)
        let lastRow = table.rowCount - 1
        let toDelete = cells.filter { $0.row == lastRow }
        toDelete.forEach { context.delete($0) }
        table.rowCount -= 1; table.updatedAt = Date(); try? context.save()
        Task {
            await TableSyncService.shared.upsertTable(table)
            for cell in toDelete { await TableSyncService.shared.deleteCell(cell) }
        }
        recordTableChange(
            name: "Delete table row", table: table,
            cells: cells.filter { $0.row != lastRow },
            from: oldState, context: context, undoManager: undoManager
        )
    }

    func deleteLastColumn(from table: TableElementModel, cells: [TableCellModel], context: ModelContext,
                          undoManager: CanvasUndoManager? = nil) {
        guard table.colCount > 1 else { return }
        let oldState = TableElementHistoryState(table, cells: cells)
        let lastCol = table.colCount - 1
        let toDelete = cells.filter { $0.col == lastCol }
        toDelete.forEach { context.delete($0) }
        table.colCount -= 1; table.updatedAt = Date(); try? context.save()
        Task {
            await TableSyncService.shared.upsertTable(table)
            for cell in toDelete { await TableSyncService.shared.deleteCell(cell) }
        }
        recordTableChange(
            name: "Delete table column", table: table,
            cells: cells.filter { $0.col != lastCol },
            from: oldState, context: context, undoManager: undoManager
        )
    }

    func setCellBackground(_ cell: TableCellModel, colorName: String, context: ModelContext,
                           undoManager: CanvasUndoManager? = nil) {
        let oldState = TableCellHistoryState(cell)
        cell.backgroundColorName = colorName
        cell.updatedAt = Date()
        try? context.save()
        Task { await TableSyncService.shared.upsertCell(cell) }
        if let undoManager {
            recordTableCellChange(
                name: "Change cell background", cell: cell, from: oldState,
                context: context, undoManager: undoManager
            )
        }
    }

    func setCellAlignment(_ cell: TableCellModel, alignment: TextAlignment, context: ModelContext,
                          undoManager: CanvasUndoManager? = nil) {
        let oldState = TableCellHistoryState(cell)
        cell.alignment = alignment
        cell.updatedAt = Date()
        try? context.save()
        Task { await TableSyncService.shared.upsertCell(cell) }
        if let undoManager {
            recordTableCellChange(
                name: "Align table cell", cell: cell, from: oldState,
                context: context, undoManager: undoManager
            )
        }
    }

    func toggleBold(_ cell: TableCellModel, context: ModelContext,
                    undoManager: CanvasUndoManager? = nil) {
        let oldState = TableCellHistoryState(cell)
        cell.isBold.toggle()
        cell.updatedAt = Date()
        try? context.save()
        Task { await TableSyncService.shared.upsertCell(cell) }
        if let undoManager {
            recordTableCellChange(
                name: "Toggle cell bold", cell: cell, from: oldState,
                context: context, undoManager: undoManager
            )
        }
    }

    func mergeRight(_ cell: TableCellModel, table: TableElementModel, cells: [TableCellModel],
                    context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        guard cell.col + cell.colSpan < table.colCount else { return }
        let oldState = TableElementHistoryState(table, cells: cells)
        if let next = cells.first(where: { $0.row == cell.row && $0.col == cell.col + cell.colSpan }) {
            next.isMerged = true; next.mergeOriginRow = cell.row; next.mergeOriginCol = cell.col
            next.updatedAt = Date()
            Task { await TableSyncService.shared.upsertCell(next) }
        }
        cell.colSpan += 1
        cell.updatedAt = Date()
        try? context.save()
        Task { await TableSyncService.shared.upsertCell(cell) }
        recordTableChange(
            name: "Merge table cells", table: table, cells: cells,
            from: oldState, context: context, undoManager: undoManager
        )
    }

    func splitCell(_ cell: TableCellModel, table: TableElementModel, cells: [TableCellModel],
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        guard cell.colSpan > 1 else { return }
        let oldState = TableElementHistoryState(table, cells: cells)
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
        recordTableChange(
            name: "Split table cells", table: table, cells: cells,
            from: oldState, context: context, undoManager: undoManager
        )
    }

    func importCSV(_ csv: String, into table: TableElementModel, cells: [TableCellModel],
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let parsed = CSVService.parse(csv)
        guard !parsed.isEmpty else { return }
        let oldState = TableElementHistoryState(table, cells: cells)
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
        let availableCells = cells + newCells
        for (r, rowData) in parsed.enumerated() {
            for (c, val) in rowData.enumerated() {
                if let cell = availableCells.first(where: { $0.row == r && $0.col == c }) {
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
        recordTableChange(
            name: "Import CSV", table: table, cells: availableCells,
            from: oldState, context: context, undoManager: undoManager
        )
    }

    func delete(table: TableElementModel, cells: [TableCellModel], context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let tableCells = cells.filter { $0.tableID == table.id }
        let snapshot = TableElementHistoryState(table, cells: tableCells)

        Task { await TableSyncService.shared.deleteTable(table, cells: tableCells) }

        tableCells.forEach { context.delete($0) }
        context.delete(table); try? context.save()

        if selectedTableID == snapshot.id { stopAll() }

        undoManager?.push(CanvasAction(name: "Delete table",
            undo: {
                applyTableHistoryState(snapshot, context: context)
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<TableElementModel>()).first(where: { $0.id == snapshot.id }) {
                    let allCells = (try? context.fetch(FetchDescriptor<TableCellModel>())) ?? []
                    let cs = allCells.filter { $0.tableID == snapshot.id }
                    cs.forEach { context.delete($0) }
                    context.delete(el); try? context.save()
                    Task { await TableSyncService.shared.deleteTable(el, cells: cs) }
                }
            }
        ))
    }
}
