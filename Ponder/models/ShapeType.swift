//
//  ShapeType.swift
//  Ponder
//

import SwiftUI

enum ShapeKind: String, Codable, CaseIterable, Identifiable {
    case line
    case rectangle
    case triangle
    case polygon
    case circle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line:      return "Line"
        case .rectangle: return "Rectangle"
        case .triangle:  return "Triangle"
        case .polygon:   return "Polygon"
        case .circle:    return "Circle"
        }
    }

    var icon: String {
        switch self {
        case .line:      return "line.diagonal"
        case .rectangle: return "rectangle"
        case .triangle:  return "triangle"
        case .polygon:   return "hexagon"
        case .circle:    return "circle"
        }
    }

    var supportsFill: Bool {
        switch self {
        case .line:    return false
        default:       return true
        }
    }
}

enum TriangleVariant: String, Codable, CaseIterable, Identifiable {
    case equilateral
    case rightAngled
    case isosceles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equilateral: return "Equilateral"
        case .rightAngled: return "Right"
        case .isosceles:   return "Isosceles"
        }
    }
}
