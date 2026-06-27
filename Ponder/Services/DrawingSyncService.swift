//
//  DrawingSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

// MARK: - Row shapes

private struct DrawingRow: Codable {
    let id:                String
    let canvas_id:         String
    let user_id:           String
    let drawing_data:      String   // base64-encoded PKDrawing data
    let x:                 Double
    let y:                 Double
    let width:             Double
    let height:            Double
    let rotation:          Double
    let z_index:           Int
    let group_id:          String?
    let is_canvas_drawing: Bool
    let created_at:        String
    let updated_at:        String
    let is_deleted:        Bool
}

private struct DrawingDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct DrawingDeletePayload: Codable {
    let id:         String
    let user_id:    String
    let updated_at: String
}

// MARK: - DrawingSyncService

@MainActor
final class DrawingSyncService {

    static let shared = DrawingSyncService()

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

    func upsert(_ element: DrawingElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = makeRow(element: element, userID: userID)

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertDrawing, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("drawings")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertDrawing, payload: data))
            }
            print("⚠️ Drawing upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Soft delete

    func delete(_ element: DrawingElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let elementID = element.id.uuidString
        let now       = iso.string(from: Date())

        guard network.isConnected else {
            let payload = DrawingDeletePayload(id: elementID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteDrawing, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("drawings")
                .update(DrawingDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id",      value: elementID)
                .eq("user_id", value: userID)
                .execute()
        } catch {
            let payload = DrawingDeletePayload(id: elementID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteDrawing, payload: data))
            }
            print("⚠️ Drawing delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull ALL rows (including deleted) → merge into SwiftData

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.syncUserID else { return }

        do {
            let rows: [DrawingRow] = try await supabase
                .from("drawings")
                .select()
                .eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id",   value: userID)
                .execute()
                .value

            let localDrawings = (try? context.fetch(FetchDescriptor<DrawingElementModel>())) ?? []
            let localCanvasDrawings = localDrawings.filter { $0.canvasID == canvasID }
            let localMap = Dictionary(uniqueKeysWithValues: localCanvasDrawings.map { ($0.id, $0) })

            for row in rows {
                guard let rowID = UUID(uuidString: row.id) else { continue }

                if row.is_deleted {
                    if let local = localMap[rowID] {
                        context.delete(local)
                    }
                    continue
                }

                // Decode base64 drawing data
                let drawingData = Data(base64Encoded: row.drawing_data) ?? Data()

                if let local = localMap[rowID] {
                    let remoteUpdated = iso.date(from: row.updated_at) ?? .distantPast
                    if remoteUpdated > local.updatedAt {
                        local.drawingData      = drawingData
                        local.x                = row.x
                        local.y                = row.y
                        local.width            = row.width
                        local.height           = row.height
                        local.rotation         = row.rotation
                        local.zIndex           = row.z_index
                        local.groupID          = row.group_id.flatMap { UUID(uuidString: $0) }
                        local.isCanvasDrawing  = row.is_canvas_drawing
                        local.updatedAt        = remoteUpdated
                    }
                } else {
                    let element = DrawingElementModel(
                        canvasID:        canvasID,
                        x:               row.x,
                        y:               row.y,
                        width:           row.width,
                        height:          row.height,
                        isCanvasDrawing: row.is_canvas_drawing
                    )
                    element.id          = rowID
                    element.drawingData = drawingData
                    element.rotation    = row.rotation
                    element.zIndex      = row.z_index
                    element.groupID     = row.group_id.flatMap { UUID(uuidString: $0) }
                    element.createdAt   = iso.date(from: row.created_at) ?? Date()
                    element.updatedAt   = iso.date(from: row.updated_at) ?? Date()
                    context.insert(element)
                }
            }

            try? context.save()

        } catch {
            print("⚠️ Drawing pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Flush offline queue

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertDrawing:
                succeeded = await SyncStalenessGuard.flushUpsert(
                    operation,
                    as: DrawingRow.self,
                    table: "drawings",
                    supabase: supabase,
                    label: "drawing"
                )

            case .deleteDrawing:
                succeeded = await SyncStalenessGuard.flushSoftDelete(
                    operation,
                    table: "drawings",
                    supabase: supabase,
                    label: "drawing"
                )

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    // MARK: - Helpers

    private func makeRow(element: DrawingElementModel, userID: String) -> DrawingRow {
        // Encode PKDrawing data as base64 for safe JSON transport
        let base64 = element.drawingData.base64EncodedString()
        return DrawingRow(
            id:                element.id.uuidString,
            canvas_id:         element.canvasID.uuidString,
            user_id:           userID,
            drawing_data:      base64,
            x:                 element.x,
            y:                 element.y,
            width:             element.width,
            height:            element.height,
            rotation:          element.rotation,
            z_index:           element.zIndex,
            group_id:          element.groupID?.uuidString,
            is_canvas_drawing: element.isCanvasDrawing,
            created_at:        iso.string(from: element.createdAt),
            updated_at:        iso.string(from: element.updatedAt),
            is_deleted:        false
        )
    }
}
