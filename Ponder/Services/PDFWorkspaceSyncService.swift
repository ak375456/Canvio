import Foundation
import SwiftData
import Supabase

private struct PDFPageElementRow: Codable {
    let id: String
    let document_id: String
    let canvas_id: String
    let user_id: String
    let pdf_file_name: String
    let original_name: String
    let page_index: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let rotation: Double
    let crop_x: Double
    let crop_y: Double
    let crop_width: Double
    let crop_height: Double
    let shows_annotations: Bool
    let z_index: Int
    let group_id: String?
    let created_at: String
    let updated_at: String
    let is_deleted: Bool
}

private struct PDFHighlightRow: Codable {
    let id: String
    let document_id: String
    let canvas_id: String
    let user_id: String
    let page_index: Int
    let selected_text: String
    let rects: [PDFNormalizedRect]
    let color_hex: String
    let opacity: Double
    let note: String?
    let created_at: String
    let updated_at: String
    let is_deleted: Bool
}

private struct PDFInkRow: Codable {
    let id: String
    let document_id: String
    let canvas_id: String
    let user_id: String
    let page_index: Int
    let drawing_data: String
    let coordinate_width: Double
    let coordinate_height: Double
    let format_version: Int
    let created_at: String
    let updated_at: String
    let is_deleted: Bool
}

private struct PDFReadingRow: Codable {
    let id: String
    let document_id: String
    let user_id: String
    let current_page_index: Int
    let scroll_progress: Double
    let zoom_scale: Double
    let display_mode_raw: String
    let sidebar_visible: Bool
    let last_opened_at: String
    let updated_at: String
}

private struct PDFWorkspaceDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct PDFWorkspaceDeletePayload: Codable {
    let id: String
    let user_id: String
    let updated_at: String
}

@MainActor
final class PDFWorkspaceSyncService {
    static let shared = PDFWorkspaceSyncService()

    private let supabase = SupabaseService.shared.client
    private let queue = SyncQueue.shared
    private let network = NetworkMonitor.shared
    private let media = MediaSyncService.shared
    private let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    func upsert(_ element: PDFPageElementModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = pageRow(element, userID: userID)
        await upsert(row, table: "pdf_page_elements", operation: .upsertPDFPage)
    }

    func upsert(_ highlight: PDFHighlightModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = highlightRow(highlight, userID: userID)
        await upsert(row, table: "pdf_highlights", operation: .upsertPDFHighlight)
    }

    func upsert(_ ink: PDFInkLayerModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = inkRow(ink, userID: userID)
        await upsert(row, table: "pdf_ink_layers", operation: .upsertPDFInk)
    }

    func upsert(_ state: PDFReadingStateModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = readingRow(state, userID: userID)
        await upsert(row, table: "pdf_reading_states", operation: .upsertPDFReadingState)
    }

    func delete(_ element: PDFPageElementModel) async {
        await softDelete(id: element.id, table: "pdf_page_elements", operation: .deletePDFPage)
    }

    func delete(_ highlight: PDFHighlightModel) async {
        await softDelete(id: highlight.id, table: "pdf_highlights", operation: .deletePDFHighlight)
    }

    func delete(_ ink: PDFInkLayerModel) async {
        await softDelete(id: ink.id, table: "pdf_ink_layers", operation: .deletePDFInk)
    }

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected, let userID = AuthService.shared.syncUserID else { return }
        do {
            async let pageResult: [PDFPageElementRow] = supabase.from("pdf_page_elements")
                .select().eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id", value: userID).execute().value
            async let highlightResult: [PDFHighlightRow] = supabase.from("pdf_highlights")
                .select().eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id", value: userID).execute().value
            async let inkResult: [PDFInkRow] = supabase.from("pdf_ink_layers")
                .select().eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id", value: userID).execute().value
            async let readingResult: [PDFReadingRow] = supabase.from("pdf_reading_states")
                .select().eq("user_id", value: userID).execute().value

            let (pages, highlights, inks, readingStates) = try await (
                pageResult, highlightResult, inkResult, readingResult
            )
            merge(pages, canvasID: canvasID, context: context)
            merge(highlights, canvasID: canvasID, context: context)
            merge(inks, canvasID: canvasID, context: context)
            merge(readingStates, context: context)
            try? context.save()
        } catch {
            print("⚠️ PDF workspace pull failed: \(error.localizedDescription)")
        }
    }

    func reconcile(canvasID: UUID, context: ModelContext) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let metadata = await SyncStalenessGuard.loadMetadata(
            supabase: supabase,
            userID: userID,
            tables: [
                "pdf_page_elements",
                "pdf_highlights",
                "pdf_ink_layers"
            ]
        )
        let pages = ((try? context.fetch(FetchDescriptor<PDFPageElementModel>())) ?? [])
            .filter { $0.canvasID == canvasID }
        let highlights = ((try? context.fetch(FetchDescriptor<PDFHighlightModel>())) ?? [])
            .filter { $0.canvasID == canvasID }
        let inks = ((try? context.fetch(FetchDescriptor<PDFInkLayerModel>())) ?? [])
            .filter { $0.canvasID == canvasID }
        for item in pages where metadata.shouldUpload(
            table: "pdf_page_elements",
            id: item.id,
            localUpdatedAt: item.updatedAt
        ) {
            await upsert(item)
        }
        for item in highlights where metadata.shouldUpload(
            table: "pdf_highlights",
            id: item.id,
            localUpdatedAt: item.updatedAt
        ) {
            await upsert(item)
        }
        for item in inks where metadata.shouldUpload(
            table: "pdf_ink_layers",
            id: item.id,
            localUpdatedAt: item.updatedAt
        ) {
            await upsert(item)
        }
    }

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }
        for operation in queue.all() {
            let succeeded: Bool
            switch operation.type {
            case .upsertPDFPage:
                succeeded = await flushUpsert(operation, as: PDFPageElementRow.self, table: "pdf_page_elements")
            case .upsertPDFHighlight:
                succeeded = await flushUpsert(operation, as: PDFHighlightRow.self, table: "pdf_highlights")
            case .upsertPDFInk:
                succeeded = await flushUpsert(operation, as: PDFInkRow.self, table: "pdf_ink_layers")
            case .upsertPDFReadingState:
                succeeded = await flushUpsert(operation, as: PDFReadingRow.self, table: "pdf_reading_states")
            case .deletePDFPage:
                succeeded = await flushDelete(operation, table: "pdf_page_elements")
            case .deletePDFHighlight:
                succeeded = await flushDelete(operation, table: "pdf_highlights")
            case .deletePDFInk:
                succeeded = await flushDelete(operation, table: "pdf_ink_layers")
            default:
                succeeded = false
            }
            if succeeded { queue.remove(id: operation.id) }
        }
    }

    private func upsert<Row: Encodable>(_ row: Row, table: String,
                                         operation: SyncOperationType) async {
        guard network.isConnected else {
            enqueue(row, operation: operation)
            return
        }
        do {
            try await supabase.from(table).upsert(row, onConflict: "id").execute()
        } catch {
            enqueue(row, operation: operation)
            print("⚠️ \(table) upsert failed: \(error.localizedDescription)")
        }
    }

    private func softDelete(id: UUID, table: String, operation: SyncOperationType) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let now = iso.string(from: Date())
        let payload = PDFWorkspaceDeletePayload(id: id.uuidString, user_id: userID, updated_at: now)
        guard network.isConnected else {
            enqueue(payload, operation: operation)
            return
        }
        do {
            try await supabase.from(table)
                .update(PDFWorkspaceDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id", value: id.uuidString).eq("user_id", value: userID).execute()
        } catch {
            enqueue(payload, operation: operation)
            print("⚠️ \(table) delete failed: \(error.localizedDescription)")
        }
    }

    private func enqueue<Row: Encodable>(_ row: Row, operation: SyncOperationType) {
        if let data = try? JSONEncoder().encode(row) {
            queue.enqueue(SyncOperation(type: operation, payload: data))
        }
    }

    private func flushUpsert<Row: Codable>(_ operation: SyncOperation, as type: Row.Type,
                                            table: String) async -> Bool {
        await SyncStalenessGuard.flushUpsert(
            operation,
            as: type,
            table: table,
            supabase: supabase,
            label: table
        )
    }

    private func flushDelete(_ operation: SyncOperation, table: String) async -> Bool {
        await SyncStalenessGuard.flushSoftDelete(
            operation,
            table: table,
            supabase: supabase,
            label: table
        )
    }

    private func pageRow(_ item: PDFPageElementModel, userID: String) -> PDFPageElementRow {
        PDFPageElementRow(
            id: item.id.uuidString, document_id: item.documentID.uuidString,
            canvas_id: item.canvasID.uuidString, user_id: userID,
            pdf_file_name: item.pdfFileName, original_name: item.originalName,
            page_index: item.pageIndex, x: item.x, y: item.y,
            width: item.width, height: item.height, rotation: item.rotation,
            crop_x: item.cropX, crop_y: item.cropY,
            crop_width: item.cropWidth, crop_height: item.cropHeight,
            shows_annotations: item.showsAnnotations, z_index: item.zIndex,
            group_id: item.groupID?.uuidString,
            created_at: iso.string(from: item.createdAt),
            updated_at: iso.string(from: item.updatedAt), is_deleted: false
        )
    }

    private func highlightRow(_ item: PDFHighlightModel, userID: String) -> PDFHighlightRow {
        PDFHighlightRow(
            id: item.id.uuidString, document_id: item.documentID.uuidString,
            canvas_id: item.canvasID.uuidString, user_id: userID,
            page_index: item.pageIndex, selected_text: item.selectedText,
            rects: item.rects, color_hex: item.colorHex, opacity: item.opacity,
            note: item.note, created_at: iso.string(from: item.createdAt),
            updated_at: iso.string(from: item.updatedAt), is_deleted: false
        )
    }

    private func inkRow(_ item: PDFInkLayerModel, userID: String) -> PDFInkRow {
        PDFInkRow(
            id: item.id.uuidString, document_id: item.documentID.uuidString,
            canvas_id: item.canvasID.uuidString, user_id: userID,
            page_index: item.pageIndex,
            drawing_data: item.drawingData.base64EncodedString(),
            coordinate_width: item.coordinateWidth,
            coordinate_height: item.coordinateHeight,
            format_version: item.formatVersion,
            created_at: iso.string(from: item.createdAt),
            updated_at: iso.string(from: item.updatedAt), is_deleted: false
        )
    }

    private func readingRow(_ item: PDFReadingStateModel, userID: String) -> PDFReadingRow {
        PDFReadingRow(
            id: item.id.uuidString, document_id: item.documentID.uuidString,
            user_id: userID, current_page_index: item.currentPageIndex,
            scroll_progress: item.scrollProgress, zoom_scale: item.zoomScale,
            display_mode_raw: item.displayModeRaw, sidebar_visible: item.sidebarVisible,
            last_opened_at: iso.string(from: item.lastOpenedAt),
            updated_at: iso.string(from: item.updatedAt)
        )
    }

    private func merge(_ rows: [PDFPageElementRow], canvasID: UUID, context: ModelContext) {
        let locals = ((try? context.fetch(FetchDescriptor<PDFPageElementModel>())) ?? [])
            .filter { $0.canvasID == canvasID }
        let map = Dictionary(uniqueKeysWithValues: locals.map { ($0.id, $0) })
        for row in rows {
            guard let id = UUID(uuidString: row.id), let documentID = UUID(uuidString: row.document_id) else { continue }
            if row.is_deleted { if let local = map[id] { context.delete(local) }; continue }
            let item = map[id] ?? PDFPageElementModel(documentID: documentID, canvasID: canvasID,
                pageIndex: row.page_index, pdfFileName: row.pdf_file_name,
                originalName: row.original_name, x: row.x, y: row.y,
                width: row.width, height: row.height)
            if map[id] == nil { item.id = id; context.insert(item) }
            guard iso.date(from: row.updated_at) ?? .distantPast >= item.updatedAt || map[id] == nil else { continue }
            item.documentID = documentID; item.pageIndex = row.page_index
            item.pdfFileName = row.pdf_file_name; item.originalName = row.original_name
            item.x = row.x; item.y = row.y; item.width = row.width; item.height = row.height
            item.rotation = row.rotation; item.cropX = row.crop_x; item.cropY = row.crop_y
            item.cropWidth = row.crop_width; item.cropHeight = row.crop_height
            item.showsAnnotations = row.shows_annotations; item.zIndex = row.z_index
            item.groupID = row.group_id.flatMap(UUID.init(uuidString:))
            item.createdAt = iso.date(from: row.created_at) ?? Date()
            item.updatedAt = iso.date(from: row.updated_at) ?? Date()
            if !row.pdf_file_name.isEmpty {
                Task {
                    await media.downloadBundleIfNeeded(.pdfFile(fileName: row.pdf_file_name))
                }
            }
        }
    }

    private func merge(_ rows: [PDFHighlightRow], canvasID: UUID, context: ModelContext) {
        let locals = ((try? context.fetch(FetchDescriptor<PDFHighlightModel>())) ?? [])
            .filter { $0.canvasID == canvasID }
        let map = Dictionary(uniqueKeysWithValues: locals.map { ($0.id, $0) })
        for row in rows {
            guard let id = UUID(uuidString: row.id), let documentID = UUID(uuidString: row.document_id) else { continue }
            if row.is_deleted { if let local = map[id] { context.delete(local) }; continue }
            let item = map[id] ?? PDFHighlightModel(documentID: documentID, canvasID: canvasID,
                pageIndex: row.page_index, selectedText: row.selected_text, rects: row.rects)
            if map[id] == nil { item.id = id; context.insert(item) }
            guard iso.date(from: row.updated_at) ?? .distantPast >= item.updatedAt || map[id] == nil else { continue }
            item.pageIndex = row.page_index; item.selectedText = row.selected_text
            item.rects = row.rects; item.colorHex = row.color_hex; item.opacity = row.opacity
            item.note = row.note; item.createdAt = iso.date(from: row.created_at) ?? Date()
            item.updatedAt = iso.date(from: row.updated_at) ?? Date()
        }
    }

    private func merge(_ rows: [PDFInkRow], canvasID: UUID, context: ModelContext) {
        let locals = ((try? context.fetch(FetchDescriptor<PDFInkLayerModel>())) ?? [])
            .filter { $0.canvasID == canvasID }
        let map = Dictionary(uniqueKeysWithValues: locals.map { ($0.id, $0) })
        for row in rows {
            guard let id = UUID(uuidString: row.id), let documentID = UUID(uuidString: row.document_id) else { continue }
            if row.is_deleted { if let local = map[id] { context.delete(local) }; continue }
            let item = map[id] ?? PDFInkLayerModel(documentID: documentID, canvasID: canvasID,
                                                   pageIndex: row.page_index)
            if map[id] == nil { item.id = id; context.insert(item) }
            guard iso.date(from: row.updated_at) ?? .distantPast >= item.updatedAt || map[id] == nil else { continue }
            item.pageIndex = row.page_index; item.drawingData = Data(base64Encoded: row.drawing_data) ?? Data()
            item.coordinateWidth = row.coordinate_width; item.coordinateHeight = row.coordinate_height
            item.formatVersion = row.format_version; item.createdAt = iso.date(from: row.created_at) ?? Date()
            item.updatedAt = iso.date(from: row.updated_at) ?? Date()
        }
    }

    private func merge(_ rows: [PDFReadingRow], context: ModelContext) {
        let locals = (try? context.fetch(FetchDescriptor<PDFReadingStateModel>())) ?? []
        let map = Dictionary(uniqueKeysWithValues: locals.map { ($0.documentID, $0) })
        for row in rows {
            guard let documentID = UUID(uuidString: row.document_id) else { continue }
            let item = map[documentID] ?? PDFReadingStateModel(documentID: documentID)
            if map[documentID] == nil { item.id = UUID(uuidString: row.id) ?? documentID; context.insert(item) }
            guard iso.date(from: row.updated_at) ?? .distantPast >= item.updatedAt || map[documentID] == nil else { continue }
            item.currentPageIndex = row.current_page_index; item.scrollProgress = row.scroll_progress
            item.zoomScale = row.zoom_scale; item.displayModeRaw = row.display_mode_raw
            item.sidebarVisible = row.sidebar_visible
            item.lastOpenedAt = iso.date(from: row.last_opened_at) ?? Date()
            item.updatedAt = iso.date(from: row.updated_at) ?? Date()
        }
    }
}
