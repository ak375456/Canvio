//
//  ElementGroupSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

private struct ElementGroupRow: Codable {
    let id: String
    let canvas_id: String
    let user_id: String
    let name: String
    let created_at: String
    let updated_at: String
    let is_deleted: Bool
}

private struct ElementGroupDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct ElementGroupDeletePayload: Codable {
    let id: String
    let user_id: String
    let updated_at: String
}

@MainActor
final class ElementGroupSyncService {
    static let shared = ElementGroupSyncService()

    private let supabase = SupabaseService.shared.client
    private let queue = SyncQueue.shared
    private let network = NetworkMonitor.shared
    private let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    func upsert(_ group: CanvasElementGroupModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = makeRow(group: group, userID: userID)

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertElementGroup, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("element_groups")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertElementGroup, payload: data))
            }
            print("⚠️ Element group upsert failed: \(error.localizedDescription)")
        }
    }

    func delete(_ group: CanvasElementGroupModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let groupID = group.id.uuidString
        let now = iso.string(from: Date())

        guard network.isConnected else {
            let payload = ElementGroupDeletePayload(id: groupID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteElementGroup, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("element_groups")
                .update(ElementGroupDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id", value: groupID)
                .eq("user_id", value: userID)
                .execute()
        } catch {
            let payload = ElementGroupDeletePayload(id: groupID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteElementGroup, payload: data))
            }
            print("⚠️ Element group delete failed: \(error.localizedDescription)")
        }
    }

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.syncUserID else { return }

        do {
            let rows: [ElementGroupRow] = try await supabase
                .from("element_groups")
                .select()
                .eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id", value: userID)
                .execute()
                .value

            let local = (try? context.fetch(FetchDescriptor<CanvasElementGroupModel>())) ?? []
            let localMap = Dictionary(uniqueKeysWithValues:
                local.filter { $0.canvasID == canvasID }.map { ($0.id, $0) }
            )

            for row in rows {
                guard let rowID = UUID(uuidString: row.id) else { continue }

                if row.is_deleted {
                    if let localGroup = localMap[rowID] {
                        context.delete(localGroup)
                    }
                    continue
                }

                let remoteUpdated = iso.date(from: row.updated_at) ?? .distantPast

                if let localGroup = localMap[rowID] {
                    if remoteUpdated > localGroup.updatedAt {
                        localGroup.name = row.name
                        localGroup.updatedAt = remoteUpdated
                    }
                } else {
                    let group = CanvasElementGroupModel(canvasID: canvasID, name: row.name)
                    group.id = rowID
                    group.createdAt = iso.date(from: row.created_at) ?? Date()
                    group.updatedAt = remoteUpdated
                    context.insert(group)
                }
            }

            try? context.save()
        } catch {
            print("⚠️ Element group pull failed: \(error.localizedDescription)")
        }
    }

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertElementGroup:
                if let row = try? JSONDecoder().decode(ElementGroupRow.self, from: operation.payload) {
                    do {
                        try await supabase
                            .from("element_groups")
                            .upsert(row, onConflict: "id")
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush element group upsert failed: \(error.localizedDescription)")
                    }
                }

            case .deleteElementGroup:
                if let payload = try? JSONDecoder().decode(ElementGroupDeletePayload.self,
                                                           from: operation.payload) {
                    do {
                        try await supabase
                            .from("element_groups")
                            .update(ElementGroupDeleteUpdate(
                                is_deleted: true,
                                updated_at: payload.updated_at
                            ))
                            .eq("id", value: payload.id)
                            .eq("user_id", value: payload.user_id)
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush element group delete failed: \(error.localizedDescription)")
                    }
                }

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    private func makeRow(group: CanvasElementGroupModel, userID: String) -> ElementGroupRow {
        let now = iso.string(from: Date())
        return ElementGroupRow(
            id: group.id.uuidString,
            canvas_id: group.canvasID.uuidString,
            user_id: userID,
            name: group.name,
            created_at: iso.string(from: group.createdAt),
            updated_at: now,
            is_deleted: false
        )
    }
}
