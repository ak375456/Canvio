//
//  CanvasBoundaryHelper.swift
//  Ponder
//

import CoreGraphics

enum CanvasBoundaryHelper {
    /// Clamps element center to stay within boundary.
    /// elementSize: pass the element's width/height so edges don't overflow.
    /// boundary = .zero means infinite — returns unchanged.
    static func clamp(
        x: Double,
        y: Double,
        boundary: CGSize,
        elementSize: CGSize = CGSize(width: 120, height: 120)
    ) -> (x: Double, y: Double) {
        guard boundary != .zero else { return (x, y) }
        let halfW = Double(elementSize.width) / 2
        let halfH = Double(elementSize.height) / 2
        let minX = halfW
        let minY = halfH
        let maxX = Double(boundary.width) - halfW
        let maxY = Double(boundary.height) - halfH
        let cx = max(minX, min(maxX, x))
        let cy = max(minY, min(maxY, y))
        return (cx, cy)
    }
}
