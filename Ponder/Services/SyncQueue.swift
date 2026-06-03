//
//  SyncQueue.swift
//  Ponder
//

import Foundation

// MARK: - SyncOperation

struct SyncOperation: Codable, Identifiable {
    let id:        UUID
    let type:      SyncOperationType
    let payload:   Data
    let createdAt: Date

    init(type: SyncOperationType, payload: Data) {
        self.id        = UUID()
        self.type      = type
        self.payload   = payload
        self.createdAt = Date()
    }
}

enum SyncOperationType: String, Codable {
    case upsertCanvas
    case deleteCanvas
    case upsertText
    case deleteText
    case upsertSticky
    case deleteSticky
    case upsertShape
    case deleteShape
    case upsertConnector
    case deleteConnector
    case upsertDrawing
    case deleteDrawing
    case upsertTodoList
    case deleteTodoList
    case upsertTodoTask
    case deleteTodoTask
    case upsertTable
    case deleteTable
    case upsertTableCell
    case deleteTableCell
    case upsertImage
    case deleteImage
    case upsertPDF
    case deletePDF
    case upsertAudio
    case deleteAudio
    case upsertYouTube
    case deleteYouTube
    case upsertSymbol       // ← NEW
    case deleteSymbol       // ← NEW
}

// MARK: - SyncQueue

final class SyncQueue {

    static let shared = SyncQueue()

    private let key = "ponder.syncQueue"
    private var operations: [SyncOperation] = []

    private init() { load() }

    var isEmpty: Bool { operations.isEmpty }
    var count:   Int  { operations.count }

    func enqueue(_ operation: SyncOperation) {
        operations.append(operation); save()
    }

    func all() -> [SyncOperation] { operations }

    func remove(id: UUID) {
        operations.removeAll { $0.id == id }; save()
    }

    func clear() {
        operations.removeAll(); save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(operations) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let ops  = try? JSONDecoder().decode([SyncOperation].self, from: data)
        else { return }
        operations = ops
    }
}
