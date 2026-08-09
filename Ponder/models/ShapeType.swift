//
//  ShapeType.swift
//  Ponder
//

import SwiftUI

enum ShapeKind: String, Codable, CaseIterable, Identifiable {
    case line
    case rectangle
    case roundedRectangle
    case triangle
    case polygon
    case circle
    case ellipse
    case diamond
    case star
    case speechBubble
    case cloud
    case parallelogram
    case cylinder
    case document
    case terminator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line:             return "Line"
        case .rectangle:        return "Rectangle"
        case .roundedRectangle: return "Rounded Rectangle"
        case .triangle:         return "Triangle"
        case .polygon:          return "Polygon"
        case .circle:           return "Circle"
        case .ellipse:          return "Ellipse"
        case .diamond:          return "Diamond"
        case .star:             return "Star"
        case .speechBubble:     return "Speech Bubble"
        case .cloud:            return "Cloud"
        case .parallelogram:    return "Data"
        case .cylinder:         return "Database"
        case .document:         return "Document"
        case .terminator:       return "Terminator"
        }
    }

    var icon: String {
        switch self {
        case .line:             return "line.diagonal"
        case .rectangle:        return "rectangle"
        case .roundedRectangle: return "rectangle.roundedtop"
        case .triangle:         return "triangle"
        case .polygon:          return "hexagon"
        case .circle:           return "circle"
        case .ellipse:          return "oval"
        case .diamond:          return "diamond"
        case .star:             return "star"
        case .speechBubble:     return "bubble.left"
        case .cloud:            return "cloud"
        case .parallelogram:    return "rhombus"
        case .cylinder:         return "cylinder"
        case .document:         return "doc"
        case .terminator:       return "capsule"
        }
    }

    var supportsFill: Bool {
        switch self {
        case .line:    return false
        default:       return true
        }
    }
}

enum ShapeLineEnding: String, Codable, CaseIterable, Identifiable {
    case none
    case start
    case end
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:  return "No Arrows"
        case .start: return "Arrow at Start"
        case .end:   return "Arrow at End"
        case .both:  return "Arrows at Both Ends"
        }
    }

    var icon: String {
        switch self {
        case .none:  return "minus"
        case .start: return "arrow.left"
        case .end:   return "arrow.right"
        case .both:  return "arrow.left.and.right"
        }
    }

    var includesStart: Bool { self == .start || self == .both }
    var includesEnd: Bool { self == .end || self == .both }
}

enum ShapeLineStyle: String, Codable, CaseIterable, Identifiable {
    case solid
    case dashed
    case dotted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid:  return "Solid"
        case .dashed: return "Dashed"
        case .dotted: return "Dotted"
        }
    }

    var icon: String {
        switch self {
        case .solid:  return "line.diagonal"
        case .dashed: return "line.horizontal.3"
        case .dotted: return "ellipsis"
        }
    }

    func dashPattern(for strokeWidth: CGFloat) -> [CGFloat] {
        switch self {
        case .solid:  return []
        case .dashed: return [max(7, strokeWidth * 3), max(5, strokeWidth * 2)]
        case .dotted: return [0.1, max(5, strokeWidth * 2.2)]
        }
    }
}

enum ShapeCategory: String, CaseIterable, Identifiable {
    case basic = "Basic"
    case lines = "Lines"
    case flowchart = "Flowchart"
    case callouts = "Callouts & Highlights"

    var id: String { rawValue }
}

struct ShapePreset: Identifiable {
    let id: String
    let title: String
    let icon: String
    let category: ShapeCategory
    let kind: ShapeKind
    var triangleVariant: TriangleVariant? = nil
    var polygonSides: Int? = nil
    var lineEnding: ShapeLineEnding? = nil
    var lineStyle: ShapeLineStyle? = nil

    static let all: [ShapePreset] = [
        ShapePreset(id: "rectangle", title: "Rectangle", icon: "rectangle", category: .basic, kind: .rectangle),
        ShapePreset(id: "rounded-rectangle", title: "Rounded", icon: "rectangle.roundedtop", category: .basic, kind: .roundedRectangle),
        ShapePreset(id: "circle", title: "Circle", icon: "circle", category: .basic, kind: .circle),
        ShapePreset(id: "ellipse", title: "Ellipse", icon: "oval", category: .basic, kind: .ellipse),
        ShapePreset(id: "triangle-equilateral", title: "Triangle", icon: "triangle", category: .basic, kind: .triangle, triangleVariant: .equilateral),
        ShapePreset(id: "triangle-right", title: "Right Triangle", icon: "triangle", category: .basic, kind: .triangle, triangleVariant: .rightAngled),
        ShapePreset(id: "triangle-isosceles", title: "Isosceles", icon: "triangle", category: .basic, kind: .triangle, triangleVariant: .isosceles),
        ShapePreset(id: "polygon-5", title: "Pentagon", icon: "pentagon", category: .basic, kind: .polygon, polygonSides: 5),
        ShapePreset(id: "polygon-6", title: "Hexagon", icon: "hexagon", category: .basic, kind: .polygon, polygonSides: 6),
        ShapePreset(id: "polygon-8", title: "Octagon", icon: "octagon", category: .basic, kind: .polygon, polygonSides: 8),

        ShapePreset(id: "line", title: "Line", icon: "minus", category: .lines, kind: .line, lineEnding: ShapeLineEnding.none, lineStyle: .solid),
        ShapePreset(id: "arrow", title: "Arrow", icon: "arrow.right", category: .lines, kind: .line, lineEnding: .end, lineStyle: .solid),
        ShapePreset(id: "double-arrow", title: "Double Arrow", icon: "arrow.left.and.right", category: .lines, kind: .line, lineEnding: .both, lineStyle: .solid),
        ShapePreset(id: "dashed-line", title: "Dashed Line", icon: "line.horizontal.3", category: .lines, kind: .line, lineEnding: ShapeLineEnding.none, lineStyle: .dashed),

        ShapePreset(id: "diamond", title: "Decision", icon: "diamond", category: .flowchart, kind: .diamond),
        ShapePreset(id: "parallelogram", title: "Data", icon: "rhombus", category: .flowchart, kind: .parallelogram),
        ShapePreset(id: "cylinder", title: "Database", icon: "cylinder", category: .flowchart, kind: .cylinder),
        ShapePreset(id: "document", title: "Document", icon: "doc", category: .flowchart, kind: .document),
        ShapePreset(id: "terminator", title: "Terminator", icon: "capsule", category: .flowchart, kind: .terminator),

        ShapePreset(id: "speech-bubble", title: "Speech Bubble", icon: "bubble.left", category: .callouts, kind: .speechBubble),
        ShapePreset(id: "cloud", title: "Cloud", icon: "cloud", category: .callouts, kind: .cloud),
        ShapePreset(id: "star", title: "Star", icon: "star", category: .callouts, kind: .star)
    ]

    static func presets(in category: ShapeCategory) -> [ShapePreset] {
        all.filter { $0.category == category }
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
