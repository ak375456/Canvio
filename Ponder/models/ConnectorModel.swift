//
//  ConnectorModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Connector style enums

enum ConnectorLineStyle: String, Codable, CaseIterable {
    case straight = "straight"
    case curved   = "curved"

    var title: String {
        switch self {
        case .straight: return "Straight"
        case .curved:   return "Curved"
        }
    }
    var icon: String {
        switch self {
        case .straight: return "minus"
        case .curved:   return "scribble"
        }
    }
}

enum ConnectorAnchor: String, Codable {
    case top    = "top"
    case bottom = "bottom"
    case left   = "left"
    case right  = "right"

    /// Returns the anchor point in canvas coordinates given an element's
    /// center (x, y) and its bounding size.
    func point(cx: Double, cy: Double, width: Double, height: Double) -> CGPoint {
        switch self {
        case .top:    return CGPoint(x: cx,             y: cy - height / 2)
        case .bottom: return CGPoint(x: cx,             y: cy + height / 2)
        case .left:   return CGPoint(x: cx - width / 2, y: cy)
        case .right:  return CGPoint(x: cx + width / 2, y: cy)
        }
    }
}

// MARK: - Model

@Model
class ConnectorModel {
    @Attribute(.unique) var id: UUID
    var canvasID: UUID

    // Source element
    var fromElementID: UUID
    var fromAnchorRaw: String   // ConnectorAnchor.rawValue

    // Target element
    var toElementID: UUID
    var toAnchorRaw: String     // ConnectorAnchor.rawValue

    // Style
    var lineStyleRaw: String    // ConnectorLineStyle.rawValue
    var colorName: String
    var strokeWidth: Double
    var hasArrowHead: Bool

    var createdAt: Date
    var updatedAt: Date

    // MARK: Computed

    var fromAnchor: ConnectorAnchor {
        get { ConnectorAnchor(rawValue: fromAnchorRaw) ?? .right }
        set { fromAnchorRaw = newValue.rawValue }
    }

    var toAnchor: ConnectorAnchor {
        get { ConnectorAnchor(rawValue: toAnchorRaw) ?? .left }
        set { toAnchorRaw = newValue.rawValue }
    }

    var lineStyle: ConnectorLineStyle {
        get { ConnectorLineStyle(rawValue: lineStyleRaw) ?? .straight }
        set { lineStyleRaw = newValue.rawValue }
    }

    init(
        canvasID: UUID,
        fromElementID: UUID, fromAnchor: ConnectorAnchor,
        toElementID: UUID,   toAnchor: ConnectorAnchor,
        lineStyle: ConnectorLineStyle = .curved,
        colorName: String = "primary",
        strokeWidth: Double = 2.0,
        hasArrowHead: Bool = true
    ) {
        self.id            = UUID()
        self.canvasID      = canvasID
        self.fromElementID = fromElementID
        self.fromAnchorRaw = fromAnchor.rawValue
        self.toElementID   = toElementID
        self.toAnchorRaw   = toAnchor.rawValue
        self.lineStyleRaw  = lineStyle.rawValue
        self.colorName     = colorName
        self.strokeWidth   = strokeWidth
        self.hasArrowHead  = hasArrowHead
        self.createdAt     = Date()
        self.updatedAt     = Date()
    }
}
