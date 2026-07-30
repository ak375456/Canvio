//
//  TodoListViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import Combine

struct TodoTaskHistoryState: Equatable {
    let id: UUID
    let listID: UUID
    let parentTaskID: UUID?
    let title: String
    let isCompleted: Bool
    let priorityRaw: String
    let dueDate: Date?
    let tagsRaw: String
    let order: Int

    init(_ task: TodoTaskModel) {
        id = task.id
        listID = task.listID
        parentTaskID = task.parentTaskID
        title = task.title
        isCompleted = task.isCompleted
        priorityRaw = task.priorityRaw
        dueDate = task.dueDate
        tagsRaw = task.tagsRaw
        order = task.order
    }

    func apply(to task: TodoTaskModel) {
        task.parentTaskID = parentTaskID
        task.title = title
        task.isCompleted = isCompleted
        task.priorityRaw = priorityRaw
        task.dueDate = dueDate
        task.tagsRaw = tagsRaw
        task.order = order
        task.updatedAt = Date()
    }

    func makeModel() -> TodoTaskModel {
        let task = TodoTaskModel(
            listID: listID,
            parentTaskID: parentTaskID,
            title: title,
            order: order
        )
        task.id = id
        apply(to: task)
        return task
    }
}

@MainActor
func recordTodoTaskChange(
    name: String,
    task: TodoTaskModel,
    from oldState: TodoTaskHistoryState,
    context: ModelContext,
    undoManager: CanvasUndoManager,
    coalescingKey: String? = nil
) {
    let newState = TodoTaskHistoryState(task)
    let id = task.id
    undoManager.recordChange(
        name: name,
        from: oldState,
        to: newState,
        coalescingKey: coalescingKey
    ) { state in
        guard let values = try? context.fetch(FetchDescriptor<TodoTaskModel>()),
              let current = values.first(where: { $0.id == id }) else { return }
        state.apply(to: current)
        try? context.save()
        Task { await TodoSyncService.shared.upsertTask(current) }
    }
}

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

    func updateTitle(list: TodoListModel, title: String, context: ModelContext,
                     undoManager: CanvasUndoManager? = nil) {
        let oldValue = list.title
        list.title = title; list.updatedAt = Date(); try? context.save()
        Task { await TodoSyncService.shared.upsertList(list) }
        undoManager?.recordElementChange(
            name: "Rename todo list", element: list,
            from: oldValue, to: list.title, context: context
        ) { $0.title = $1 }
    }

    func updateColor(list: TodoListModel, colorName: String, context: ModelContext,
                     undoManager: CanvasUndoManager? = nil) {
        let oldValue = list.colorName
        list.colorName = colorName; list.updatedAt = Date(); try? context.save()
        Task { await TodoSyncService.shared.upsertList(list) }
        undoManager?.recordElementChange(
            name: "Change todo color", element: list,
            from: oldValue, to: list.colorName, context: context
        ) { $0.colorName = $1 }
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

    func addTask(to list: TodoListModel, existingCount: Int, context: ModelContext,
                 undoManager: CanvasUndoManager? = nil) -> TodoTaskModel {
        let task = TodoTaskModel(listID: list.id, title: "", order: existingCount)
        context.insert(task); try? context.save()
        Task { await TodoSyncService.shared.upsertTask(task) }
        let snapshot = TodoTaskHistoryState(task)
        undoManager?.push(CanvasAction(
            name: "Add todo task",
            undo: {
                guard let values = try? context.fetch(FetchDescriptor<TodoTaskModel>()),
                      let current = values.first(where: { $0.id == snapshot.id }) else { return }
                context.delete(current)
                try? context.save()
                Task { await TodoSyncService.shared.deleteTask(current) }
            },
            redo: {
                let restored = snapshot.makeModel()
                context.insert(restored)
                try? context.save()
                Task { await TodoSyncService.shared.upsertTask(restored) }
            }
        ))
        return task
    }

    func toggleTask(_ task: TodoTaskModel, context: ModelContext,
                    undoManager: CanvasUndoManager? = nil) {
        let oldState = TodoTaskHistoryState(task)
        task.isCompleted.toggle(); task.updatedAt = Date(); try? context.save()
        Task { await TodoSyncService.shared.upsertTask(task) }
        if let undoManager {
            recordTodoTaskChange(
                name: "Toggle todo task",
                task: task,
                from: oldState,
                context: context,
                undoManager: undoManager
            )
        }
    }

    func deleteTask(_ task: TodoTaskModel, subtasks: [TodoTaskModel], context: ModelContext,
                    undoManager: CanvasUndoManager? = nil) {
        let snapshots = ([task] + subtasks).map(TodoTaskHistoryState.init)
        // Soft-delete subtasks in Supabase first
        for sub in subtasks {
            Task { await TodoSyncService.shared.deleteTask(sub) }
            context.delete(sub)
        }
        Task { await TodoSyncService.shared.deleteTask(task) }
        context.delete(task); try? context.save()
        undoManager?.push(CanvasAction(
            name: "Delete todo task",
            undo: {
                for snapshot in snapshots {
                    let restored = snapshot.makeModel()
                    context.insert(restored)
                    Task { await TodoSyncService.shared.upsertTask(restored) }
                }
                try? context.save()
            },
            redo: {
                guard let values = try? context.fetch(FetchDescriptor<TodoTaskModel>()) else { return }
                let ids = Set(snapshots.map(\.id))
                for current in values where ids.contains(current.id) {
                    Task { await TodoSyncService.shared.deleteTask(current) }
                    context.delete(current)
                }
                try? context.save()
            }
        ))
    }

    func delete(list: TodoListModel, tasks: [TodoTaskModel], context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snap = (id: list.id, canvasID: list.canvasID, title: list.title,
                    x: list.x, y: list.y, width: list.width, height: list.height,
                    colorName: list.colorName, zIndex: list.zIndex,
                    groupID: list.groupID, isLayerHidden: list.isLayerHidden,
                    layerOpacity: list.layerOpacity)
        let taskSnapshots = tasks.map(TodoTaskHistoryState.init)

        // Soft-delete tasks + list in Supabase
        Task { await TodoSyncService.shared.deleteList(list, tasks: tasks) }

        tasks.forEach { context.delete($0) }
        context.delete(list); try? context.save()
        if editingID == snap.id { editingID = nil }

        undoManager?.push(CanvasAction(
            name: "Delete todo list",
            undo: {
                let el = TodoListModel(canvasID: snap.canvasID, x: snap.x, y: snap.y)
                el.id = snap.id; el.title = snap.title; el.colorName = snap.colorName
                el.width = snap.width; el.height = snap.height; el.zIndex = snap.zIndex
                el.groupID = snap.groupID; el.isLayerHidden = snap.isLayerHidden
                el.layerOpacity = snap.layerOpacity
                context.insert(el)
                for taskSnapshot in taskSnapshots {
                    context.insert(taskSnapshot.makeModel())
                }
                try? context.save()
                Task { await TodoSyncService.shared.upsertList(el) }
                for taskSnapshot in taskSnapshots {
                    if let values = try? context.fetch(FetchDescriptor<TodoTaskModel>()),
                       let task = values.first(where: { $0.id == taskSnapshot.id }) {
                        Task { await TodoSyncService.shared.upsertTask(task) }
                    }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<TodoListModel>()).first(where: { $0.id == snap.id }) {
                    let currentTasks = (try? context.fetch(FetchDescriptor<TodoTaskModel>()))?
                        .filter { $0.listID == snap.id } ?? []
                    currentTasks.forEach { context.delete($0) }
                    context.delete(el); try? context.save()
                    Task { await TodoSyncService.shared.deleteList(el, tasks: currentTasks) }
                }
            }
        ))
    }

    func stopEditing() { editingID = nil }
}
