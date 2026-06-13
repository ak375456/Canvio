//
//  TextStyle.swift
//  Ponder
//
//  Created by aftab fazal qayum on 27/04/2026.
//

import SwiftUI

struct TextStyle {
    var text: String
    var fontSize: Double
    var isBold: Bool
    var isItalic: Bool
    var isUnderline: Bool = false
    var colorName: String
    var fontName: String = "system"
    var alignmentRaw: String = "leading"
    var bgColorName:     String = "none"
    var strokeColorName: String = "none"
    var strokeWidth:     Double = 2.0

    var textAlignment: TextAlignment {
        get {
            switch alignmentRaw {
            case "center":   return .center
            case "trailing": return .trailing
            default:         return .leading
            }
        }
        set {
            switch newValue {
            case .center:   alignmentRaw = "center"
            case .trailing: alignmentRaw = "trailing"
            default:        alignmentRaw = "leading"
            }
        }
    }

    static let colorOptions: [(name: String, color: Color)] = [
        ("primary", .primary),
        ("black", .black),
        ("gray",    .gray),
        ("blue",    .blue),
        ("indigo",  .indigo),
        ("cyan",    .cyan),
        ("teal",    .teal),
        ("mint",    .mint),
        ("green",   .green),
        ("yellow",  .yellow),
        ("orange",  .orange),
        ("red",     .red),
        ("pink",    .pink),
        ("purple",  .purple),
        ("brown",   .brown),
    ]
}
