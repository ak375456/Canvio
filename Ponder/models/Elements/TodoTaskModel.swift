//
//  TodoTaskModel.swift
//  Ponder
//
//  Created by aftab fazal qayum on 11/05/2026.
//

//
//  TodoTaskModel.swift
//  Ponder
//

import Foundation
import SwiftData

@Model
class TodoTaskModel {
    var id: UUID
    var listID: UUID
    var parentTaskID: UUID?     // nil = top-level task, else subtask
    var title: String
    var isCompleted: Bool
    var priorityRaw: String
    var dueDate: Date?
    var tagsRaw: String         // comma-separated for simplicity
    var order: Int              // for manual sorting within list
    var createdAt: Date
    var updatedAt: Date

    var priority: TodoPriority {
        get { TodoPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var tags: [String] {
        get {
            tagsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsRaw = newValue.joined(separator: ", ")
        }
    }

    init(listID: UUID, parentTaskID: UUID? = nil, title: String = "", order: Int = 0) {
        self.id = UUID()
        self.listID = listID
        self.parentTaskID = parentTaskID
        self.title = title
        self.isCompleted = false
        self.priorityRaw = TodoPriority.none.rawValue
        self.dueDate = nil
        self.tagsRaw = ""
        self.order = order
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
