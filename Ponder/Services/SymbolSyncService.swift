//
//  SymbolSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

// MARK: - Row type

private struct SymbolRow: Codable {
    let id:          String
    let canvas_id:   String
    let user_id:     String
    let symbol_name: String
    let color_name:  String
    let font_size:   Double
    let x:           Double
    let y:           Double
    let z_index:     Int
    let group_id:    String?
    let created_at:  String
    let updated_at:  String
    let is_deleted:  Bool
}

private struct SymbolDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct SymbolDeletePayload: Codable {
    let id:         String
    let user_id:    String
    let updated_at: String
}

// MARK: - SymbolSyncService

@MainActor
final class SymbolSyncService {

    static let shared = SymbolSyncService()

    private let supabase = SupabaseService.shared.client
    private let queue    = SyncQueue.shared
    private let network  = NetworkMonitor.shared
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    // MARK: - Upsert

    func upsert(_ element: SymbolElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = makeRow(element: element, userID: userID)

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertSymbol, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("symbol_elements")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertSymbol, payload: data))
            }
            print("⚠️ Symbol upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Soft delete

    func delete(_ element: SymbolElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let elementID = element.id.uuidString
        let now       = iso.string(from: Date())

        guard network.isConnected else {
            let payload = SymbolDeletePayload(id: elementID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteSymbol, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("symbol_elements")
                .update(SymbolDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id",      value: elementID)
                .eq("user_id", value: userID)
                .execute()
        } catch {
            let payload = SymbolDeletePayload(id: elementID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteSymbol, payload: data))
            }
            print("⚠️ Symbol delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull all → merge into SwiftData

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.syncUserID else { return }

        do {
            let rows: [SymbolRow] = try await supabase
                .from("symbol_elements")
                .select()
                .eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id",   value: userID)
                .execute()
                .value

            let local    = (try? context.fetch(FetchDescriptor<SymbolElementModel>())) ?? []
            let localMap = Dictionary(uniqueKeysWithValues:
                local.filter { $0.canvasID == canvasID }.map { ($0.id, $0) }
            )

            for row in rows {
                guard let rowID = UUID(uuidString: row.id) else { continue }

                if row.is_deleted {
                    if let l = localMap[rowID] { context.delete(l) }
                    continue
                }

                if let l = localMap[rowID] {
                    let remoteUpdated = iso.date(from: row.updated_at) ?? .distantPast
                    if remoteUpdated > l.updatedAt {
                        l.symbolName = row.symbol_name
                        l.colorName  = row.color_name
                        l.fontSize   = row.font_size
                        l.x          = row.x
                        l.y          = row.y
                        l.zIndex     = row.z_index
                        l.groupID    = row.group_id.flatMap { UUID(uuidString: $0) }
                        l.updatedAt  = remoteUpdated
                    }
                } else {
                    let el = SymbolElementModel(
                        canvasID:   canvasID,
                        symbolName: row.symbol_name,
                        colorName:  row.color_name,
                        fontSize:   row.font_size,
                        x: row.x, y: row.y
                    )
                    el.id        = rowID
                    el.zIndex    = row.z_index
                    el.groupID   = row.group_id.flatMap { UUID(uuidString: $0) }
                    el.createdAt = iso.date(from: row.created_at) ?? Date()
                    el.updatedAt = iso.date(from: row.updated_at) ?? Date()
                    context.insert(el)
                }
            }

            try? context.save()

        } catch {
            print("⚠️ Symbol pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Flush offline queue

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertSymbol:
                succeeded = await SyncStalenessGuard.flushUpsert(
                    operation,
                    as: SymbolRow.self,
                    table: "symbol_elements",
                    supabase: supabase,
                    label: "symbol"
                )

            case .deleteSymbol:
                succeeded = await SyncStalenessGuard.flushSoftDelete(
                    operation,
                    table: "symbol_elements",
                    supabase: supabase,
                    label: "symbol"
                )

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    // MARK: - Helpers

    private func makeRow(element: SymbolElementModel, userID: String) -> SymbolRow {
        return SymbolRow(
            id:          element.id.uuidString,
            canvas_id:   element.canvasID.uuidString,
            user_id:     userID,
            symbol_name: element.symbolName,
            color_name:  element.colorName,
            font_size:   element.fontSize,
            x:           element.x,
            y:           element.y,
            z_index:     element.zIndex,
            group_id:    element.groupID?.uuidString,
            created_at:  iso.string(from: element.createdAt),
            updated_at:  iso.string(from: element.updatedAt),
            is_deleted:  false
        )
    }
}
