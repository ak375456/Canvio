//
//  CanvasUndoManager.swift
//  Ponder
//

import Foundation
import Combine
import SwiftData

struct CanvasAction {
    let name: String
    let coalescingKey: String?
    let undo: () -> Void
    let redo: () -> Void
    let onDiscard: ((Bool) -> Void)?

    init(
        name: String = "Canvas change",
        coalescingKey: String? = nil,
        undo: @escaping () -> Void,
        redo: @escaping () -> Void,
        onDiscard: ((Bool) -> Void)? = nil
    ) {
        self.name = name
        self.coalescingKey = coalescingKey
        self.undo = undo
        self.redo = redo
        self.onDiscard = onDiscard
    }
}

@MainActor
final class CanvasUndoManager: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var undoStack: [CanvasAction] = []
    private var redoStack: [CanvasAction] = []
    private let maxStackSize = 50
    private let coalescingInterval: TimeInterval = 0.7
    private var lastPushDate = Date.distantPast
    private var groupedActions: [CanvasAction]?
    private var groupName = "Canvas change"
    private var groupingDepth = 0

    func push(_ action: CanvasAction) {
        if groupedActions != nil {
            groupedActions?.append(action)
            return
        }
        pushResolved(action)
    }

    func beginGrouping(name: String) {
        if groupedActions != nil {
            groupingDepth += 1
            return
        }
        groupName = name
        groupedActions = []
        groupingDepth = 1
    }

    func endGrouping() {
        guard groupingDepth > 0 else { return }
        groupingDepth -= 1
        guard groupingDepth == 0 else { return }
        guard let actions = groupedActions else { return }
        groupedActions = nil
        guard !actions.isEmpty else { return }
        guard actions.count > 1 else {
            pushResolved(actions[0])
            return
        }
        pushResolved(CanvasAction(
            name: groupName,
            undo: {
                for action in actions.reversed() {
                    action.undo()
                }
            },
            redo: {
                for action in actions {
                    action.redo()
                }
            },
            onDiscard: { isApplied in
                for action in actions {
                    action.onDiscard?(isApplied)
                }
            }
        ))
    }

    private func pushResolved(_ action: CanvasAction) {
        let now = Date()
        if let key = action.coalescingKey,
           now.timeIntervalSince(lastPushDate) <= coalescingInterval,
           let previous = undoStack.last,
           previous.coalescingKey == key {
            undoStack[undoStack.count - 1] = CanvasAction(
                name: action.name,
                coalescingKey: key,
                undo: previous.undo,
                redo: action.redo,
                onDiscard: action.onDiscard ?? previous.onDiscard
            )
        } else {
            undoStack.append(action)
        }

        if undoStack.count > maxStackSize {
            let discarded = undoStack.prefix(undoStack.count - maxStackSize)
            discarded.forEach { $0.onDiscard?(true) }
            undoStack.removeFirst(undoStack.count - maxStackSize)
        }
        redoStack.forEach { $0.onDiscard?(false) }
        redoStack.removeAll()
        lastPushDate = now
        updateFlags()
    }

    /// Records only the old and new value plus the element identifier. This
    /// keeps ordinary edits lightweight and still survives delete/restore
    /// cycles because replay resolves the current model instance by UUID.
    func recordElementChange<Element: LayerableElement, Value: Equatable>(
        name: String,
        element: Element,
        from oldValue: Value,
        to newValue: Value,
        context: ModelContext,
        coalescingKey: String? = nil,
        apply: @escaping (Element, Value) -> Void
    ) {
        guard oldValue != newValue else { return }

        let elementID = element.id
        let replay: (Value) -> Void = { value in
            guard let current = CanvasElementHistoryLookup.element(
                withID: elementID,
                context: context
            ) as? Element else { return }
            apply(current, value)
            current.updatedAt = Date()
            try? context.save()
            Task { await CanvasElementSyncRouter.upsert(current) }
        }

        push(CanvasAction(
            name: name,
            coalescingKey: coalescingKey,
            undo: { replay(oldValue) },
            redo: { replay(newValue) }
        ))
    }

    func recordChange<Value: Equatable>(
        name: String,
        from oldValue: Value,
        to newValue: Value,
        coalescingKey: String? = nil,
        apply: @escaping (Value) -> Void
    ) {
        guard oldValue != newValue else { return }
        push(CanvasAction(
            name: name,
            coalescingKey: coalescingKey,
            undo: { apply(oldValue) },
            redo: { apply(newValue) }
        ))
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        action.undo()
        redoStack.append(action)
        lastPushDate = .distantPast
        updateFlags()
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }
        action.redo()
        undoStack.append(action)
        lastPushDate = .distantPast
        updateFlags()
    }

    func clear() {
        undoStack.forEach { $0.onDiscard?(true) }
        redoStack.forEach { $0.onDiscard?(false) }
        undoStack.removeAll()
        redoStack.removeAll()
        groupedActions = nil
        groupingDepth = 0
        lastPushDate = .distantPast
        updateFlags()
    }

    private func updateFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}

@MainActor
enum CanvasElementHistoryLookup {
    static func element(withID id: UUID, context: ModelContext) -> (any LayerableElement)? {
        if let value = fetch(TextElementModel.self, id: id, context: context) { return value }
        if let value = fetch(StickyNoteModel.self, id: id, context: context) { return value }
        if let value = fetch(TodoListModel.self, id: id, context: context) { return value }
        if let value = fetch(ShapeElementModel.self, id: id, context: context) { return value }
        if let value = fetch(ImageElementModel.self, id: id, context: context) { return value }
        if let value = fetch(PDFElementModel.self, id: id, context: context) { return value }
        if let value = fetch(PDFPageElementModel.self, id: id, context: context) { return value }
        if let value = fetch(TableElementModel.self, id: id, context: context) { return value }
        if let value = fetch(AudioElementModel.self, id: id, context: context) { return value }
        if let value = fetch(YouTubeElementModel.self, id: id, context: context) { return value }
        if let value = fetch(DrawingElementModel.self, id: id, context: context) { return value }
        if let value = fetch(SymbolElementModel.self, id: id, context: context) { return value }
        return nil
    }

    private static func fetch<Model: PersistentModel & LayerableElement>(
        _ type: Model.Type,
        id: UUID,
        context: ModelContext
    ) -> Model? {
        guard let values = try? context.fetch(FetchDescriptor<Model>()) else { return nil }
        return values.first { $0.id == id }
    }
}
