//
//  ConnectorSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

// MARK: - Row shapes

private struct ConnectorRow: Codable {
    let id:               String
    let canvas_id:        String
    let user_id:          String
    let from_element_id:  String
    let from_anchor_raw:  String
    let to_element_id:    String
    let to_anchor_raw:    String
    let line_style_raw:   String
    let color_name:       String
    let stroke_width:     Double
    let has_arrow_head:   Bool
    let created_at:       String
    let updated_at:       String
    let is_deleted:       Bool
}

private struct ConnectorDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct ConnectorDeletePayload: Codable {
    let id:         String
    let user_id:    String
    let updated_at: String
}

// MARK: - ConnectorSyncService

@MainActor
final class ConnectorSyncService {

    static let shared = ConnectorSyncService()

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

    func upsert(_ connector: ConnectorModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = makeRow(connector: connector, userID: userID)

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertConnector, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("connectors")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertConnector, payload: data))
            }
            print("⚠️ Connector upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Soft delete

    func delete(_ connector: ConnectorModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let connectorID = connector.id.uuidString
        let now         = iso.string(from: Date())

        guard network.isConnected else {
            let payload = ConnectorDeletePayload(id: connectorID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteConnector, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("connectors")
                .update(ConnectorDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id",      value: connectorID)
                .eq("user_id", value: userID)
                .execute()
        } catch {
            let payload = ConnectorDeletePayload(id: connectorID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteConnector, payload: data))
            }
            print("⚠️ Connector delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull ALL rows (including deleted) → merge into SwiftData

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.syncUserID else { return }

        do {
            let rows: [ConnectorRow] = try await supabase
                .from("connectors")
                .select()
                .eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id",   value: userID)
                .execute()
                .value

            let localConnectors = (try? context.fetch(FetchDescriptor<ConnectorModel>())) ?? []
            let localCanvasConnectors = localConnectors.filter { $0.canvasID == canvasID }
            let localMap = Dictionary(uniqueKeysWithValues: localCanvasConnectors.map { ($0.id, $0) })

            for row in rows {
                guard let rowID = UUID(uuidString: row.id) else { continue }

                if row.is_deleted {
                    if let local = localMap[rowID] {
                        context.delete(local)
                    }
                    continue
                }

                guard let fromID = UUID(uuidString: row.from_element_id),
                      let toID   = UUID(uuidString: row.to_element_id) else { continue }

                if let local = localMap[rowID] {
                    let remoteUpdated = iso.date(from: row.updated_at) ?? .distantPast
                    if remoteUpdated > local.updatedAt {
                        local.fromElementID = fromID
                        local.fromAnchorRaw = row.from_anchor_raw
                        local.toElementID   = toID
                        local.toAnchorRaw   = row.to_anchor_raw
                        local.lineStyleRaw  = row.line_style_raw
                        local.colorName     = row.color_name
                        local.strokeWidth   = row.stroke_width
                        local.hasArrowHead  = row.has_arrow_head
                        local.updatedAt     = remoteUpdated
                    }
                } else {
                    let fromAnchor = ConnectorAnchor(rawValue: row.from_anchor_raw) ?? .right
                    let toAnchor   = ConnectorAnchor(rawValue: row.to_anchor_raw)   ?? .left
                    let lineStyle  = ConnectorLineStyle(rawValue: row.line_style_raw) ?? .curved

                    let connector = ConnectorModel(
                        canvasID:      canvasID,
                        fromElementID: fromID, fromAnchor: fromAnchor,
                        toElementID:   toID,   toAnchor:   toAnchor,
                        lineStyle:     lineStyle,
                        colorName:     row.color_name,
                        strokeWidth:   row.stroke_width,
                        hasArrowHead:  row.has_arrow_head
                    )
                    connector.id        = rowID
                    connector.createdAt = iso.date(from: row.created_at) ?? Date()
                    connector.updatedAt = iso.date(from: row.updated_at) ?? Date()
                    context.insert(connector)
                }
            }

            try? context.save()

        } catch {
            print("⚠️ Connector pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Flush offline queue

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertConnector:
                if let row = try? JSONDecoder().decode(ConnectorRow.self, from: operation.payload) {
                    do {
                        try await supabase
                            .from("connectors")
                            .upsert(row, onConflict: "id")
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush connector upsert failed: \(error.localizedDescription)")
                    }
                }

            case .deleteConnector:
                if let payload = try? JSONDecoder().decode(ConnectorDeletePayload.self,
                                                           from: operation.payload) {
                    do {
                        try await supabase
                            .from("connectors")
                            .update(ConnectorDeleteUpdate(
                                is_deleted: true,
                                updated_at: payload.updated_at
                            ))
                            .eq("id",      value: payload.id)
                            .eq("user_id", value: payload.user_id)
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush connector delete failed: \(error.localizedDescription)")
                    }
                }

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    // MARK: - Helpers

    private func makeRow(connector: ConnectorModel, userID: String) -> ConnectorRow {
        let now = iso.string(from: Date())
        return ConnectorRow(
            id:              connector.id.uuidString,
            canvas_id:       connector.canvasID.uuidString,
            user_id:         userID,
            from_element_id: connector.fromElementID.uuidString,
            from_anchor_raw: connector.fromAnchorRaw,
            to_element_id:   connector.toElementID.uuidString,
            to_anchor_raw:   connector.toAnchorRaw,
            line_style_raw:  connector.lineStyleRaw,
            color_name:      connector.colorName,
            stroke_width:    connector.strokeWidth,
            has_arrow_head:  connector.hasArrowHead,
            created_at:      iso.string(from: connector.createdAt),
            updated_at:      now,
            is_deleted:      false
        )
    }
}
