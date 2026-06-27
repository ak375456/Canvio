//
//  YouTubeSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

private struct YouTubeRow: Codable {
    let id: String
    let canvas_id: String
    let user_id: String
    let video_id: String
    let original_url: String
    let title: String
    let thumbnail_url: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let z_index: Int
    let group_id: String?
    let created_at: String
    let updated_at: String
    let is_deleted: Bool
}

private struct YouTubeDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct YouTubeDeletePayload: Codable {
    let id: String
    let user_id: String
    let updated_at: String
}

@MainActor
final class YouTubeSyncService {
    static let shared = YouTubeSyncService()

    private let supabase = SupabaseService.shared.client
    private let queue = SyncQueue.shared
    private let network = NetworkMonitor.shared
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    func upsert(_ element: YouTubeElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = makeRow(element: element, userID: userID)

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertYouTube, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("youtube_elements")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertYouTube, payload: data))
            }
            print("⚠️ YouTube upsert failed: \(error.localizedDescription)")
        }
    }

    func delete(_ element: YouTubeElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let elementID = element.id.uuidString
        let now = iso.string(from: Date())

        guard network.isConnected else {
            let payload = YouTubeDeletePayload(id: elementID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteYouTube, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("youtube_elements")
                .update(YouTubeDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id", value: elementID)
                .eq("user_id", value: userID)
                .execute()
        } catch {
            let payload = YouTubeDeletePayload(id: elementID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteYouTube, payload: data))
            }
            print("⚠️ YouTube delete failed: \(error.localizedDescription)")
        }
    }

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.syncUserID else { return }

        do {
            let rows: [YouTubeRow] = try await supabase
                .from("youtube_elements")
                .select()
                .eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id", value: userID)
                .execute()
                .value

            let localElements = (try? context.fetch(FetchDescriptor<YouTubeElementModel>())) ?? []
            let localCanvasElements = localElements.filter { $0.canvasID == canvasID }
            let localMap = Dictionary(uniqueKeysWithValues: localCanvasElements.map { ($0.id, $0) })

            for row in rows {
                guard let rowID = UUID(uuidString: row.id) else { continue }

                if row.is_deleted {
                    if let local = localMap[rowID] {
                        context.delete(local)
                    }
                    continue
                }

                let remoteUpdated = iso.date(from: row.updated_at) ?? .distantPast

                if let local = localMap[rowID] {
                    if remoteUpdated > local.updatedAt {
                        local.videoID = row.video_id
                        local.originalURL = row.original_url
                        local.title = row.title
                        local.thumbnailURL = row.thumbnail_url
                        local.x = row.x
                        local.y = row.y
                        local.width = row.width
                        local.height = row.height
                        local.zIndex = row.z_index
                        local.groupID = row.group_id.flatMap { UUID(uuidString: $0) }
                        local.updatedAt = remoteUpdated
                    }
                } else {
                    let element = YouTubeElementModel(
                        canvasID: canvasID,
                        videoID: row.video_id,
                        originalURL: row.original_url,
                        title: row.title,
                        thumbnailURL: row.thumbnail_url,
                        x: row.x,
                        y: row.y,
                        width: row.width,
                        height: row.height
                    )
                    element.id = rowID
                    element.zIndex = row.z_index
                    element.groupID = row.group_id.flatMap { UUID(uuidString: $0) }
                    element.createdAt = iso.date(from: row.created_at) ?? Date()
                    element.updatedAt = remoteUpdated
                    context.insert(element)
                }
            }

            try? context.save()
        } catch {
            print("⚠️ YouTube pull failed: \(error.localizedDescription)")
        }
    }

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertYouTube:
                succeeded = await SyncStalenessGuard.flushUpsert(
                    operation,
                    as: YouTubeRow.self,
                    table: "youtube_elements",
                    supabase: supabase,
                    label: "YouTube"
                )

            case .deleteYouTube:
                succeeded = await SyncStalenessGuard.flushSoftDelete(
                    operation,
                    table: "youtube_elements",
                    supabase: supabase,
                    label: "YouTube"
                )

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    private func makeRow(element: YouTubeElementModel, userID: String) -> YouTubeRow {
        return YouTubeRow(
            id: element.id.uuidString,
            canvas_id: element.canvasID.uuidString,
            user_id: userID,
            video_id: element.videoID,
            original_url: element.originalURL,
            title: element.title,
            thumbnail_url: element.thumbnailURL,
            x: element.x,
            y: element.y,
            width: element.width,
            height: element.height,
            z_index: element.zIndex,
            group_id: element.groupID?.uuidString,
            created_at: iso.string(from: element.createdAt),
            updated_at: iso.string(from: element.updatedAt),
            is_deleted: false
        )
    }
}
