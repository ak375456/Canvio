import Foundation
import Supabase

struct SyncRemoteMetadata: Decodable {
    let id: String
    let updated_at: String
    let is_deleted: Bool?
}

private struct SyncPayloadIdentity: Decodable {
    let id: String
    let user_id: String
    let updated_at: String
}

private struct SyncSoftDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

enum SyncWriteDecision {
    case write
    case stale
    case retry
}

struct SyncReconcileMetadata {
    private let maps: [String: [String: SyncRemoteMetadata]]
    private let unavailableTables: Set<String>

    init(maps: [String: [String: SyncRemoteMetadata]], unavailableTables: Set<String>) {
        self.maps = maps
        self.unavailableTables = unavailableTables
    }

    func shouldUpload(table: String, id: UUID, localUpdatedAt: Date) -> Bool {
        shouldUpload(table: table, id: id.uuidString, localUpdatedAt: localUpdatedAt)
    }

    func shouldUpload(table: String, id: String, localUpdatedAt: Date) -> Bool {
        guard !unavailableTables.contains(table) else { return false }
        let remote = maps[table]?[id.lowercased()]
        return SyncStalenessGuard.shouldUpload(localUpdatedAt: localUpdatedAt, remote: remote)
    }
}

@MainActor
enum SyncStalenessGuard {
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func loadMetadata(
        supabase: SupabaseClient,
        userID: String,
        tables: [String]
    ) async -> SyncReconcileMetadata {
        var maps: [String: [String: SyncRemoteMetadata]] = [:]
        var unavailableTables = Set<String>()

        for table in tables {
            do {
                let rows: [SyncRemoteMetadata] = try await supabase
                    .from(table)
                    .select("id, updated_at")
                    .eq("user_id", value: userID)
                    .execute()
                    .value
                maps[table] = Dictionary(
                    rows.map { ($0.id.lowercased(), $0) },
                    uniquingKeysWith: { current, replacement in
                        guard let currentDate = parse(current.updated_at),
                              let replacementDate = parse(replacement.updated_at) else {
                            return replacement
                        }
                        return replacementDate > currentDate ? replacement : current
                    }
                )
            } catch {
                unavailableTables.insert(table)
                print("⚠️ Metadata fetch failed for \(table): \(error.localizedDescription)")
            }
        }

        return SyncReconcileMetadata(maps: maps, unavailableTables: unavailableTables)
    }

    static func writeDecision(
        supabase: SupabaseClient,
        table: String,
        payload: Data
    ) async -> SyncWriteDecision {
        guard let identity = try? JSONDecoder().decode(SyncPayloadIdentity.self, from: payload) else {
            return .write
        }

        return await writeDecision(
            supabase: supabase,
            table: table,
            id: identity.id,
            userID: identity.user_id,
            updatedAt: identity.updated_at
        )
    }

    static func flushUpsert<Row: Codable>(
        _ operation: SyncOperation,
        as type: Row.Type,
        table: String,
        supabase: SupabaseClient,
        label: String
    ) async -> Bool {
        guard let row = try? JSONDecoder().decode(type, from: operation.payload) else { return false }

        switch await writeDecision(supabase: supabase, table: table, payload: operation.payload) {
        case .write:
            do {
                try await supabase.from(table).upsert(row, onConflict: "id").execute()
                return true
            } catch {
                print("⚠️ Queue flush \(label) upsert failed: \(error.localizedDescription)")
                return false
            }
        case .stale:
            return true
        case .retry:
            return false
        }
    }

    static func flushSoftDelete(
        _ operation: SyncOperation,
        table: String,
        supabase: SupabaseClient,
        label: String
    ) async -> Bool {
        guard let identity = try? JSONDecoder().decode(SyncPayloadIdentity.self, from: operation.payload) else {
            return false
        }

        switch await writeDecision(supabase: supabase, table: table, payload: operation.payload) {
        case .write:
            do {
                try await supabase
                    .from(table)
                    .update(SyncSoftDeleteUpdate(is_deleted: true, updated_at: identity.updated_at))
                    .eq("id", value: identity.id)
                    .eq("user_id", value: identity.user_id)
                    .execute()
                return true
            } catch {
                print("⚠️ Queue flush \(label) delete failed: \(error.localizedDescription)")
                return false
            }
        case .stale:
            return true
        case .retry:
            return false
        }
    }

    static func writeDecision(
        supabase: SupabaseClient,
        table: String,
        id: String,
        userID: String,
        updatedAt: String
    ) async -> SyncWriteDecision {
        guard let incomingDate = parse(updatedAt) else {
            return .write
        }

        do {
            let rows: [SyncRemoteMetadata] = try await supabase
                .from(table)
                .select("id, updated_at")
                .eq("id", value: id)
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value

            guard let remote = rows.first else { return .write }
            guard shouldUpload(localUpdatedAt: incomingDate, remote: remote) else {
                let remoteState = remote.is_deleted == true ? "deleted" : "newer"
                print("⏭️ Skipped stale \(table) write for \(id); remote is \(remoteState)")
                return .stale
            }
            return .write
        } catch {
            print("⚠️ Metadata check failed for \(table) \(id): \(error.localizedDescription)")
            return .retry
        }
    }

    static func shouldUpload(localUpdatedAt: Date, remote: SyncRemoteMetadata?) -> Bool {
        guard let remote else { return true }
        guard let remoteUpdatedAt = parse(remote.updated_at) else { return true }
        return localUpdatedAt >= remoteUpdatedAt
    }

    private static func parse(_ value: String) -> Date? {
        iso.date(from: value)
    }
}
