//
//  PDFSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

// MARK: - Row shapes

private struct PDFRow: Codable {
    let id:                  String
    let document_id:         String
    let canvas_id:           String
    let user_id:             String
    let pdf_file_name:       String
    let thumbnail_file_name: String
    let original_name:       String
    let page_count:          Int
    let x:                   Double
    let y:                   Double
    let width:               Double
    let height:              Double
    let rotation:            Double
    let z_index:             Int
    let group_id:            String?
    let created_at:          String
    let updated_at:          String
    let is_deleted:          Bool
}

private struct PDFDocumentAssetRow: Codable {
    let id: String
    let user_id: String
    let pdf_file_name: String
    let thumbnail_file_name: String
    let original_name: String
    let page_count: Int
    let file_size_bytes: Int64?
    let sha256: String?
    let created_at: String
    let updated_at: String
    let is_deleted: Bool
}

private struct PDFDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct PDFDeletePayload: Codable {
    let id:                  String
    let user_id:             String
    let updated_at:          String
    let pdf_file_name:       String
    let thumbnail_file_name: String
    let delete_asset: Bool
}

// MARK: - PDFSyncService

@MainActor
final class PDFSyncService {

    static let shared = PDFSyncService()

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

    func upsert(_ element: PDFElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = makeRow(element: element, userID: userID)
        let documentRow = makeDocumentRow(element: element, userID: userID)

        Task {
            await media.uploadBundle(.pdf(
                pdfFileName: element.pdfFileName,
                thumbnailFileName: element.thumbnailFileName
            ))
        }

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertPDF, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("pdf_documents")
                .upsert(documentRow, onConflict: "id")
                .execute()
            try await supabase
                .from("pdf_elements")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertPDF, payload: data))
            }
            print("⚠️ PDF upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Soft delete

    func delete(_ element: PDFElementModel, deleteAsset: Bool = true) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let elementID = element.id.uuidString
        let now       = iso.string(from: Date())

        guard network.isConnected else {
            let payload = PDFDeletePayload(id: elementID, user_id: userID, updated_at: now,
                                           pdf_file_name: element.pdfFileName,
                                           thumbnail_file_name: element.thumbnailFileName,
                                           delete_asset: deleteAsset)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deletePDF, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("pdf_elements")
                .update(PDFDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id",      value: elementID)
                .eq("user_id", value: userID)
                .execute()
            if deleteAsset {
                Task {
                    await media.deleteBundle(.pdf(
                        pdfFileName: element.pdfFileName,
                        thumbnailFileName: element.thumbnailFileName
                    ))
                }
            }
        } catch {
            let payload = PDFDeletePayload(id: elementID, user_id: userID, updated_at: now,
                                           pdf_file_name: element.pdfFileName,
                                           thumbnail_file_name: element.thumbnailFileName,
                                           delete_asset: deleteAsset)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deletePDF, payload: data))
            }
            print("⚠️ PDF delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull ALL rows + download missing files (lazy)

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.syncUserID else { return }

        do {
            let rows: [PDFRow] = try await supabase
                .from("pdf_elements")
                .select()
                .eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id",   value: userID)
                .execute()
                .value

            let localElements = (try? context.fetch(FetchDescriptor<PDFElementModel>())) ?? []
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
                        local.documentID = UUID(uuidString: row.document_id)
                        local.y         = row.y
                        local.width     = row.width
                        local.height    = row.height
                        local.rotation  = row.rotation
                        local.zIndex    = row.z_index
                        local.groupID   = row.group_id.flatMap { UUID(uuidString: $0) }
                        local.updatedAt = remoteUpdated
                    }
                    Task {
                        await media.downloadBundleIfNeeded(.pdf(
                            pdfFileName: row.pdf_file_name,
                            thumbnailFileName: row.thumbnail_file_name
                        ))
                    }
                } else {
                    let element = PDFElementModel(
                        canvasID: canvasID,
                        pdfFileName: row.pdf_file_name,
                        thumbnailFileName: row.thumbnail_file_name,
                        originalName: row.original_name,
                        pageCount: row.page_count,
                        x: row.x, y: row.y
                    )
                    element.id        = rowID
                    element.documentID = UUID(uuidString: row.document_id)
                    element.width     = row.width
                    element.height    = row.height
                    element.rotation  = row.rotation
                    element.zIndex    = row.z_index
                    element.groupID   = row.group_id.flatMap { UUID(uuidString: $0) }
                    element.createdAt = iso.date(from: row.created_at) ?? Date()
                    element.updatedAt = iso.date(from: row.updated_at) ?? Date()
                    context.insert(element)
                    Task {
                        await media.downloadBundleIfNeeded(.pdf(
                            pdfFileName: row.pdf_file_name,
                            thumbnailFileName: row.thumbnail_file_name
                        ))
                    }
                }
            }

            try? context.save()

        } catch {
            print("⚠️ PDF pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Flush offline queue

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertPDF:
                if let row = try? JSONDecoder().decode(PDFRow.self, from: operation.payload) {
                    switch await SyncStalenessGuard.writeDecision(supabase: supabase, table: "pdf_elements", payload: operation.payload) {
                    case .write:
                        do {
                            let fileURL = PDFStorageService.pdfsDirectory.appendingPathComponent(row.pdf_file_name)
                            let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
                            let documentRow = PDFDocumentAssetRow(
                                id: row.document_id, user_id: row.user_id,
                                pdf_file_name: row.pdf_file_name,
                                thumbnail_file_name: row.thumbnail_file_name,
                                original_name: row.original_name, page_count: max(1, row.page_count),
                                file_size_bytes: fileSize, sha256: nil,
                                created_at: row.created_at, updated_at: row.updated_at,
                                is_deleted: false
                            )
                            try await supabase.from("pdf_documents")
                                .upsert(documentRow, onConflict: "id").execute()
                            try await supabase
                                .from("pdf_elements")
                                .upsert(row, onConflict: "id")
                                .execute()
                            Task {
                                await media.uploadBundle(.pdf(
                                    pdfFileName: row.pdf_file_name,
                                    thumbnailFileName: row.thumbnail_file_name
                                ))
                            }
                            succeeded = true
                        } catch {
                            print("⚠️ Queue flush PDF upsert failed: \(error.localizedDescription)")
                        }
                    case .stale:
                        succeeded = true
                    case .retry:
                        break
                    }
                }

            case .deletePDF:
                if let payload = try? JSONDecoder().decode(PDFDeletePayload.self, from: operation.payload) {
                    switch await SyncStalenessGuard.writeDecision(supabase: supabase, table: "pdf_elements", payload: operation.payload) {
                    case .write:
                        do {
                            try await supabase
                                .from("pdf_elements")
                                .update(PDFDeleteUpdate(is_deleted: true, updated_at: payload.updated_at))
                                .eq("id",      value: payload.id)
                                .eq("user_id", value: payload.user_id)
                                .execute()
                            if payload.delete_asset {
                                Task {
                                    await media.deleteBundle(.pdf(
                                        pdfFileName: payload.pdf_file_name,
                                        thumbnailFileName: payload.thumbnail_file_name
                                    ))
                                }
                            }
                            succeeded = true
                        } catch {
                            print("⚠️ Queue flush PDF delete failed: \(error.localizedDescription)")
                        }
                    case .stale:
                        succeeded = true
                    case .retry:
                        break
                    }
                }

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    // MARK: - Helpers

    private func makeRow(element: PDFElementModel, userID: String) -> PDFRow {
        return PDFRow(
            id:                  element.id.uuidString,
            document_id:         element.resolvedDocumentID.uuidString,
            canvas_id:           element.canvasID.uuidString,
            user_id:             userID,
            pdf_file_name:       element.pdfFileName,
            thumbnail_file_name: element.thumbnailFileName,
            original_name:       element.originalName,
            page_count:          element.pageCount,
            x:                   element.x,
            y:                   element.y,
            width:               element.width,
            height:              element.height,
            rotation:            element.rotation,
            z_index:             element.zIndex,
            group_id:            element.groupID?.uuidString,
            created_at:          iso.string(from: element.createdAt),
            updated_at:          iso.string(from: element.updatedAt),
            is_deleted:          false
        )
    }

    private func makeDocumentRow(element: PDFElementModel, userID: String) -> PDFDocumentAssetRow {
        let fileURL = PDFStorageService.pdfsDirectory.appendingPathComponent(element.pdfFileName)
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        return PDFDocumentAssetRow(
            id: element.resolvedDocumentID.uuidString,
            user_id: userID,
            pdf_file_name: element.pdfFileName,
            thumbnail_file_name: element.thumbnailFileName,
            original_name: element.originalName,
            page_count: max(1, element.pageCount),
            file_size_bytes: fileSize,
            sha256: nil,
            created_at: iso.string(from: element.createdAt),
            updated_at: iso.string(from: element.updatedAt),
            is_deleted: false
        )
    }
}
