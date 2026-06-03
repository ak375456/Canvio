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

// MARK: - Connector geometry

struct ConnectorGeometry {
    private static let minimumCurveDistance: CGFloat = 48
    private static let minimumHandleLength: CGFloat = 44
    private static let maximumHandleLength: CGFloat = 220

    static func path(from start: CGPoint,
                     fromAnchor: ConnectorAnchor? = nil,
                     to end: CGPoint,
                     toAnchor: ConnectorAnchor? = nil,
                     style: ConnectorLineStyle) -> Path {
        var path = Path()
        path.move(to: start)

        switch style {
        case .straight:
            path.addLine(to: end)
        case .curved:
            guard distance(start, end) >= minimumCurveDistance else {
                path.addLine(to: end)
                return path
            }

            let controls = controlPoints(
                from: start,
                fromAnchor: fromAnchor,
                to: end,
                toAnchor: toAnchor
            )
            path.addCurve(to: end, control1: controls.first, control2: controls.second)
        }

        return path
    }

    static func point(from start: CGPoint,
                      fromAnchor: ConnectorAnchor? = nil,
                      to end: CGPoint,
                      toAnchor: ConnectorAnchor? = nil,
                      style: ConnectorLineStyle,
                      t: CGFloat) -> CGPoint {
        let progress = clamped(t, minimum: 0, maximum: 1)

        guard style == .curved,
              distance(start, end) >= minimumCurveDistance else {
            return CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
        }

        let controls = controlPoints(
            from: start,
            fromAnchor: fromAnchor,
            to: end,
            toAnchor: toAnchor
        )
        let mt = 1 - progress
        return CGPoint(
            x: mt * mt * mt * start.x
                + 3 * mt * mt * progress * controls.first.x
                + 3 * mt * progress * progress * controls.second.x
                + progress * progress * progress * end.x,
            y: mt * mt * mt * start.y
                + 3 * mt * mt * progress * controls.first.y
                + 3 * mt * progress * progress * controls.second.y
                + progress * progress * progress * end.y
        )
    }

    static func pointBeforeEnd(from start: CGPoint,
                               fromAnchor: ConnectorAnchor? = nil,
                               to end: CGPoint,
                               toAnchor: ConnectorAnchor? = nil,
                               style: ConnectorLineStyle,
                               distance offset: CGFloat) -> CGPoint {
        let totalDistance = distance(start, end)
        guard totalDistance > 0 else { return end }

        if style == .straight || totalDistance < minimumCurveDistance {
            let angle = atan2(end.y - start.y, end.x - start.x)
            return CGPoint(
                x: end.x - offset * cos(angle),
                y: end.y - offset * sin(angle)
            )
        }

        let controls = controlPoints(
            from: start,
            fromAnchor: fromAnchor,
            to: end,
            toAnchor: toAnchor
        )
        let tangent = CGPoint(
            x: 3 * (end.x - controls.second.x),
            y: 3 * (end.y - controls.second.y)
        )
        let tangentLength = hypot(tangent.x, tangent.y)

        guard tangentLength > 0 else {
            let angle = atan2(end.y - start.y, end.x - start.x)
            return CGPoint(
                x: end.x - offset * cos(angle),
                y: end.y - offset * sin(angle)
            )
        }

        return CGPoint(
            x: end.x - (tangent.x / tangentLength) * offset,
            y: end.y - (tangent.y / tangentLength) * offset
        )
    }

    private static func controlPoints(from start: CGPoint,
                                      fromAnchor: ConnectorAnchor?,
                                      to end: CGPoint,
                                      toAnchor: ConnectorAnchor?) -> (first: CGPoint, second: CGPoint) {
        guard fromAnchor != nil || toAnchor != nil else {
            return fallbackControlPoints(from: start, to: end)
        }

        let resolvedFromAnchor = fromAnchor ?? inferredAnchor(at: start, facing: end)
        let resolvedToAnchor = toAnchor ?? inferredAnchor(at: end, facing: start)
        let fromDirection = direction(for: resolvedFromAnchor)
        let toDirection = direction(for: resolvedToAnchor)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let totalDistance = max(distance(start, end), 1)
        let baseHandle = clamped(
            totalDistance * 0.28,
            minimum: minimumHandleLength,
            maximum: 160
        )
        let fromProjection = max(0, dx * fromDirection.dx + dy * fromDirection.dy)
        let toProjection = max(0, -dx * toDirection.dx - dy * toDirection.dy)
        let fromHandle = clamped(
            max(baseHandle, fromProjection * 0.55),
            minimum: minimumHandleLength,
            maximum: maximumHandleLength
        )
        let toHandle = clamped(
            max(baseHandle, toProjection * 0.55),
            minimum: minimumHandleLength,
            maximum: maximumHandleLength
        )

        return (
            CGPoint(
                x: start.x + fromDirection.dx * fromHandle,
                y: start.y + fromDirection.dy * fromHandle
            ),
            CGPoint(
                x: end.x + toDirection.dx * toHandle,
                y: end.y + toDirection.dy * toHandle
            )
        )
    }

    private static func fallbackControlPoints(from start: CGPoint,
                                              to end: CGPoint) -> (first: CGPoint, second: CGPoint) {
        let dx = (end.x - start.x) * 0.5
        return (
            CGPoint(x: start.x + dx, y: start.y),
            CGPoint(x: end.x - dx, y: end.y)
        )
    }

    private static func inferredAnchor(at point: CGPoint, facing other: CGPoint) -> ConnectorAnchor {
        let dx = other.x - point.x
        let dy = other.y - point.y

        if abs(dx) > abs(dy) {
            return dx >= 0 ? .right : .left
        } else {
            return dy >= 0 ? .bottom : .top
        }
    }

    private static func direction(for anchor: ConnectorAnchor) -> CGVector {
        switch anchor {
        case .top:    return CGVector(dx: 0,  dy: -1)
        case .bottom: return CGVector(dx: 0,  dy: 1)
        case .left:   return CGVector(dx: -1, dy: 0)
        case .right:  return CGVector(dx: 1,  dy: 0)
        }
    }

    private static func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }

    private static func clamped(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
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
