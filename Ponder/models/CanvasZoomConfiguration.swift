import CoreGraphics

/// A single set of limits for pinch, scroll, page fitting, and restored zoom.
struct CanvasZoomConfiguration: Equatable {
    static let expansionRange: ClosedRange<Double> = 1...4
    static let defaultMinimumScale: CGFloat = 0.55
    #if os(macOS)
    static let defaultMaximumScale: CGFloat = 8
    #else
    static let defaultMaximumScale: CGFloat = 5
    #endif

    let expansion: Double

    init(expansion: Double = 1, isPro: Bool = false) {
        self.expansion = isPro ? Self.clampedExpansion(expansion) : 1
    }

    static func clampedExpansion(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(expansionRange.upperBound, max(expansionRange.lowerBound, value))
    }

    var minimumScale: CGFloat { Self.defaultMinimumScale / CGFloat(expansion) }
    var maximumScale: CGFloat { Self.defaultMaximumScale * CGFloat(expansion) }

    func clampedScale(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return 1 }
        return min(maximumScale, max(minimumScale, scale))
    }

    func offsetPreservingAnchor(
        from offset: CGSize,
        oldScale: CGFloat,
        newScale: CGFloat,
        anchor: CGPoint
    ) -> CGSize {
        let ratio = newScale / max(oldScale, 0.0001)
        return CGSize(
            width: anchor.x - (anchor.x - offset.width) * ratio,
            height: anchor.y - (anchor.y - offset.height) * ratio
        )
    }
}
