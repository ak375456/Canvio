//
//  TodoListViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import Combine

@MainActor
class TodoListViewModel: ObservableObject {
    @Published var editingID: UUID? = nil

    func addList(canvasID: UUID, center: CGPoint, offset: CGSize,
                 scale: CGFloat, zIndex: Int, context: ModelContext,
                 undoManager: CanvasUndoManager? = nil) {
        let x = (center.x - offset.width) / scale
        let y = (center.y - offset.height) / scale
        let list = TodoListModel(canvasID: canvasID, x: x, y: y)
        list.zIndex = zIndex
        context.insert(list); try? context.save()
        editingID = list.id

        Task { await TodoSyncService.shared.upsertList(list) }

        let id = list.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TodoListModel>()).first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await TodoSyncService.shared.deleteList(el, tasks: []) }
                }
            },
            redo: {
                let el = TodoListModel(canvasID: canvasID, x: x, y: y)
                el.id = id; el.zIndex = zIndex
                context.insert(el); try? context.save()
                Task { await TodoSyncService.shared.upsertList(el) }
            }
        ))
    }

    func updatePosition(list: TodoListModel, translation: CGSize,
                        scale: CGFloat = 1, boundary: CGSize = .zero,
                        context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldX = list.x, oldY = list.y
        let newX = list.x + Double(translation.width)
        let newY = list.y + Double(translation.height)
        let clamped = CanvasBoundaryHelper.clamp(x: newX, y: newY, boundary: boundary,
                                                  elementSize: CGSize(width: list.width, height: list.height))
        list.x = clamped.x; list.y = clamped.y
        list.updatedAt = Date(); try? context.save()
        Task { await TodoSyncService.shared.upsertList(list) }

        let id = list.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TodoListModel>()).first(where: { $0.id == id }) {
                    el.x = oldX; el.y = oldY; el.updatedAt = Date(); try? context.save()
                    Task { await TodoSyncService.shared.upsertList(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<TodoListModel>()).first(where: { $0.id == id }) {
                    el.x = clamped.x; el.y = clamped.y; el.updatedAt = Date(); try? context.save()
                    Task { await TodoSyncService.shared.upsertList(el) }
                }
            }
        ))
    }

    @discardableResult
    func duplicate(list: TodoListModel, zIndex: Int,
                   offset: CGSize = CGSize(width: 30, height: 30),
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) -> UUID? {
        let copy = TodoListModel(canvasID: list.canvasID,
                                 x: list.x + Double(offset.width),
                                 y: list.y + Double(offset.height))
        copy.title = list.title; copy.colorName = list.colorName
        copy.width = list.width; copy.height = list.height; copy.zIndex = zIndex
        context.insert(copy); try? context.save()
        Task { await TodoSyncService.shared.upsertList(copy) }

        let id = copy.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TodoListModel>()).first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await TodoSyncService.shared.deleteList(el, tasks: []) }
                }
            },
            redo: {
                let el = TodoListModel(canvasID: list.canvasID,
                                       x: list.x + Double(offset.width),
                                       y: list.y + Double(offset.height))
                el.id = id; el.zIndex = zIndex
                context.insert(el); try? context.save()
                Task { await TodoSyncService.shared.upsertList(el) }
            }
        ))
        return id
    }

    func updateTitle(list: TodoListModel, title: String, context: ModelContext) {
        list.title = title; list.updatedAt = Date(); try? context.save()
        Task { await TodoSyncService.shared.upsertList(list) }
    }

    func updateColor(list: TodoListModel, colorName: String, context: ModelContext) {
        list.colorName = colorName; list.updatedAt = Date(); try? context.save()
        Task { await TodoSyncService.shared.upsertList(list) }
    }

    func updateSize(list: TodoListModel, width: Double, height: Double,
                    context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldW = list.width, oldH = list.height
        list.width = max(220, min(800, width)); list.height = max(180, min(1000, height))
        list.updatedAt = Date(); try? context.save()
        Task { await TodoSyncService.shared.upsertList(list) }

        let id = list.id; let newW = list.width, newH = list.height
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TodoListModel>()).first(where: { $0.id == id }) {
                    el.width = oldW; el.height = oldH; el.updatedAt = Date(); try? context.save()
                    Task { await TodoSyncService.shared.upsertList(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<TodoListModel>()).first(where: { $0.id == id }) {
                    el.width = newW; el.height = newH; el.updatedAt = Date(); try? context.save()
                    Task { await TodoSyncService.shared.upsertList(el) }
                }
            }
        ))
    }

    // MARK: - Task CRUD

    func addTask(to list: TodoListModel, existingCount: Int, context: ModelContext) -> TodoTaskModel {
        let task = TodoTaskModel(listID: list.id, title: "", order: existingCount)
        context.insert(task); try? context.save()
        Task { await TodoSyncService.shared.upsertTask(task) }
        return task
    }

    func toggleTask(_ task: TodoTaskModel, context: ModelContext) {
        task.isCompleted.toggle(); task.updatedAt = Date(); try? context.save()
        Task { await TodoSyncService.shared.upsertTask(task) }
    }

    func deleteTask(_ task: TodoTaskModel, subtasks: [TodoTaskModel], context: ModelContext) {
        // Soft-delete subtasks in Supabase first
        for sub in subtasks {
            Task { await TodoSyncService.shared.deleteTask(sub) }
            context.delete(sub)
        }
        Task { await TodoSyncService.shared.deleteTask(task) }
        context.delete(task); try? context.save()
    }

    func delete(list: TodoListModel, tasks: [TodoTaskModel], context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snap = (id: list.id, canvasID: list.canvasID, title: list.title,
                    x: list.x, y: list.y, width: list.width, height: list.height,
                    colorName: list.colorName, zIndex: list.zIndex)

        // Soft-delete tasks + list in Supabase
        Task { await TodoSyncService.shared.deleteList(list, tasks: tasks) }

        tasks.forEach { context.delete($0) }
        context.delete(list); try? context.save()
        if editingID == snap.id { editingID = nil }

        undoManager?.push(CanvasAction(
            undo: {
                let el = TodoListModel(canvasID: snap.canvasID, x: snap.x, y: snap.y)
                el.id = snap.id; el.title = snap.title; el.colorName = snap.colorName
                el.width = snap.width; el.height = snap.height; el.zIndex = snap.zIndex
                context.insert(el); try? context.save()
                Task { await TodoSyncService.shared.upsertList(el) }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<TodoListModel>()).first(where: { $0.id == snap.id }) {
                    context.delete(el); try? context.save()
                    Task { await TodoSyncService.shared.deleteList(el, tasks: []) }
                }
            }
        ))
    }

    func stopEditing() { editingID = nil }
}
