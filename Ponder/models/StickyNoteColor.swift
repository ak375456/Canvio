//
//  StickyNoteColor.swift
//  Ponder
//
//  Created by aftab fazal qayum on 11/05/2026.
//

//
//  StickyNoteColor.swift
//  Ponder
//

import SwiftUI

struct StickyNoteColor: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let background: Color
    let foldShadow: Color  // the darker triangle behind the fold

    static let allColors: [StickyNoteColor] = [
        StickyNoteColor(name: "yellow",
                        background: Color(red: 1.00, green: 0.91, blue: 0.45),
                        foldShadow: Color(red: 0.92, green: 0.79, blue: 0.30)),
        StickyNoteColor(name: "orange",
                        background: Color(red: 1.00, green: 0.75, blue: 0.45),
                        foldShadow: Color(red: 0.93, green: 0.62, blue: 0.30)),
        StickyNoteColor(name: "pink",
                        background: Color(red: 1.00, green: 0.71, blue: 0.80),
                        foldShadow: Color(red: 0.92, green: 0.56, blue: 0.68)),
        StickyNoteColor(name: "blue",
                        background: Color(red: 0.66, green: 0.85, blue: 1.00),
                        foldShadow: Color(red: 0.50, green: 0.74, blue: 0.93)),
        StickyNoteColor(name: "green",
                        background: Color(red: 0.74, green: 0.93, blue: 0.68),
                        foldShadow: Color(red: 0.58, green: 0.83, blue: 0.50)),
    ]

    static func color(named name: String) -> StickyNoteColor {
        allColors.first { $0.name == name } ?? allColors[0]
    }
}
