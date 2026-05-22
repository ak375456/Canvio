//
//  CanvasUndoManager.swift
//  Ponder
//

import Foundation
import Combine

struct CanvasAction {
    let undo: () -> Void
    let redo: () -> Void
}

@MainActor
class CanvasUndoManager: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var undoStack: [CanvasAction] = []
    private var redoStack: [CanvasAction] = []
    private let maxStackSize = 50

    func push(_ action: CanvasAction) {
        undoStack.append(action)
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateFlags()
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        action.undo()
        redoStack.append(action)
        updateFlags()
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }
        action.redo()
        undoStack.append(action)
        updateFlags()
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        updateFlags()
    }

    private func updateFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
