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
    var colorName: String
    var fontName: String = "system"

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
