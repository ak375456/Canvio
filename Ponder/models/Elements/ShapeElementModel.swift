//
//  ShapeElementModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ShapeColorOption: Identifiable {
    let name: String
    let title: String
    let color: Color

    var id: String { name }
}

enum ShapeColorPalette {
    static let options: [ShapeColorOption] = [
        ShapeColorOption(name: "primary", title: "Default", color: .primary),
        ShapeColorOption(name: "black", title: "Black", color: .black),
        ShapeColorOption(name: "white", title: "White", color: .white),
        ShapeColorOption(name: "gray", title: "Gray", color: .gray),
        ShapeColorOption(name: "red", title: "Red", color: .red),
        ShapeColorOption(name: "orange", title: "Orange", color: .orange),
        ShapeColorOption(name: "#FF6B4A", title: "Coral", color: Color(red: 1.0, green: 0.42, blue: 0.29)),
        ShapeColorOption(name: "yellow", title: "Yellow", color: .yellow),
        ShapeColorOption(name: "#A3E635", title: "Lime", color: Color(red: 0.64, green: 0.90, blue: 0.21)),
        ShapeColorOption(name: "green", title: "Green", color: .green),
        ShapeColorOption(name: "mint", title: "Mint", color: .mint),
        ShapeColorOption(name: "teal", title: "Teal", color: .teal),
        ShapeColorOption(name: "cyan", title: "Cyan", color: .cyan),
        ShapeColorOption(name: "blue", title: "Blue", color: .blue),
        ShapeColorOption(name: "indigo", title: "Indigo", color: .indigo),
        ShapeColorOption(name: "purple", title: "Purple", color: .purple),
        ShapeColorOption(name: "pink", title: "Pink", color: .pink),
        ShapeColorOption(name: "brown", title: "Brown", color: .brown)
    ]

    static func color(named name: String, fallback: Color = .primary) -> Color {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "none" { return .clear }
        if let option = options.first(where: { $0.name == trimmed }) {
            return option.color
        }
        if let color = colorFromHex(trimmed) {
            return color
        }
        return fallback
    }

    static func title(for name: String) -> String {
        if name == "none" { return "None" }
        if let option = options.first(where: { $0.name == name }) {
            return option.title
        }
        return "Custom"
    }

    static func storageName(for color: Color, fallback: String = "primary") -> String {
        hexString(for: color) ?? fallback
    }

    private static func colorFromHex(_ name: String) -> Color? {
        let raw = name.hasPrefix("#") ? String(name.dropFirst()) : name
        guard raw.count == 6 || raw.count == 8,
              let value = UInt64(raw, radix: 16) else { return nil }

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        if raw.count == 8 {
            red = Double((value & 0xFF000000) >> 24) / 255
            green = Double((value & 0x00FF0000) >> 16) / 255
            blue = Double((value & 0x0000FF00) >> 8) / 255
            alpha = Double(value & 0x000000FF) / 255
        } else {
            red = Double((value & 0xFF0000) >> 16) / 255
            green = Double((value & 0x00FF00) >> 8) / 255
            blue = Double(value & 0x0000FF) / 255
            alpha = 1
        }

        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    private static func hexString(for color: Color) -> String? {
        #if canImport(UIKit)
        let platformColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard platformColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        #elseif canImport(AppKit)
        let platformColor = NSColor(color)
        guard let converted = platformColor.usingColorSpace(.sRGB) else {
            return nil
        }
        let red = converted.redComponent
        let green = converted.greenComponent
        let blue = converted.blueComponent
        let alpha = converted.alphaComponent
        #else
        return nil
        #endif

        let r = Int(round(min(max(red, 0), 1) * 255))
        let g = Int(round(min(max(green, 0), 1) * 255))
        let b = Int(round(min(max(blue, 0), 1) * 255))
        let a = Int(round(min(max(alpha, 0), 1) * 255))

        if a < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

@Model
class ShapeElementModel: LayerableElement {
    var id: UUID
    var canvasID: UUID
    var shapeTypeRaw: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double
    var strokeColorName: String
    var fillColorName: String
    var hasFill: Bool
    var strokeWidth: Double
    var hasArrowHead: Bool
    var triangleVariantRaw: String
    var polygonSides: Int
    var createdAt: Date
    var updatedAt: Date
    var isLayerHidden: Bool = false
    var layerOpacity: Double = 1
    var zIndex: Int = 0
    var groupID: UUID? = nil

    var shapeKind: ShapeKind {
        get { ShapeKind(rawValue: shapeTypeRaw) ?? .rectangle }
        set { shapeTypeRaw = newValue.rawValue }
    }

    var triangleVariant: TriangleVariant {
        get { TriangleVariant(rawValue: triangleVariantRaw) ?? .equilateral }
        set { triangleVariantRaw = newValue.rawValue }
    }

    var lineEnding: ShapeLineEnding {
        get {
            guard shapeKind == .line else { return .none }
            if let decoration = decodedLineDecoration {
                return decoration.ending
            }
            return hasArrowHead ? .end : .none
        }
        set { setLineAppearance(ending: newValue, style: lineStyle) }
    }

    var lineStyle: ShapeLineStyle {
        get {
            guard shapeKind == .line else { return .solid }
            return decodedLineDecoration?.style ?? .solid
        }
        set { setLineAppearance(ending: lineEnding, style: newValue) }
    }

    func setLineAppearance(ending: ShapeLineEnding, style: ShapeLineStyle) {
        guard shapeKind == .line else { return }
        triangleVariantRaw = "line:\(ending.rawValue):\(style.rawValue)"
        // Keep the legacy flag meaningful for older clients while richer line
        // appearance data travels in the existing variant field.
        hasArrowHead = ending.includesEnd
    }

    private var decodedLineDecoration: (ending: ShapeLineEnding, style: ShapeLineStyle)? {
        let parts = triangleVariantRaw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "line",
              let ending = ShapeLineEnding(rawValue: String(parts[1])),
              let style = ShapeLineStyle(rawValue: String(parts[2])) else { return nil }
        return (ending, style)
    }

    var hasVisibleStroke: Bool {
        strokeColorName != "none" && strokeWidth > 0
    }

    var hasVisibleStyle: Bool {
        hasVisibleStroke || (shapeKind.supportsFill && hasFill)
    }

    init(canvasID: UUID, kind: ShapeKind, x: Double = 0, y: Double = 0) {
        self.id = UUID()
        self.canvasID = canvasID
        self.shapeTypeRaw = kind.rawValue
        self.x = x
        self.y = y
        switch kind {
        case .line:             self.width = 180; self.height = 4
        case .rectangle:        self.width = 160; self.height = 110
        case .roundedRectangle: self.width = 170; self.height = 110
        case .triangle:         self.width = 140; self.height = 130
        case .polygon:          self.width = 140; self.height = 140
        case .circle:           self.width = 140; self.height = 140
        case .ellipse:          self.width = 175; self.height = 110
        case .diamond:          self.width = 155; self.height = 125
        case .star:             self.width = 145; self.height = 145
        case .speechBubble:     self.width = 180; self.height = 125
        case .cloud:            self.width = 180; self.height = 120
        case .parallelogram:    self.width = 180; self.height = 110
        case .cylinder:         self.width = 150; self.height = 150
        case .document:         self.width = 160; self.height = 130
        case .terminator:       self.width = 180; self.height = 80
        }
        self.rotation = 0
        self.strokeColorName = "primary"
        self.fillColorName = "blue"
        self.hasFill = false
        self.strokeWidth = 2.5
        self.hasArrowHead = false
        self.triangleVariantRaw = kind == .line
            ? "line:\(ShapeLineEnding.none.rawValue):\(ShapeLineStyle.solid.rawValue)"
            : TriangleVariant.equilateral.rawValue
        self.polygonSides = 6
        self.createdAt = Date()
        self.updatedAt = Date()
        self.zIndex = 0
        self.groupID = nil
    }

    var layerTitle: String { shapeKind.title }
    var layerIcon: String { shapeKind.icon }
    var layerTint: Color { .purple }
}
