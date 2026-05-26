//
//  ImageSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

// MARK: - Row shapes

private struct ImageRow: Codable {
    let id:            String
    let canvas_id:     String
    let user_id:       String
    let image_file_name: String
    let x:             Double
    let y:             Double
    let width:         Double
    let height:        Double
    let rotation:      Double
    let corner_radius: Double
    let opacity:       Double
    let z_index:       Int
    let created_at:    String
    let updated_at:    String
    let is_deleted:    Bool
}

private struct ImageDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct ImageDeletePayload: Codable {
    let id:              String
    let user_id:         String
    let updated_at:      String
    let image_file_name: String
}

// MARK: - ImageSyncService

@MainActor
final class ImageSyncService {

    static let shared = ImageSyncService()

    private let supabase = SupabaseService.shared.client
    private let queue    = SyncQueue.shared
    private let network  = NetworkMonitor.shared
    private let media    = MediaSyncService.shared
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    // MARK: - Upsert (metadata + upload file)

    func upsert(_ element: ImageElementModel, uploadFile: Bool = false) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = makeRow(element: element, userID: userID)

        if uploadFile {
            let fileName = element.imageFileName
            Task(priority: .utility) { await media.uploadImage(fileName: fileName) }
        }

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertImage, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("image_elements")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertImage, payload: data))
            }
            print("⚠️ Image upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Soft delete

    func delete(_ element: ImageElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let elementID = element.id.uuidString
        let now       = iso.string(from: Date())

        guard network.isConnected else {
            let payload = ImageDeletePayload(id: elementID, user_id: userID,
                                             updated_at: now, image_file_name: element.imageFileName)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteImage, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("image_elements")
                .update(ImageDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id",      value: elementID)
                .eq("user_id", value: userID)
                .execute()
            // Delete file from Storage too
            Task { await media.deleteImage(fileName: element.imageFileName) }
        } catch {
            let payload = ImageDeletePayload(id: elementID, user_id: userID,
                                             updated_at: now, image_file_name: element.imageFileName)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteImage, payload: data))
            }
            print("⚠️ Image delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull ALL rows + download missing files (lazy)

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.syncUserID else { return }

        do {
            let rows: [ImageRow] = try await supabase
                .from("image_elements")
                .select()
                .eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id",   value: userID)
                .execute()
                .value

            let localElements = (try? context.fetch(FetchDescriptor<ImageElementModel>())) ?? []
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

                if let local = localMap[rowID] {
                    let remoteUpdated = iso.date(from: row.updated_at) ?? .distantPast
                    if remoteUpdated > local.updatedAt {
                        local.x            = row.x
                        local.y            = row.y
                        local.width        = row.width
                        local.height       = row.height
                        local.rotation     = row.rotation
                        local.cornerRadius = row.corner_radius
                        local.opacity      = row.opacity
                        local.zIndex       = row.z_index
                        local.updatedAt    = remoteUpdated
                    }
                    // Always ensure file exists locally (lazy download)
                    Task { await media.downloadImageIfNeeded(fileName: row.image_file_name) }
                } else {
                    // New element from another device
                    let element = ImageElementModel(
                        canvasID: canvasID,
                        imageFileName: row.image_file_name,
                        x: row.x, y: row.y,
                        width: row.width, height: row.height
                    )
                    element.id           = rowID
                    element.rotation     = row.rotation
                    element.cornerRadius = row.corner_radius
                    element.opacity      = row.opacity
                    element.zIndex       = row.z_index
                    element.createdAt    = iso.date(from: row.created_at) ?? Date()
                    element.updatedAt    = iso.date(from: row.updated_at) ?? Date()
                    context.insert(element)
                    // Download file lazily
                    Task { await media.downloadImageIfNeeded(fileName: row.image_file_name) }
                }
            }

            try? context.save()

        } catch {
            print("⚠️ Image pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Flush offline queue

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertImage:
                if let row = try? JSONDecoder().decode(ImageRow.self, from: operation.payload) {
                    do {
                        try await supabase
                            .from("image_elements")
                            .upsert(row, onConflict: "id")
                            .execute()
                        // Also retry file upload
                        Task { await media.uploadImage(fileName: row.image_file_name) }
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush image upsert failed: \(error.localizedDescription)")
                    }
                }

            case .deleteImage:
                if let payload = try? JSONDecoder().decode(ImageDeletePayload.self, from: operation.payload) {
                    do {
                        try await supabase
                            .from("image_elements")
                            .update(ImageDeleteUpdate(is_deleted: true, updated_at: payload.updated_at))
                            .eq("id",      value: payload.id)
                            .eq("user_id", value: payload.user_id)
                            .execute()
                        Task { await media.deleteImage(fileName: payload.image_file_name) }
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush image delete failed: \(error.localizedDescription)")
                    }
                }

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    // MARK: - Helpers

    private func makeRow(element: ImageElementModel, userID: String) -> ImageRow {
        let now = iso.string(from: Date())
        return ImageRow(
            id:               element.id.uuidString,
            canvas_id:        element.canvasID.uuidString,
            user_id:          userID,
            image_file_name:  element.imageFileName,
            x:                element.x,
            y:                element.y,
            width:            element.width,
            height:           element.height,
            rotation:         element.rotation,
            corner_radius:    element.cornerRadius,
            opacity:          element.opacity,
            z_index:          element.zIndex,
            created_at:       iso.string(from: element.createdAt),
            updated_at:       now,
            is_deleted:       false
        )
    }
}
