//
//  TextSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

// MARK: - Row shapes

private struct TextElementRow: Codable {
    let id:                String
    let canvas_id:         String
    let user_id:           String
    let text:              String
    let x:                 Double
    let y:                 Double
    let font_size:         Double
    let is_bold:           Bool
    let is_italic:         Bool
    let is_underline:      Bool
    let color_name:        String
    let font_name:         String
    let alignment_raw:     String
    let z_index:           Int
    let created_at:        String
    let updated_at:        String
    let is_deleted:        Bool
    let bg_color_name:     String
    let stroke_color_name: String
    let stroke_width:      Double
}

private struct TextDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct TextDeletePayload: Codable {
    let id:         String
    let user_id:    String
    let updated_at: String
}

// MARK: - TextSyncService

@MainActor
final class TextSyncService {

    static let shared = TextSyncService()

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

    func upsert(_ element: TextElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = makeRow(element: element, userID: userID)

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertText, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("text_elements")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertText, payload: data))
            }
            print("⚠️ Text upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Soft delete

    func delete(_ element: TextElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let elementID = element.id.uuidString
        let now       = iso.string(from: Date())

        guard network.isConnected else {
            let payload = TextDeletePayload(id: elementID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteText, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("text_elements")
                .update(TextDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id",      value: elementID)
                .eq("user_id", value: userID)
                .execute()
        } catch {
            let payload = TextDeletePayload(id: elementID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteText, payload: data))
            }
            print("⚠️ Text delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull ALL rows → merge into SwiftData

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.syncUserID else { return }

        do {
            let rows: [TextElementRow] = try await supabase
                .from("text_elements")
                .select()
                .eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id",   value: userID)
                .execute()
                .value

            let localElements       = (try? context.fetch(FetchDescriptor<TextElementModel>())) ?? []
            let localCanvasElements = localElements.filter { $0.canvasID == canvasID }
            let localMap            = Dictionary(uniqueKeysWithValues: localCanvasElements.map { ($0.id, $0) })

            for row in rows {
                guard let rowID = UUID(uuidString: row.id) else { continue }

                if row.is_deleted {
                    if let local = localMap[rowID] { context.delete(local) }
                    continue
                }

                if let local = localMap[rowID] {
                    let remoteUpdated = iso.date(from: row.updated_at) ?? .distantPast
                    if remoteUpdated > local.updatedAt {
                        local.text            = row.text
                        local.x               = row.x
                        local.y               = row.y
                        local.fontSize        = row.font_size
                        local.isBold          = row.is_bold
                        local.isItalic        = row.is_italic
                        local.isUnderline     = row.is_underline
                        local.colorName       = row.color_name
                        local.fontName        = row.font_name
                        local.alignmentRaw    = row.alignment_raw
                        local.zIndex          = row.z_index
                        local.bgColorName     = row.bg_color_name
                        local.strokeColorName = row.stroke_color_name
                        local.strokeWidth     = row.stroke_width
                        local.updatedAt       = remoteUpdated
                    }
                } else {
                    let el = TextElementModel(canvasID: canvasID, text: row.text,
                                              x: row.x, y: row.y)
                    el.id             = rowID
                    el.fontSize       = row.font_size
                    el.isBold         = row.is_bold
                    el.isItalic       = row.is_italic
                    el.isUnderline    = row.is_underline
                    el.colorName      = row.color_name
                    el.fontName       = row.font_name
                    el.alignmentRaw   = row.alignment_raw
                    el.zIndex         = row.z_index
                    el.bgColorName    = row.bg_color_name
                    el.strokeColorName = row.stroke_color_name
                    el.strokeWidth    = row.stroke_width
                    el.updatedAt      = iso.date(from: row.updated_at) ?? Date()
                    context.insert(el)
                }
            }

            try? context.save()

        } catch {
            print("⚠️ Text pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Flush offline queue

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertText:
                if let row = try? JSONDecoder().decode(TextElementRow.self,
                                                       from: operation.payload) {
                    do {
                        try await supabase
                            .from("text_elements")
                            .upsert(row, onConflict: "id")
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush text upsert failed: \(error.localizedDescription)")
                    }
                }

            case .deleteText:
                if let payload = try? JSONDecoder().decode(TextDeletePayload.self,
                                                           from: operation.payload) {
                    do {
                        try await supabase
                            .from("text_elements")
                            .update(TextDeleteUpdate(is_deleted: true,
                                                     updated_at: payload.updated_at))
                            .eq("id",      value: payload.id)
                            .eq("user_id", value: payload.user_id)
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush text delete failed: \(error.localizedDescription)")
                    }
                }

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    // MARK: - Helpers

    private func makeRow(element: TextElementModel, userID: String) -> TextElementRow {
        let now = iso.string(from: Date())
        return TextElementRow(
            id:                element.id.uuidString,
            canvas_id:         element.canvasID.uuidString,
            user_id:           userID,
            text:              element.text,
            x:                 element.x,
            y:                 element.y,
            font_size:         element.fontSize,
            is_bold:           element.isBold,
            is_italic:         element.isItalic,
            is_underline:      element.isUnderline,
            color_name:        element.colorName,
            font_name:         element.fontName,
            alignment_raw:     element.alignmentRaw,
            z_index:           element.zIndex,
            created_at:        iso.string(from: element.updatedAt),
            updated_at:        now,
            is_deleted:        false,
            bg_color_name:     element.bgColorName,
            stroke_color_name: element.strokeColorName,
            stroke_width:      element.strokeWidth
        )
    }
}
