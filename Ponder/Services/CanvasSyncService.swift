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

    private func resolveUserID() async -> String? {
        if let id = AuthService.shared.syncUserID { return id }
        for _ in 0..<6 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let id = AuthService.shared.syncUserID { return id }
        }
        return nil
    }

    // MARK: - Upsert

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
            try await supabase.from("canvases").upsert(row, onConflict: "id").execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertCanvas, payload: data))
            }
            print("⚠️ Canvas upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Soft delete

    func delete(_ canvas: CanvasModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
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
            try await supabase.from("canvases")
                .update(DeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id", value: canvasID).eq("user_id", value: userID).execute()
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
        guard let userID = AuthService.shared.syncUserID else { return }

        do {
            let rows: [CanvasRow] = try await supabase
                .from("canvases").select()
                .eq("user_id", value: userID)
                .order("created_at", ascending: true)
                .execute().value

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

    // MARK: - Reconcile local canvases → remote

    func reconcileLocalToRemote(context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.syncUserID else { return }

        do {
            struct IDOnly: Codable { let id: String }
            let remoteRows: [IDOnly] = try await supabase
                .from("canvases").select("id")
                .eq("user_id",    value: userID)
                .eq("is_deleted", value: false)
                .execute().value

            let remoteIDs      = Set(remoteRows.map { $0.id.lowercased() })
            let localCanvases  = (try? context.fetch(FetchDescriptor<CanvasModel>())) ?? []
            let orphans        = localCanvases.filter {
                !remoteIDs.contains($0.id.uuidString.lowercased())
            }

            if !orphans.isEmpty {
                print("🔁 Reconciling \(orphans.count) local canvas(es) missing from Supabase")
                for canvas in orphans {
                    let row = makeRow(canvas: canvas, userID: userID)
                    try? await supabase.from("canvases").upsert(row, onConflict: "id").execute()
                }
            }
        } catch {
            print("⚠️ Canvas reconcile failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Reconcile ALL local elements → Supabase
    //
    // Called after login or after Pro purchase so that canvases and elements
    // created while the user was a guest (no account / not Pro) are pushed up.
    // Each sync service already has upsert — we just call it for every local record.

    func reconcileAllLocalData(context: ModelContext) async {
        guard network.isConnected else { return }
        guard AuthService.shared.syncUserID != nil else { return }

        print("🔁 reconcileAllLocalData — pushing all local data to Supabase")

        // 1. Canvases
        let canvases = (try? context.fetch(FetchDescriptor<CanvasModel>())) ?? []
        for canvas in canvases {
            await upsert(canvas)
        }

        // Small yield so Supabase has the canvas rows before elements reference them
        try? await Task.sleep(nanoseconds: 500_000_000)

        // 2. All element types for every canvas
        for canvas in canvases {
            let canvasID = canvas.id

            let texts = (try? context.fetch(FetchDescriptor<TextElementModel>()))?.filter {
                $0.canvasID == canvasID
            } ?? []
            for el in texts { await TextSyncService.shared.upsert(el) }

            let stickies = (try? context.fetch(FetchDescriptor<StickyNoteModel>()))?.filter {
                $0.canvasID == canvasID
            } ?? []
            for el in stickies { await StickyNoteSyncService.shared.upsert(el) }

            let shapes = (try? context.fetch(FetchDescriptor<ShapeElementModel>()))?.filter {
                $0.canvasID == canvasID
            } ?? []
            for el in shapes { await ShapeSyncService.shared.upsert(el) }

            let images = (try? context.fetch(FetchDescriptor<ImageElementModel>()))?.filter {
                $0.canvasID == canvasID
            } ?? []
            for el in images { await ImageSyncService.shared.upsert(el) }

            let pdfs = (try? context.fetch(FetchDescriptor<PDFElementModel>()))?.filter {
                $0.canvasID == canvasID
            } ?? []
            for el in pdfs { await PDFSyncService.shared.upsert(el) }

            let todos = (try? context.fetch(FetchDescriptor<TodoListModel>()))?.filter {
                $0.canvasID == canvasID
            } ?? []
            for el in todos { await TodoSyncService.shared.upsertList(el) }

            let tasks = (try? context.fetch(FetchDescriptor<TodoTaskModel>())) ?? []
            let todoIDs = Set(todos.map { $0.id })
            for el in tasks.filter({ todoIDs.contains($0.listID) }) {
                await TodoSyncService.shared.upsertTask(el)
            }

            let tables = (try? context.fetch(FetchDescriptor<TableElementModel>()))?.filter {
                $0.canvasID == canvasID
            } ?? []
            for el in tables { await TableSyncService.shared.upsertTable(el) }

            let cells = (try? context.fetch(FetchDescriptor<TableCellModel>())) ?? []
            let tableIDs = Set(tables.map { $0.id })
            for el in cells.filter({ tableIDs.contains($0.tableID) }) {
                await TableSyncService.shared.upsertCell(el)
            }

            let audio = (try? context.fetch(FetchDescriptor<AudioElementModel>()))?.filter {
                $0.canvasID == canvasID
            } ?? []
            for el in audio { await AudioSyncService.shared.upsert(el) }

            let youtube = (try? context.fetch(FetchDescriptor<YouTubeElementModel>()))?.filter {
                $0.canvasID == canvasID
            } ?? []
            for el in youtube { await YouTubeSyncService.shared.upsert(el) }

            let drawings = (try? context.fetch(FetchDescriptor<DrawingElementModel>()))?.filter {
                $0.canvasID == canvasID
            } ?? []
            for el in drawings { await DrawingSyncService.shared.upsert(el) }

            let connectors = (try? context.fetch(FetchDescriptor<ConnectorModel>()))?.filter {
                $0.canvasID == canvasID
            } ?? []
            for el in connectors { await ConnectorSyncService.shared.upsert(el) }

            let symbols = (try? context.fetch(FetchDescriptor<SymbolElementModel>()))?.filter {
                $0.canvasID == canvasID
            } ?? []
            for el in symbols { await SymbolSyncService.shared.upsert(el) }
        }

        print("✅ reconcileAllLocalData complete")
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
                        try await supabase.from("canvases").upsert(row, onConflict: "id").execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush canvas upsert failed: \(error.localizedDescription)")
                    }
                }

            case .deleteCanvas:
                if let payload = try? JSONDecoder().decode(DeletePayload.self, from: operation.payload) {
                    do {
                        try await supabase.from("canvases")
                            .update(DeleteUpdate(is_deleted: true, updated_at: payload.updated_at))
                            .eq("id", value: payload.id).eq("user_id", value: payload.user_id)
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
