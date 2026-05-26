//
//  TodoSyncService.swift
//  Ponder
//

import Foundation
import SwiftData
import Supabase

// MARK: - Row shapes
// Note: prefixed with "DB" to avoid name clash with TodoTaskRow SwiftUI view

private struct DBTodoListRow: Codable {
    let id:         String
    let canvas_id:  String
    let user_id:    String
    let title:      String
    let x:          Double
    let y:          Double
    let width:      Double
    let height:     Double
    let color_name: String
    let z_index:    Int
    let created_at: String
    let updated_at: String
    let is_deleted: Bool
}

private struct DBTodoTaskRow: Codable {
    let id:             String
    let list_id:        String
    let user_id:        String
    let parent_task_id: String?
    let title:          String
    let is_completed:   Bool
    let priority_raw:   String
    let due_date:       String?
    let tags_raw:       String
    let sort_order:     Int
    let created_at:     String
    let updated_at:     String
    let is_deleted:     Bool
}

private struct ListDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct ListDeletePayload: Codable {
    let id:         String
    let user_id:    String
    let updated_at: String
}

private struct TaskDeleteUpdate: Encodable {
    let is_deleted: Bool
    let updated_at: String
}

private struct TaskDeletePayload: Codable {
    let id:         String
    let user_id:    String
    let updated_at: String
}

// MARK: - TodoSyncService

@MainActor
final class TodoSyncService {

    static let shared = TodoSyncService()

    private let supabase = SupabaseService.shared.client
    private let queue    = SyncQueue.shared
    private let network  = NetworkMonitor.shared
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    // MARK: - Upsert List

    func upsertList(_ list: TodoListModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = makeListRow(list: list, userID: userID)

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertTodoList, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("todo_lists")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertTodoList, payload: data))
            }
            print("⚠️ TodoList upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete List (soft-deletes all tasks first)

    func deleteList(_ list: TodoListModel, tasks: [TodoTaskModel]) async {
        guard let userID = AuthService.shared.syncUserID else { return }

        // Soft-delete all tasks belonging to this list first
        for task in tasks {
            await deleteTask(task)
        }

        // Then soft-delete the list
        let listID = list.id.uuidString
        let now    = iso.string(from: Date())

        guard network.isConnected else {
            let payload = ListDeletePayload(id: listID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteTodoList, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("todo_lists")
                .update(ListDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id",      value: listID)
                .eq("user_id", value: userID)
                .execute()
        } catch {
            let payload = ListDeletePayload(id: listID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteTodoList, payload: data))
            }
            print("⚠️ TodoList delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Upsert Task

    func upsertTask(_ task: TodoTaskModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let row = makeTaskRow(task: task, userID: userID)

        guard network.isConnected else {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertTodoTask, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("todo_tasks")
                .upsert(row, onConflict: "id")
                .execute()
        } catch {
            if let data = try? JSONEncoder().encode(row) {
                queue.enqueue(SyncOperation(type: .upsertTodoTask, payload: data))
            }
            print("⚠️ TodoTask upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete Task

    func deleteTask(_ task: TodoTaskModel) async {
        guard let userID = AuthService.shared.syncUserID else { return }
        let taskID = task.id.uuidString
        let now    = iso.string(from: Date())

        guard network.isConnected else {
            let payload = TaskDeletePayload(id: taskID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteTodoTask, payload: data))
            }
            return
        }

        do {
            try await supabase
                .from("todo_tasks")
                .update(TaskDeleteUpdate(is_deleted: true, updated_at: now))
                .eq("id",      value: taskID)
                .eq("user_id", value: userID)
                .execute()
        } catch {
            let payload = TaskDeletePayload(id: taskID, user_id: userID, updated_at: now)
            if let data = try? JSONEncoder().encode(payload) {
                queue.enqueue(SyncOperation(type: .deleteTodoTask, payload: data))
            }
            print("⚠️ TodoTask delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull ALL lists + tasks for a canvas

    func pullAll(canvasID: UUID, context: ModelContext) async {
        guard network.isConnected else { return }
        guard let userID = AuthService.shared.syncUserID else { return }

        // Pull lists
        do {
            let rows: [DBTodoListRow] = try await supabase
                .from("todo_lists")
                .select()
                .eq("canvas_id", value: canvasID.uuidString)
                .eq("user_id",   value: userID)
                .execute()
                .value

            let localLists = (try? context.fetch(FetchDescriptor<TodoListModel>())) ?? []
            let localCanvasLists = localLists.filter { $0.canvasID == canvasID }
            let localListMap = Dictionary(uniqueKeysWithValues: localCanvasLists.map { ($0.id, $0) })

            for row in rows {
                guard let rowID = UUID(uuidString: row.id) else { continue }

                if row.is_deleted {
                    if let local = localListMap[rowID] {
                        context.delete(local)
                    }
                    continue
                }

                if let local = localListMap[rowID] {
                    let remoteUpdated = iso.date(from: row.updated_at) ?? .distantPast
                    if remoteUpdated > local.updatedAt {
                        local.title     = row.title
                        local.x         = row.x
                        local.y         = row.y
                        local.width     = row.width
                        local.height    = row.height
                        local.colorName = row.color_name
                        local.zIndex    = row.z_index
                        local.updatedAt = remoteUpdated
                    }
                } else {
                    let list = TodoListModel(canvasID: canvasID, x: row.x, y: row.y)
                    list.id        = rowID
                    list.title     = row.title
                    list.width     = row.width
                    list.height    = row.height
                    list.colorName = row.color_name
                    list.zIndex    = row.z_index
                    list.createdAt = iso.date(from: row.created_at) ?? Date()
                    list.updatedAt = iso.date(from: row.updated_at) ?? Date()
                    context.insert(list)
                }
            }

            try? context.save()

        } catch {
            print("⚠️ TodoList pull failed: \(error.localizedDescription)")
        }

        // Pull tasks for all lists in this canvas
        let currentLists = (try? context.fetch(FetchDescriptor<TodoListModel>())) ?? []
        let canvasListIDs = Set(currentLists.filter { $0.canvasID == canvasID }.map { $0.id.uuidString })

        guard !canvasListIDs.isEmpty else { return }

        do {
            let rows: [DBTodoTaskRow] = try await supabase
                .from("todo_tasks")
                .select()
                .eq("user_id", value: userID)
                .in("list_id", values: Array(canvasListIDs))
                .execute()
                .value

            let localTasks = (try? context.fetch(FetchDescriptor<TodoTaskModel>())) ?? []
            let relevantLocalTasks = localTasks.filter { canvasListIDs.contains($0.listID.uuidString) }
            let localTaskMap = Dictionary(uniqueKeysWithValues: relevantLocalTasks.map { ($0.id, $0) })

            for row in rows {
                guard let rowID  = UUID(uuidString: row.id) else { continue }
                guard let listID = UUID(uuidString: row.list_id) else { continue }

                if row.is_deleted {
                    if let local = localTaskMap[rowID] {
                        context.delete(local)
                    }
                    continue
                }

                if let local = localTaskMap[rowID] {
                    let remoteUpdated = iso.date(from: row.updated_at) ?? .distantPast
                    if remoteUpdated > local.updatedAt {
                        local.title        = row.title
                        local.isCompleted  = row.is_completed
                        local.priorityRaw  = row.priority_raw
                        local.tagsRaw      = row.tags_raw
                        local.order        = row.sort_order
                        local.parentTaskID = row.parent_task_id.flatMap { UUID(uuidString: $0) }
                        local.dueDate      = row.due_date.flatMap { iso.date(from: $0) }
                        local.updatedAt    = remoteUpdated
                    }
                } else {
                    let task = TodoTaskModel(
                        listID:       listID,
                        parentTaskID: row.parent_task_id.flatMap { UUID(uuidString: $0) },
                        title:        row.title,
                        order:        row.sort_order
                    )
                    task.id          = rowID
                    task.isCompleted = row.is_completed
                    task.priorityRaw = row.priority_raw
                    task.tagsRaw     = row.tags_raw
                    task.dueDate     = row.due_date.flatMap { iso.date(from: $0) }
                    task.createdAt   = iso.date(from: row.created_at) ?? Date()
                    task.updatedAt   = iso.date(from: row.updated_at) ?? Date()
                    context.insert(task)
                }
            }

            try? context.save()

        } catch {
            print("⚠️ TodoTask pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Flush offline queue

    func flushQueue() async {
        guard network.isConnected, !queue.isEmpty else { return }

        for operation in queue.all() {
            var succeeded = false

            switch operation.type {
            case .upsertTodoList:
                if let row = try? JSONDecoder().decode(DBTodoListRow.self, from: operation.payload) {
                    do {
                        try await supabase
                            .from("todo_lists")
                            .upsert(row, onConflict: "id")
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush todo list upsert failed: \(error.localizedDescription)")
                    }
                }

            case .deleteTodoList:
                if let payload = try? JSONDecoder().decode(ListDeletePayload.self,
                                                           from: operation.payload) {
                    do {
                        try await supabase
                            .from("todo_lists")
                            .update(ListDeleteUpdate(is_deleted: true, updated_at: payload.updated_at))
                            .eq("id",      value: payload.id)
                            .eq("user_id", value: payload.user_id)
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush todo list delete failed: \(error.localizedDescription)")
                    }
                }

            case .upsertTodoTask:
                if let row = try? JSONDecoder().decode(DBTodoTaskRow.self, from: operation.payload) {
                    do {
                        try await supabase
                            .from("todo_tasks")
                            .upsert(row, onConflict: "id")
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush todo task upsert failed: \(error.localizedDescription)")
                    }
                }

            case .deleteTodoTask:
                if let payload = try? JSONDecoder().decode(TaskDeletePayload.self,
                                                           from: operation.payload) {
                    do {
                        try await supabase
                            .from("todo_tasks")
                            .update(TaskDeleteUpdate(is_deleted: true, updated_at: payload.updated_at))
                            .eq("id",      value: payload.id)
                            .eq("user_id", value: payload.user_id)
                            .execute()
                        succeeded = true
                    } catch {
                        print("⚠️ Queue flush todo task delete failed: \(error.localizedDescription)")
                    }
                }

            default:
                break
            }

            if succeeded { queue.remove(id: operation.id) }
        }
    }

    // MARK: - Helpers

    private func makeListRow(list: TodoListModel, userID: String) -> DBTodoListRow {
        let now = iso.string(from: Date())
        return DBTodoListRow(
            id:         list.id.uuidString,
            canvas_id:  list.canvasID.uuidString,
            user_id:    userID,
            title:      list.title,
            x:          list.x,
            y:          list.y,
            width:      list.width,
            height:     list.height,
            color_name: list.colorName,
            z_index:    list.zIndex,
            created_at: iso.string(from: list.createdAt),
            updated_at: now,
            is_deleted: false
        )
    }

    private func makeTaskRow(task: TodoTaskModel, userID: String) -> DBTodoTaskRow {
        let now = iso.string(from: Date())
        return DBTodoTaskRow(
            id:             task.id.uuidString,
            list_id:        task.listID.uuidString,
            user_id:        userID,
            parent_task_id: task.parentTaskID?.uuidString,
            title:          task.title,
            is_completed:   task.isCompleted,
            priority_raw:   task.priorityRaw,
            due_date:       task.dueDate.map { iso.string(from: $0) },
            tags_raw:       task.tagsRaw,
            sort_order:     task.order,
            created_at:     iso.string(from: task.createdAt),
            updated_at:     now,
            is_deleted:     false
        )
    }
}
