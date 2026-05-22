//
//  SelectionViewModel.swift
//  Ponder
//

import SwiftUI
import Combine

@MainActor
class SelectionViewModel: ObservableObject {
    @Published var isMultiSelectActive = false
    @Published var selectedIDs: Set<UUID> = []

    var count: Int { selectedIDs.count }
    var hasSelection: Bool { !selectedIDs.isEmpty }

    func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }

    func select(_ id: UUID) { selectedIDs.insert(id) }

    func isSelected(_ id: UUID) -> Bool { selectedIDs.contains(id) }

    func enterMultiSelect() {
        isMultiSelectActive = true
        selectedIDs.removeAll()
    }

    func exit() {
        isMultiSelectActive = false
        selectedIDs.removeAll()
    }
}
