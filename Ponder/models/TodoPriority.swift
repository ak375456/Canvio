//
//  TodoPriority.swift
//  Ponder
//
//  Created by aftab fazal qayum on 11/05/2026.
//

//
//  TodoPriority.swift
//  Ponder
//

import SwiftUI

enum TodoPriority: String, Codable, CaseIterable, Identifiable {
    case none
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    var color: Color {
        switch self {
        case .none:   return .gray.opacity(0.4)
        case .low:    return .blue
        case .medium: return .orange
        case .high:   return .red
        }
    }

    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        case .none: return 3
        }
    }
}
