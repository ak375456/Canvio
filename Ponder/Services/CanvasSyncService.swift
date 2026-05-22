//
//  CanvasSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

// MARK: - Row shapes

private struct CanvasRow: Codable {
    let id:              String
    let user_id:         String
    let name:            String
    let icon_name:       String
    let icon_color:      String
    let canvas_size_raw: String
    let custom_width:    Double
    let custom_height:   Double
    let created_at:      String
    let updated_at:      String
    let is_deleted:      Bool
}

private struct DeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct DeletePayload: Codable {
    let id:         String
    let user_id:    String
    let updated_at: String
}

// MARK: - CanvasSyncService

@MainActor
final class CanvasSyncService {

    static let shared = CanvasSyncService()

    private let supabase = SupabaseService.shared.client
    private let queue    = SyncQueue.shared
    private let network  = NetworkMonitor.shared
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    // MARK: - Resolve userID
    // Waits up to 3 seconds for session restore before giving up.

    private func resolveUserID() async -> String? {
        if let id = AuthService.shared.currentUser?.id.uuidString { return id }
        for _ in 0..<6 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            if let id = AuthService.shared.currentUser?.id.uuidString { return id }
        }
        return nil
    }

    // MARK: - Upsert (create / rename)

    func upsert(_ canvas: CanvasModel) async {
        guard let userID = await resolveUserID() else { return }
        let row = makeRow(canvas: canvas, userID: userID)

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertCanvas, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("canvases")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertCanvas, payload: data))
            }
            print("⚠️ Canvas upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Soft delete

    func delete(_ canvas: CanvasModel) async {
        guard let userID = AuthService.shared.currentUser?.id.uuidString else { return }
        let canvasID = canvas.id.uuidString
        let now      = iso.string(from: Date())

        guard network.isConnected else {
            let payload = DeletePayload(id: canvasID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteCanvas, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("canvases")
                .update(DeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id",      value: canvasID)
                .eq("user_id", value: userID)
                .execute()
        } catch {
            let payload = DeletePayload(id: canvasID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteCanvas, payload: data))
            }
            print("⚠️ Canvas delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull ALL rows → merge into SwiftData

    func pullAll(context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.currentUser?.id.uuidString else { return }

        do {
            let rows: [CanvasRow] = try await supabase
                .from("canvases")
                .select()
                .eq("user_id", value: userID)
                .order("created_at", ascending: true)
                .execute()
                .value

            let localCanvases = (try? context.fetch(FetchDescriptor<CanvasModel>())) ?? []
            let localMap = Dictionary(uniqueKeysWithValues: localCanvases.map { ($0.id, $0) })

            for row in rows {
                guard let rowID = UUID(uuidString: row.id) else { continue }

                if row.is_deleted {
                    if let local = localMap[rowID] { context.delete(local) }
                    continue
                }

                if let local = localMap[rowID] {
                    let remoteUpdated = iso.date(from: row.updated_at) ?? .distantPast
                    if remoteUpdated > local.updatedAt {
                        local.name          = row.name
                        local.iconName      = row.icon_name
                        local.iconColor     = row.icon_color
                        local.canvasSizeRaw = row.canvas_size_raw
                        local.customWidth   = row.custom_width
                        local.customHeight  = row.custom_height
                        local.updatedAt     = remoteUpdated
                    }
                } else {
                    let canvas = CanvasModel(
                        name:         row.name,
                        iconName:     row.icon_name,
                        iconColor:    row.icon_color,
                        canvasSize:   CanvasSize(rawValue: row.canvas_size_raw) ?? .infinite,
                        customWidth:  row.custom_width,
                        customHeight: row.custom_height
                    )
                    canvas.id        = rowID
                    canvas.createdAt = iso.date(from: row.created_at) ?? Date()
                    canvas.updatedAt = iso.date(from: row.updated_at) ?? Date()
                    context.insert(canvas)
                }
            }

            try? context.save()

        } catch {
            print("⚠️ Canvas pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Reconcile local → remote
    //
    // Finds any local canvases that are missing from Supabase and pushes them up.
    // This fixes the "first canvas never synced" scenario where upsert fired
    // before the session was restored (currentUser was nil) so the row was
    // silently dropped and never retried.
    //
    // Call this AFTER pullAll so we know what's already in Supabase.

    func reconcileLocalToRemote(context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.currentUser?.id.uuidString else { return }

        // Fetch all remote IDs (non-deleted)
        do {
            struct IDOnly: Codable { let id: String }
            let remoteRows: [IDOnly] = try await supabase
                .from("canvases")
                .select("id")
                .eq("user_id",   value: userID)
                .eq("is_deleted", value: false)
                .execute()
                .value

            let remoteIDs = Set(remoteRows.map { $0.id.lowercased() })

            // Find local canvases not in Supabase
            let localCanvases = (try? context.fetch(FetchDescriptor<CanvasModel>())) ?? []
            let orphans = localCanvases.filter { !remoteIDs.contains($0.id.uuidString.lowercased()) }

            if !orphans.isEmpty {
                print("🔁 Reconciling \(orphans.count) local canvas(es) missing from Supabase")
                for canvas in orphans {
                    let row = makeRow(canvas: canvas, userID: userID)
                    try? await supabase
                        .from("canvases")
                        .upsert(row, onConflict: "id")
                        .execute()
                }
            }
        } catch {
            print("⚠️ Canvas reconcile failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Flush offline queue

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertCanvas:
                if let row = try? JSONDecoder().decode(CanvasRow.self, from: operation.payload) {
                    do {
                        try await supabase
                            .from("canvases")
                            .upsert(row, onConflict: "id")
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush canvas upsert failed: \(error.localizedDescription)")
                    }
                }

            case .deleteCanvas:
                if let payload = try? JSONDecoder().decode(DeletePayload.self,
                                                           from: operation.payload) {
                    do {
                        try await supabase
                            .from("canvases")
                            .update(DeleteUpdate(is_deleted: true, updated_at: payload.updated_at))
                            .eq("id",      value: payload.id)
                            .eq("user_id", value: payload.user_id)
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush canvas delete failed: \(error.localizedDescription)")
                    }
                }

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    // MARK: - Helpers

    private func makeRow(canvas: CanvasModel, userID: String) -> CanvasRow {
        let now = iso.string(from: Date())
        return CanvasRow(
            id:              canvas.id.uuidString,
            user_id:         userID,
            name:            canvas.name,
            icon_name:       canvas.iconName,
            icon_color:      canvas.iconColor,
            canvas_size_raw: canvas.canvasSizeRaw,
            custom_width:    canvas.customWidth,
            custom_height:   canvas.customHeight,
            created_at:      iso.string(from: canvas.createdAt),
            updated_at:      now,
            is_deleted:      false
        )
    }
}
