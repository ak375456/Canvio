//
//  CanvasPageSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

private struct CanvasPageRow: Codable {
    let id: String
    let canvas_id: String
    let content_canvas_id: String?
    let user_id: String
    let name: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let order_index: Int
    let created_at: String
    let updated_at: String
    let is_deleted: Bool
}

private struct CanvasPageDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct CanvasPageDeletePayload: Codable {
    let id: String
    let user_id: String
    let updated_at: String
}

@MainActor
final class CanvasPageSyncService {
    static let shared = CanvasPageSyncService()

    private let supabase = SupabaseService.shared.client
    private let queue = SyncQueue.shared
    private let network = NetworkMonitor.shared
    private let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    func upsert(_ page: CanvasPageModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = makeRow(page: page, userID: userID)

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertCanvasPage, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("canvas_pages")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertCanvasPage, payload: data))
            }
            print("⚠️ Canvas page upsert failed: \(error.localizedDescription)")
        }
    }

    func delete(_ page: CanvasPageModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let pageID = page.id.uuidString
        let now = iso.string(from: Date())

        guard network.isConnected else {
            let payload = CanvasPageDeletePayload(id: pageID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteCanvasPage, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("canvas_pages")
                .update(CanvasPageDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id", value: pageID)
                .eq("user_id", value: userID)
                .execute()
        } catch {
            let payload = CanvasPageDeletePayload(id: pageID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteCanvasPage, payload: data))
            }
            print("⚠️ Canvas page delete failed: \(error.localizedDescription)")
        }
    }

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.syncUserID else { return }

        do {
            let rows: [CanvasPageRow] = try await supabase
                .from("canvas_pages")
                .select()
                .eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id", value: userID)
                .order("order_index", ascending: true)
                .execute()
                .value

            let localPages = (try? context.fetch(FetchDescriptor<CanvasPageModel>())) ?? []
            let localMap = Dictionary(uniqueKeysWithValues:
                localPages.filter { $0.canvasID == canvasID }.map { ($0.id, $0) }
            )

            for row in rows {
                guard let rowID = UUID(uuidString: row.id) else { continue }

                if row.is_deleted {
                    if let localPage = localMap[rowID] {
                        context.delete(localPage)
                    }
                    continue
                }

                let remoteUpdated = iso.date(from: row.updated_at) ?? .distantPast
                let contentCanvasID = UUID(uuidString: row.content_canvas_id ?? "") ?? canvasID

                if let localPage = localMap[rowID] {
                    if remoteUpdated > localPage.updatedAt {
                        localPage.contentCanvasID = contentCanvasID
                        localPage.name = row.name
                        localPage.x = row.x
                        localPage.y = row.y
                        localPage.width = row.width
                        localPage.height = row.height
                        localPage.orderIndex = row.order_index
                        localPage.updatedAt = remoteUpdated
                    }
                } else {
                    let page = CanvasPageModel(
                        canvasID: canvasID,
                        contentCanvasID: contentCanvasID,
                        name: row.name,
                        x: row.x,
                        y: row.y,
                        width: row.width,
                        height: row.height,
                        orderIndex: row.order_index
                    )
                    page.id = rowID
                    page.createdAt = iso.date(from: row.created_at) ?? Date()
                    page.updatedAt = remoteUpdated
                    context.insert(page)
                }
            }

            try? context.save()
        } catch {
            print("⚠️ Canvas page pull failed: \(error.localizedDescription)")
        }
    }

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertCanvasPage:
                if let row = try? JSONDecoder().decode(CanvasPageRow.self, from: operation.payload) {
                    do {
                        try await supabase
                            .from("canvas_pages")
                            .upsert(row, onConflict: "id")
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush canvas page upsert failed: \(error.localizedDescription)")
                    }
                }

            case .deleteCanvasPage:
                if let payload = try? JSONDecoder().decode(CanvasPageDeletePayload.self,
                                                           from: operation.payload) {
                    do {
                        try await supabase
                            .from("canvas_pages")
                            .update(CanvasPageDeleteUpdate(
                                is_deleted: true,
                                updated_at: payload.updated_at
                            ))
                            .eq("id", value: payload.id)
                            .eq("user_id", value: payload.user_id)
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush canvas page delete failed: \(error.localizedDescription)")
                    }
                }

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    private func makeRow(page: CanvasPageModel, userID: String) -> CanvasPageRow {
        let now = iso.string(from: Date())
        return CanvasPageRow(
            id: page.id.uuidString,
            canvas_id: page.canvasID.uuidString,
            content_canvas_id: page.resolvedContentCanvasID.uuidString,
            user_id: userID,
            name: page.name,
            x: page.x,
            y: page.y,
            width: page.width,
            height: page.height,
            order_index: page.orderIndex,
            created_at: iso.string(from: page.createdAt),
            updated_at: now,
            is_deleted: false
        )
    }
}
