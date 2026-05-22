//
//  CanvasModel.swift
//  Ponder
//

import Foundation
import CoreGraphics
import SwiftData

enum CanvasSize: String, Codable, CaseIterable {
    case infinite = "infinite"
    case a4       = "a4"
    case a5       = "a5"
    case letter   = "letter"
    case ipad     = "ipad"
    case custom   = "custom"

    var displayName: String {
        switch self {
        case .infinite: return "Infinite"
        case .a4:       return "A4"
        case .a5:       return "A5"
        case .letter:   return "Letter"
        case .ipad:     return "iPad"
        case .custom:   return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .infinite: return "infinity"
        case .a4:       return "doc"
        case .a5:       return "doc.text"
        case .letter:   return "doc.plaintext"
        case .ipad:     return "ipad"
        case .custom:   return "slider.horizontal.3"
        }
    }

    var subtitle: String {
        switch self {
        case .infinite: return "No boundaries"
        case .a4:       return "210 × 297 mm"
        case .a5:       return "148 × 210 mm"
        case .letter:   return "8.5 × 11 in"
        case .ipad:     return "iPad screen ratio"
        case .custom:   return "Set your own size"
        }
    }

    func dimensions(customWidth: Double = 800, customHeight: Double = 600) -> CGSize {
        switch self {
        case .infinite: return .zero
        case .a4:       return CGSize(width: 794,  height: 1123)
        case .a5:       return CGSize(width: 559,  height: 794)
        case .letter:   return CGSize(width: 816,  height: 1056)
        case .ipad:     return CGSize(width: 768,  height: 1024)
        case .custom:   return CGSize(width: customWidth, height: customHeight)
        }
    }
}

@Model
class CanvasModel {
    @Attribute(.unique) var id: UUID
    var name:          String
    var iconName:      String
    var iconColor:     String
    var createdAt:     Date
    // NEW — used for last-write-wins conflict resolution during sync.
    // Safe default for migration: existing records get .distantPast
    // which means any remote version will win on first sync.
    var updatedAt:     Date = Date.distantPast
    var canvasSizeRaw: String = "infinite"
    var customWidth:   Double = 800.0
    var customHeight:  Double = 600.0
    // Thumbnail stored as JPEG Data — nil until canvas is visited once
    var thumbnailData: Data? = nil

    var canvasSize: CanvasSize {
        get { CanvasSize(rawValue: canvasSizeRaw) ?? .infinite }
        set { canvasSizeRaw = newValue.rawValue }
    }

    var boundarySize: CGSize {
        canvasSize.dimensions(customWidth: customWidth, customHeight: customHeight)
    }

    var isInfinite: Bool { canvasSize == .infinite }

    init(
        name:         String,
        iconName:     String  = "doc.text",
        iconColor:    String  = "blue",
        canvasSize:   CanvasSize = .infinite,
        customWidth:  Double  = 800,
        customHeight: Double  = 600
    ) {
        self.id           = UUID()
        self.name         = name
        self.iconName     = iconName
        self.iconColor    = iconColor
        self.createdAt    = Date()
        self.updatedAt    = Date()
        self.canvasSizeRaw = canvasSize.rawValue
        self.customWidth  = customWidth
        self.customHeight = customHeight
        self.thumbnailData = nil
    }
}
