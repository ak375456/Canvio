//
//  LayersViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import Combine

private struct LayerZHistoryState: Equatable {
    let id: UUID
    let zIndex: Int
}

@MainActor
class LayersViewModel: ObservableObject {
    @Published var highlightedID: UUID? = nil

    // MARK: - Generic z-index operations
    func bringForward(_ element: any LayerableElement,
                      in allElements: [any LayerableElement],
                      context: ModelContext,
                      undoManager: CanvasUndoManager? = nil) {
        let before = zState(for: allElements)
        let sorted = sortedByZ(allElements)
        guard let idx = sorted.firstIndex(where: { $0.id == element.id }),
              idx < sorted.count - 1 else { return }
        let above = sorted[idx + 1]
        swapZ(element, above, context: context)
        recordZChange(
            name: "Bring layer forward", before: before,
            elements: allElements, context: context, undoManager: undoManager
        )
    }

    func sendBackward(_ element: any LayerableElement,
                      in allElements: [any LayerableElement],
                      context: ModelContext,
                      undoManager: CanvasUndoManager? = nil) {
        let before = zState(for: allElements)
        let sorted = sortedByZ(allElements)
        guard let idx = sorted.firstIndex(where: { $0.id == element.id }),
              idx > 0 else { return }
        let below = sorted[idx - 1]
        swapZ(element, below, context: context)
        recordZChange(
            name: "Send layer backward", before: before,
            elements: allElements, context: context, undoManager: undoManager
        )
    }

    func bringToFront(_ element: any LayerableElement,
                      in allElements: [any LayerableElement],
                      context: ModelContext,
                      undoManager: CanvasUndoManager? = nil) {
        let before = zState(for: allElements)
        let maxZ = allElements.map { $0.zIndex }.max() ?? 0
        guard element.zIndex < maxZ else { return }
        element.zIndex = maxZ + 1
        element.updatedAt = Date()
        try? context.save()
        Task { await CanvasElementSyncRouter.upsert(element) }
        recordZChange(
            name: "Bring layer to front", before: before,
            elements: allElements, context: context, undoManager: undoManager
        )
    }

    func sendToBack(_ element: any LayerableElement,
                    in allElements: [any LayerableElement],
                    context: ModelContext,
                    undoManager: CanvasUndoManager? = nil) {
        let before = zState(for: allElements)
        let minZ = allElements.map { $0.zIndex }.min() ?? 0
        guard element.zIndex > minZ else { return }
        element.zIndex = minZ - 1
        element.updatedAt = Date()
        try? context.save()
        Task { await CanvasElementSyncRouter.upsert(element) }
        recordZChange(
            name: "Send layer to back", before: before,
            elements: allElements, context: context, undoManager: undoManager
        )
    }

    /// Reorder by setting z-indices to match the order of `orderedElements`
    /// (bottom of array = bottom of stack).
    func reorder(_ orderedElements: [any LayerableElement], context: ModelContext,
                 undoManager: CanvasUndoManager? = nil) {
        let changedElements = orderedElements.enumerated().compactMap { index, element in
            element.zIndex == index ? nil : element
        }
        guard !changedElements.isEmpty else { return }

        let before = zState(for: changedElements)
        let changedIDs = Set(changedElements.map(\.id))
        let now = Date()

        for (i, el) in orderedElements.enumerated() where changedIDs.contains(el.id) {
            el.zIndex = i
            el.updatedAt = now
        }
        try? context.save()
        Task {
            for element in changedElements {
                await CanvasElementSyncRouter.upsert(element)
            }
        }
        recordZChange(
            name: "Reorder layers", before: before,
            elements: changedElements, context: context, undoManager: undoManager
        )
    }

    func highlight(_ id: UUID) {
        highlightedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.highlightedID == id { self?.highlightedID = nil }
        }
    }

    // MARK: - Helpers
    private func sortedByZ(_ elements: [any LayerableElement]) -> [any LayerableElement] {
        elements.sorted { $0.zIndex < $1.zIndex }
    }

    private func swapZ(_ a: any LayerableElement, _ b: any LayerableElement, context: ModelContext) {
        let tmp = a.zIndex
        a.zIndex = b.zIndex
        b.zIndex = tmp
        a.updatedAt = Date()
        b.updatedAt = Date()
        try? context.save()
        Task {
            await CanvasElementSyncRouter.upsert(a)
            await CanvasElementSyncRouter.upsert(b)
        }
    }

    private func zState(for elements: [any LayerableElement]) -> [LayerZHistoryState] {
        elements
            .map { LayerZHistoryState(id: $0.id, zIndex: $0.zIndex) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func recordZChange(
        name: String,
        before: [LayerZHistoryState],
        elements: [any LayerableElement],
        context: ModelContext,
        undoManager: CanvasUndoManager?
    ) {
        guard let undoManager else { return }
        let after = zState(for: elements)
        undoManager.recordChange(name: name, from: before, to: after) { state in
            var changed: [any LayerableElement] = []
            for item in state {
                guard let element = CanvasElementHistoryLookup.element(
                    withID: item.id,
                    context: context
                ) else { continue }
                element.zIndex = item.zIndex
                element.updatedAt = Date()
                changed.append(element)
            }
            try? context.save()
            Task {
                for element in changed {
                    await CanvasElementSyncRouter.upsert(element)
                }
            }
        }
    }

    /// Assign initial z-index for a newly added element (top of stack)
    static func nextZ(among elements: [any LayerableElement]) -> Int {
        (elements.map { $0.zIndex }.max() ?? 0) + 1
    }
}
