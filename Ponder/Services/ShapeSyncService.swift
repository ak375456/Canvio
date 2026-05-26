//
//  ShapeSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

// MARK: - Row shapes

private struct ShapeRow: Codable {
    let id:                   String
    let canvas_id:            String
    let user_id:              String
    let shape_type_raw:       String
    let x:                    Double
    let y:                    Double
    let width:                Double
    let height:               Double
    let rotation:             Double
    let stroke_color_name:    String
    let fill_color_name:      String
    let has_fill:             Bool
    let stroke_width:         Double
    let has_arrow_head:       Bool
    let triangle_variant_raw: String
    let polygon_sides:        Int
    let z_index:              Int
    let created_at:           String
    let updated_at:           String
    let is_deleted:           Bool
}

private struct ShapeDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct ShapeDeletePayload: Codable {
    let id:         String
    let user_id:    String
    let updated_at: String
}

// MARK: - ShapeSyncService

@MainActor
final class ShapeSyncService {

    static let shared = ShapeSyncService()

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

    func upsert(_ shape: ShapeElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = makeRow(shape: shape, userID: userID)

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertShape, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("shapes")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertShape, payload: data))
            }
            print("⚠️ Shape upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Soft delete

    func delete(_ shape: ShapeElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let shapeID = shape.id.uuidString
        let now     = iso.string(from: Date())

        guard network.isConnected else {
            let payload = ShapeDeletePayload(id: shapeID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteShape, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("shapes")
                .update(ShapeDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id",      value: shapeID)
                .eq("user_id", value: userID)
                .execute()
        } catch {
            let payload = ShapeDeletePayload(id: shapeID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteShape, payload: data))
            }
            print("⚠️ Shape delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull ALL rows (including deleted) → merge into SwiftData

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.syncUserID else { return }

        do {
            let rows: [ShapeRow] = try await supabase
                .from("shapes")
                .select()
                .eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id",   value: userID)
                .execute()
                .value

            let localShapes = (try? context.fetch(FetchDescriptor<ShapeElementModel>())) ?? []
            let localCanvasShapes = localShapes.filter { $0.canvasID == canvasID }
            let localMap = Dictionary(uniqueKeysWithValues: localCanvasShapes.map { ($0.id, $0) })

            for row in rows {
                guard let rowID = UUID(uuidString: row.id) else { continue }

                if row.is_deleted {
                    if let local = localMap[rowID] {
                        context.delete(local)
                    }
                    continue
                }

                if let local = localMap[rowID] {
                    let remoteUpdated = iso.date(from: row.updated_at) ?? .distantPast
                    if remoteUpdated > local.updatedAt {
                        local.shapeTypeRaw       = row.shape_type_raw
                        local.x                  = row.x
                        local.y                  = row.y
                        local.width              = row.width
                        local.height             = row.height
                        local.rotation           = row.rotation
                        local.strokeColorName    = row.stroke_color_name
                        local.fillColorName      = row.fill_color_name
                        local.hasFill            = row.has_fill
                        local.strokeWidth        = row.stroke_width
                        local.hasArrowHead       = row.has_arrow_head
                        local.triangleVariantRaw = row.triangle_variant_raw
                        local.polygonSides       = row.polygon_sides
                        local.zIndex             = row.z_index
                        local.updatedAt          = remoteUpdated
                    }
                } else {
                    let kind = ShapeKind(rawValue: row.shape_type_raw) ?? .rectangle
                    let shape = ShapeElementModel(canvasID: canvasID, kind: kind,
                                                  x: row.x, y: row.y)
                    shape.id                  = rowID
                    shape.width               = row.width
                    shape.height              = row.height
                    shape.rotation            = row.rotation
                    shape.strokeColorName     = row.stroke_color_name
                    shape.fillColorName       = row.fill_color_name
                    shape.hasFill             = row.has_fill
                    shape.strokeWidth         = row.stroke_width
                    shape.hasArrowHead        = row.has_arrow_head
                    shape.triangleVariantRaw  = row.triangle_variant_raw
                    shape.polygonSides        = row.polygon_sides
                    shape.zIndex              = row.z_index
                    shape.createdAt           = iso.date(from: row.created_at) ?? Date()
                    shape.updatedAt           = iso.date(from: row.updated_at) ?? Date()
                    context.insert(shape)
                }
            }

            try? context.save()

        } catch {
            print("⚠️ Shape pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Flush offline queue

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertShape:
                if let row = try? JSONDecoder().decode(ShapeRow.self, from: operation.payload) {
                    do {
                        try await supabase
                            .from("shapes")
                            .upsert(row, onConflict: "id")
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush shape upsert failed: \(error.localizedDescription)")
                    }
                }

            case .deleteShape:
                if let payload = try? JSONDecoder().decode(ShapeDeletePayload.self,
                                                           from: operation.payload) {
                    do {
                        try await supabase
                            .from("shapes")
                            .update(ShapeDeleteUpdate(
                                is_deleted: true,
                                updated_at: payload.updated_at
                            ))
                            .eq("id",      value: payload.id)
                            .eq("user_id", value: payload.user_id)
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush shape delete failed: \(error.localizedDescription)")
                    }
                }

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    // MARK: - Helpers

    private func makeRow(shape: ShapeElementModel, userID: String) -> ShapeRow {
        let now = iso.string(from: Date())
        return ShapeRow(
            id:                   shape.id.uuidString,
            canvas_id:            shape.canvasID.uuidString,
            user_id:              userID,
            shape_type_raw:       shape.shapeTypeRaw,
            x:                    shape.x,
            y:                    shape.y,
            width:                shape.width,
            height:               shape.height,
            rotation:             shape.rotation,
            stroke_color_name:    shape.strokeColorName,
            fill_color_name:      shape.fillColorName,
            has_fill:             shape.hasFill,
            stroke_width:         shape.strokeWidth,
            has_arrow_head:       shape.hasArrowHead,
            triangle_variant_raw: shape.triangleVariantRaw,
            polygon_sides:        shape.polygonSides,
            z_index:              shape.zIndex,
            created_at:           iso.string(from: shape.createdAt),
            updated_at:           now,
            is_deleted:           false
        )
    }
}
