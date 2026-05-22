//
//  TableSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

// MARK: - Row shapes
// Prefixed with "DB" to avoid any name clashes with SwiftUI views

private struct DBTableRow: Codable {
    let id:                    String
    let canvas_id:             String
    let user_id:               String
    let x:                     Double
    let y:                     Double
    let row_count:             Int
    let col_count:             Int
    let cell_width:            Double
    let cell_height:           Double
    let rotation:              Double
    let z_index:               Int
    let col_header_color_name: String
    let row_header_color_name: String
    let show_col_headers:      Bool
    let show_row_headers:      Bool
    let created_at:            String
    let updated_at:            String
    let is_deleted:            Bool
}

private struct DBTableCellRow: Codable {
    let id:                    String
    let table_id:              String
    let user_id:               String
    let row_index:             Int
    let col_index:             Int
    let value:                 String
    let background_color_name: String
    let text_color_name:       String
    let alignment_raw:         String
    let is_bold:               Bool
    let is_merged:             Bool
    let merge_origin_row:      Int
    let merge_origin_col:      Int
    let col_span:              Int
    let row_span:              Int
    let created_at:            String
    let updated_at:            String
    let is_deleted:            Bool
}

private struct TableDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct TableDeletePayload: Codable {
    let id:         String
    let user_id:    String
    let updated_at: String
}

private struct CellDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct CellDeletePayload: Codable {
    let id:         String
    let user_id:    String
    let updated_at: String
}

// MARK: - TableSyncService

@MainActor
final class TableSyncService {

    static let shared = TableSyncService()

    private let supabase = SupabaseService.shared.client
    private let queue    = SyncQueue.shared
    private let network  = NetworkMonitor.shared
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    // MARK: - Upsert Table

    func upsertTable(_ table: TableElementModel) async {
        guard let userID = AuthService.shared.currentUser?.id.uuidString else { return }
        let row = makeTableRow(table: table, userID: userID)

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertTable, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("table_elements")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertTable, payload: data))
            }
            print("⚠️ Table upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete Table (soft-deletes all cells first)

    func deleteTable(_ table: TableElementModel, cells: [TableCellModel]) async {
        guard let userID = AuthService.shared.currentUser?.id.uuidString else { return }

        // Soft-delete all cells first
        for cell in cells {
            await deleteCell(cell)
        }

        let tableID = table.id.uuidString
        let now     = iso.string(from: Date())

        guard network.isConnected else {
            let payload = TableDeletePayload(id: tableID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteTable, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("table_elements")
                .update(TableDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id",      value: tableID)
                .eq("user_id", value: userID)
                .execute()
        } catch {
            let payload = TableDeletePayload(id: tableID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteTable, payload: data))
            }
            print("⚠️ Table delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Upsert Cell

    func upsertCell(_ cell: TableCellModel) async {
        guard let userID = AuthService.shared.currentUser?.id.uuidString else { return }
        let row = makeCellRow(cell: cell, userID: userID)

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertTableCell, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("table_cells")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertTableCell, payload: data))
            }
            print("⚠️ TableCell upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Upsert multiple cells at once (for addRow, addColumn, importCSV)

    func upsertCells(_ cells: [TableCellModel]) async {
        for cell in cells {
            await upsertCell(cell)
        }
    }

    // MARK: - Delete Cell

    func deleteCell(_ cell: TableCellModel) async {
        guard let userID = AuthService.shared.currentUser?.id.uuidString else { return }
        let cellID = cell.id.uuidString
        let now    = iso.string(from: Date())

        guard network.isConnected else {
            let payload = CellDeletePayload(id: cellID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteTableCell, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("table_cells")
                .update(CellDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id",      value: cellID)
                .eq("user_id", value: userID)
                .execute()
        } catch {
            let payload = CellDeletePayload(id: cellID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteTableCell, payload: data))
            }
            print("⚠️ TableCell delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull ALL tables + cells for a canvas

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.currentUser?.id.uuidString else { return }

        // Pull tables
        do {
            let rows: [DBTableRow] = try await supabase
                .from("table_elements")
                .select()
                .eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id",   value: userID)
                .execute()
                .value

            let localTables = (try? context.fetch(FetchDescriptor<TableElementModel>())) ?? []
            let localCanvasTables = localTables.filter { $0.canvasID == canvasID }
            let localTableMap = Dictionary(uniqueKeysWithValues: localCanvasTables.map { ($0.id, $0) })

            for row in rows {
                guard let rowID = UUID(uuidString: row.id) else { continue }

                if row.is_deleted {
                    if let local = localTableMap[rowID] {
                        context.delete(local)
                    }
                    continue
                }

                if let local = localTableMap[rowID] {
                    let remoteUpdated = iso.date(from: row.updated_at) ?? .distantPast
                    if remoteUpdated > local.updatedAt {
                        local.x                   = row.x
                        local.y                   = row.y
                        local.rowCount            = row.row_count
                        local.colCount            = row.col_count
                        local.cellWidth           = row.cell_width
                        local.cellHeight          = row.cell_height
                        local.rotation            = row.rotation
                        local.zIndex              = row.z_index
                        local.colHeaderColorName  = row.col_header_color_name
                        local.rowHeaderColorName  = row.row_header_color_name
                        local.showColHeaders      = row.show_col_headers
                        local.showRowHeaders      = row.show_row_headers
                        local.updatedAt           = remoteUpdated
                    }
                } else {
                    let table = TableElementModel(
                        canvasID: canvasID,
                        rows: row.row_count,
                        cols: row.col_count,
                        x: row.x,
                        y: row.y
                    )
                    table.id                  = rowID
                    table.cellWidth           = row.cell_width
                    table.cellHeight          = row.cell_height
                    table.rotation            = row.rotation
                    table.zIndex              = row.z_index
                    table.colHeaderColorName  = row.col_header_color_name
                    table.rowHeaderColorName  = row.row_header_color_name
                    table.showColHeaders      = row.show_col_headers
                    table.showRowHeaders      = row.show_row_headers
                    table.createdAt           = iso.date(from: row.created_at) ?? Date()
                    table.updatedAt           = iso.date(from: row.updated_at) ?? Date()
                    context.insert(table)
                }
            }

            try? context.save()

        } catch {
            print("⚠️ Table pull failed: \(error.localizedDescription)")
        }

        // Pull cells for all tables in this canvas
        let currentTables = (try? context.fetch(FetchDescriptor<TableElementModel>())) ?? []
        let canvasTableIDs = Set(currentTables.filter { $0.canvasID == canvasID }.map { $0.id.uuidString })

        guard !canvasTableIDs.isEmpty else { return }

        do {
            let rows: [DBTableCellRow] = try await supabase
                .from("table_cells")
                .select()
                .eq("user_id", value: userID)
                .in("table_id", values: Array(canvasTableIDs))
                .execute()
                .value

            let localCells = (try? context.fetch(FetchDescriptor<TableCellModel>())) ?? []
            let relevantLocalCells = localCells.filter { canvasTableIDs.contains($0.tableID.uuidString) }
            let localCellMap = Dictionary(uniqueKeysWithValues: relevantLocalCells.map { ($0.id, $0) })

            for row in rows {
                guard let rowID   = UUID(uuidString: row.id) else { continue }
                guard let tableID = UUID(uuidString: row.table_id) else { continue }

                if row.is_deleted {
                    if let local = localCellMap[rowID] {
                        context.delete(local)
                    }
                    continue
                }

                if let local = localCellMap[rowID] {
                    let remoteUpdated = iso.date(from: row.updated_at) ?? .distantPast
                    if remoteUpdated > local.updatedAt {
                        local.value               = row.value
                        local.backgroundColorName = row.background_color_name
                        local.textColorName       = row.text_color_name
                        local.alignmentRaw        = row.alignment_raw
                        local.isBold              = row.is_bold
                        local.isMerged            = row.is_merged
                        local.mergeOriginRow      = row.merge_origin_row
                        local.mergeOriginCol      = row.merge_origin_col
                        local.colSpan             = row.col_span
                        local.rowSpan             = row.row_span
                        local.updatedAt           = remoteUpdated
                    }
                } else {
                    let cell = TableCellModel(tableID: tableID, row: row.row_index, col: row.col_index)
                    cell.id                  = rowID
                    cell.value               = row.value
                    cell.backgroundColorName = row.background_color_name
                    cell.textColorName       = row.text_color_name
                    cell.alignmentRaw        = row.alignment_raw
                    cell.isBold              = row.is_bold
                    cell.isMerged            = row.is_merged
                    cell.mergeOriginRow      = row.merge_origin_row
                    cell.mergeOriginCol      = row.merge_origin_col
                    cell.colSpan             = row.col_span
                    cell.rowSpan             = row.row_span
                    cell.createdAt           = iso.date(from: row.created_at) ?? Date()
                    cell.updatedAt           = iso.date(from: row.updated_at) ?? Date()
                    context.insert(cell)
                }
            }

            try? context.save()

        } catch {
            print("⚠️ TableCell pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Flush offline queue

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertTable:
                if let row = try? JSONDecoder().decode(DBTableRow.self, from: operation.payload) {
                    do {
                        try await supabase
                            .from("table_elements")
                            .upsert(row, onConflict: "id")
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush table upsert failed: \(error.localizedDescription)")
                    }
                }

            case .deleteTable:
                if let payload = try? JSONDecoder().decode(TableDeletePayload.self,
                                                           from: operation.payload) {
                    do {
                        try await supabase
                            .from("table_elements")
                            .update(TableDeleteUpdate(is_deleted: true, updated_at: payload.updated_at))
                            .eq("id",      value: payload.id)
                            .eq("user_id", value: payload.user_id)
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush table delete failed: \(error.localizedDescription)")
                    }
                }

            case .upsertTableCell:
                if let row = try? JSONDecoder().decode(DBTableCellRow.self, from: operation.payload) {
                    do {
                        try await supabase
                            .from("table_cells")
                            .upsert(row, onConflict: "id")
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush table cell upsert failed: \(error.localizedDescription)")
                    }
                }

            case .deleteTableCell:
                if let payload = try? JSONDecoder().decode(CellDeletePayload.self,
                                                           from: operation.payload) {
                    do {
                        try await supabase
                            .from("table_cells")
                            .update(CellDeleteUpdate(is_deleted: true, updated_at: payload.updated_at))
                            .eq("id",      value: payload.id)
                            .eq("user_id", value: payload.user_id)
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush table cell delete failed: \(error.localizedDescription)")
                    }
                }

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    // MARK: - Helpers

    private func makeTableRow(table: TableElementModel, userID: String) -> DBTableRow {
        let now = iso.string(from: Date())
        return DBTableRow(
            id:                    table.id.uuidString,
            canvas_id:             table.canvasID.uuidString,
            user_id:               userID,
            x:                     table.x,
            y:                     table.y,
            row_count:             table.rowCount,
            col_count:             table.colCount,
            cell_width:            table.cellWidth,
            cell_height:           table.cellHeight,
            rotation:              table.rotation,
            z_index:               table.zIndex,
            col_header_color_name: table.colHeaderColorName,
            row_header_color_name: table.rowHeaderColorName,
            show_col_headers:      table.showColHeaders,
            show_row_headers:      table.showRowHeaders,
            created_at:            iso.string(from: table.createdAt),
            updated_at:            now,
            is_deleted:            false
        )
    }

    private func makeCellRow(cell: TableCellModel, userID: String) -> DBTableCellRow {
        let now = iso.string(from: Date())
        return DBTableCellRow(
            id:                    cell.id.uuidString,
            table_id:              cell.tableID.uuidString,
            user_id:               userID,
            row_index:             cell.row,
            col_index:             cell.col,
            value:                 cell.value,
            background_color_name: cell.backgroundColorName,
            text_color_name:       cell.textColorName,
            alignment_raw:         cell.alignmentRaw,
            is_bold:               cell.isBold,
            is_merged:             cell.isMerged,
            merge_origin_row:      cell.mergeOriginRow,
            merge_origin_col:      cell.mergeOriginCol,
            col_span:              cell.colSpan,
            row_span:              cell.rowSpan,
            created_at:            iso.string(from: cell.createdAt),
            updated_at:            now,
            is_deleted:            false
        )
    }
}
