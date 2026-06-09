//
//  StickyNoteSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

// MARK: - Row shapes

private struct StickyNoteRow: Codable {
    let id:             String
    let canvas_id:      String
    let user_id:        String
    let text:           String
    let x:              Double
    let y:              Double
    let width:          Double
    let height:         Double
    let rotation:       Double
    let font_size:      Double
    let is_bold:        Bool
    let is_italic:      Bool
    let font_name:      String
    let color_name:     String
    let list_style_raw: String
    let z_index:        Int
    let group_id:       String?
    let created_at:     String
    let updated_at:     String
    let is_deleted:     Bool
}

private struct StickyDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct StickyDeletePayload: Codable {
    let id:         String
    let user_id:    String
    let updated_at: String
}

// MARK: - StickyNoteSyncService

@MainActor
final class StickyNoteSyncService {

    static let shared = StickyNoteSyncService()

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

    func upsert(_ note: StickyNoteModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = makeRow(note: note, userID: userID)

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertSticky, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("sticky_notes")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertSticky, payload: data))
            }
            print("⚠️ Sticky upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Soft delete

    func delete(_ note: StickyNoteModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let noteID = note.id.uuidString
        let now    = iso.string(from: Date())

        guard network.isConnected else {
            let payload = StickyDeletePayload(id: noteID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteSticky, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("sticky_notes")
                .update(StickyDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id",      value: noteID)
                .eq("user_id", value: userID)
                .execute()
        } catch {
            let payload = StickyDeletePayload(id: noteID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteSticky, payload: data))
            }
            print("⚠️ Sticky delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull ALL rows (including deleted) → merge into SwiftData

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.syncUserID else { return }

        do {
            let rows: [StickyNoteRow] = try await supabase
                .from("sticky_notes")
                .select()
                .eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id",   value: userID)
                .execute()
                .value

            let localNotes = (try? context.fetch(FetchDescriptor<StickyNoteModel>())) ?? []
            let localCanvasNotes = localNotes.filter { $0.canvasID == canvasID }
            let localMap = Dictionary(uniqueKeysWithValues: localCanvasNotes.map { ($0.id, $0) })

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
                        local.text         = row.text
                        local.x            = row.x
                        local.y            = row.y
                        local.width        = row.width
                        local.height       = row.height
                        local.rotation     = row.rotation
                        local.fontSize     = row.font_size
                        local.isBold       = row.is_bold
                        local.isItalic     = row.is_italic
                        local.fontName     = row.font_name
                        local.colorName    = row.color_name
                        local.listStyleRaw = row.list_style_raw
                        local.zIndex       = row.z_index
                        local.groupID      = row.group_id.flatMap { UUID(uuidString: $0) }
                        local.updatedAt    = remoteUpdated
                    }
                } else {
                    let note = StickyNoteModel(canvasID: canvasID, x: row.x, y: row.y)
                    note.id           = rowID
                    note.text         = row.text
                    note.width        = row.width
                    note.height       = row.height
                    note.rotation     = row.rotation
                    note.fontSize     = row.font_size
                    note.isBold       = row.is_bold
                    note.isItalic     = row.is_italic
                    note.fontName     = row.font_name
                    note.colorName    = row.color_name
                    note.listStyleRaw = row.list_style_raw
                    note.zIndex       = row.z_index
                    note.groupID      = row.group_id.flatMap { UUID(uuidString: $0) }
                    note.updatedAt    = iso.date(from: row.updated_at) ?? Date()
                    context.insert(note)
                }
            }

            try? context.save()

        } catch {
            print("⚠️ Sticky pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Flush offline queue

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertSticky:
                if let row = try? JSONDecoder().decode(StickyNoteRow.self, from: operation.payload) {
                    do {
                        try await supabase
                            .from("sticky_notes")
                            .upsert(row, onConflict: "id")
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush sticky upsert failed: \(error.localizedDescription)")
                    }
                }

            case .deleteSticky:
                if let payload = try? JSONDecoder().decode(StickyDeletePayload.self,
                                                           from: operation.payload) {
                    do {
                        try await supabase
                            .from("sticky_notes")
                            .update(StickyDeleteUpdate(
                                is_deleted: true,
                                updated_at: payload.updated_at
                            ))
                            .eq("id",      value: payload.id)
                            .eq("user_id", value: payload.user_id)
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush sticky delete failed: \(error.localizedDescription)")
                    }
                }

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    // MARK: - Helpers

    private func makeRow(note: StickyNoteModel, userID: String) -> StickyNoteRow {
        let now = iso.string(from: Date())
        return StickyNoteRow(
            id:             note.id.uuidString,
            canvas_id:      note.canvasID.uuidString,
            user_id:        userID,
            text:           note.text,
            x:              note.x,
            y:              note.y,
            width:          note.width,
            height:         note.height,
            rotation:       note.rotation,
            font_size:      note.fontSize,
            is_bold:        note.isBold,
            is_italic:      note.isItalic,
            font_name:      note.fontName,
            color_name:     note.colorName,
            list_style_raw: note.listStyleRaw,
            z_index:        note.zIndex,
            group_id:       note.groupID?.uuidString,
            created_at:     iso.string(from: note.updatedAt),
            updated_at:     now,
            is_deleted:     false
        )
    }
}
