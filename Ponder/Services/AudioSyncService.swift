//
//  AudioSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

// MARK: - Row shapes

private struct AudioRow: Codable {
    let id:              String
    let canvas_id:       String
    let user_id:         String
    let audio_file_name: String
    let original_name:   String
    let duration:        Double
    let x:               Double
    let y:               Double
    let width:           Double
    let height:          Double
    let rotation:        Double
    let z_index:         Int
    let group_id:        String?
    let created_at:      String
    let updated_at:      String
    let is_deleted:      Bool
}

private struct AudioDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct AudioDeletePayload: Codable {
    let id:              String
    let user_id:         String
    let updated_at:      String
    let audio_file_name: String
}

// MARK: - AudioSyncService

@MainActor
final class AudioSyncService {

    static let shared = AudioSyncService()

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

    // MARK: - Upsert

    func upsert(_ element: AudioElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = makeRow(element: element, userID: userID)

        Task { await media.uploadAudio(fileName: element.audioFileName) }

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertAudio, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("audio_elements")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertAudio, payload: data))
            }
            print("⚠️ Audio upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Soft delete

    func delete(_ element: AudioElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let elementID = element.id.uuidString
        let now       = iso.string(from: Date())

        guard network.isConnected else {
            let payload = AudioDeletePayload(id: elementID, user_id: userID,
                                             updated_at: now, audio_file_name: element.audioFileName)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteAudio, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("audio_elements")
                .update(AudioDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id",      value: elementID)
                .eq("user_id", value: userID)
                .execute()
            Task { await media.deleteAudio(fileName: element.audioFileName) }
        } catch {
            let payload = AudioDeletePayload(id: elementID, user_id: userID,
                                             updated_at: now, audio_file_name: element.audioFileName)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteAudio, payload: data))
            }
            print("⚠️ Audio delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull ALL rows + download missing files (lazy)

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.syncUserID else { return }

        do {
            let rows: [AudioRow] = try await supabase
                .from("audio_elements")
                .select()
                .eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id",   value: userID)
                .execute()
                .value

            let localElements = (try? context.fetch(FetchDescriptor<AudioElementModel>())) ?? []
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
                        local.x         = row.x
                        local.y         = row.y
                        local.width     = row.width
                        local.height    = row.height
                        local.rotation  = row.rotation
                        local.zIndex    = row.z_index
                        local.groupID   = row.group_id.flatMap { UUID(uuidString: $0) }
                        local.updatedAt = remoteUpdated
                    }
                    Task { await media.downloadAudioIfNeeded(fileName: row.audio_file_name) }
                } else {
                    let element = AudioElementModel(
                        canvasID: canvasID,
                        audioFileName: row.audio_file_name,
                        originalName: row.original_name,
                        duration: row.duration,
                        x: row.x, y: row.y
                    )
                    element.id        = rowID
                    element.width     = row.width
                    element.height    = row.height
                    element.rotation  = row.rotation
                    element.zIndex    = row.z_index
                    element.groupID   = row.group_id.flatMap { UUID(uuidString: $0) }
                    element.createdAt = iso.date(from: row.created_at) ?? Date()
                    element.updatedAt = iso.date(from: row.updated_at) ?? Date()
                    context.insert(element)
                    Task { await media.downloadAudioIfNeeded(fileName: row.audio_file_name) }
                }
            }

            try? context.save()

        } catch {
            print("⚠️ Audio pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Flush offline queue

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertAudio:
                if let row = try? JSONDecoder().decode(AudioRow.self, from: operation.payload) {
                    do {
                        try await supabase
                            .from("audio_elements")
                            .upsert(row, onConflict: "id")
                            .execute()
                        Task { await media.uploadAudio(fileName: row.audio_file_name) }
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush audio upsert failed: \(error.localizedDescription)")
                    }
                }

            case .deleteAudio:
                if let payload = try? JSONDecoder().decode(AudioDeletePayload.self, from: operation.payload) {
                    do {
                        try await supabase
                            .from("audio_elements")
                            .update(AudioDeleteUpdate(is_deleted: true, updated_at: payload.updated_at))
                            .eq("id",      value: payload.id)
                            .eq("user_id", value: payload.user_id)
                            .execute()
                        Task { await media.deleteAudio(fileName: payload.audio_file_name) }
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush audio delete failed: \(error.localizedDescription)")
                    }
                }

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    // MARK: - Helpers

    private func makeRow(element: AudioElementModel, userID: String) -> AudioRow {
        let now = iso.string(from: Date())
        return AudioRow(
            id:              element.id.uuidString,
            canvas_id:       element.canvasID.uuidString,
            user_id:         userID,
            audio_file_name: element.audioFileName,
            original_name:   element.originalName,
            duration:        element.duration,
            x:               element.x,
            y:               element.y,
            width:           element.width,
            height:          element.height,
            rotation:        element.rotation,
            z_index:         element.zIndex,
            group_id:        element.groupID?.uuidString,
            created_at:      iso.string(from: element.createdAt),
            updated_at:      now,
            is_deleted:      false
        )
    }
}
