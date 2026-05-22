//
//  LayersViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import Combine

@MainActor
class LayersViewModel: ObservableObject {
    @Published var highlightedID: UUID? = nil

    // MARK: - Generic z-index operations
    func bringForward(_ element: any LayerableElement,
                      in allElements: [any LayerableElement],
                      context: ModelContext) {
        let sorted = sortedByZ(allElements)
        guard let idx = sorted.firstIndex(where: { $0.id == element.id }),
              idx < sorted.count - 1 else { return }
        let above = sorted[idx + 1]
        swapZ(element, above, context: context)
    }

    func sendBackward(_ element: any LayerableElement,
                      in allElements: [any LayerableElement],
                      context: ModelContext) {
        let sorted = sortedByZ(allElements)
        guard let idx = sorted.firstIndex(where: { $0.id == element.id }),
              idx > 0 else { return }
        let below = sorted[idx - 1]
        swapZ(element, below, context: context)
    }

    func bringToFront(_ element: any LayerableElement,
                      in allElements: [any LayerableElement],
                      context: ModelContext) {
        let maxZ = allElements.map { $0.zIndex }.max() ?? 0
        guard element.zIndex < maxZ else { return }
        element.zIndex = maxZ + 1
        element.updatedAt = Date()
        try? context.save()
    }

    func sendToBack(_ element: any LayerableElement,
                    in allElements: [any LayerableElement],
                    context: ModelContext) {
        let minZ = allElements.map { $0.zIndex }.min() ?? 0
        guard element.zIndex > minZ else { return }
        element.zIndex = minZ - 1
        element.updatedAt = Date()
        try? context.save()
    }

    /// Reorder by setting z-indices to match the order of `orderedElements`
    /// (bottom of array = bottom of stack).
    func reorder(_ orderedElements: [any LayerableElement], context: ModelContext) {
        for (i, el) in orderedElements.enumerated() {
            el.zIndex = i
            el.updatedAt = Date()
        }
        try? context.save()
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
    }

    /// Assign initial z-index for a newly added element (top of stack)
    static func nextZ(among elements: [any LayerableElement]) -> Int {
        (elements.map { $0.zIndex }.max() ?? 0) + 1
    }
}
