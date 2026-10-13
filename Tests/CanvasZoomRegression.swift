import CoreGraphics

@main
struct CanvasZoomRegression {
    static func main() {
        let standard = CanvasZoomConfiguration()
        let extended = CanvasZoomConfiguration(expansion: 4, isPro: true)

        // A saved premium preference must never unlock zoom for a free account.
        for preference in [-100.0, 1, 2.5, 4, 100, .infinity, .nan] {
            expect(CanvasZoomConfiguration(expansion: preference, isPro: false) == standard,
                   "Free accounts retain standard limits for saved preference \(preference)")
        }
        expect(extended.minimumScale < standard.minimumScale,
               "Pro can zoom out farther to see more canvas")
        expect(extended.maximumScale > standard.maximumScale,
               "Pro can zoom in closer for details")
        expect(CanvasZoomConfiguration(expansion: 1, isPro: true) == standard,
               "Returning the slider to Standard disables the extension")
        expect(CanvasZoomConfiguration(expansion: -10, isPro: true) == standard,
               "Invalid stored values cannot shrink the standard range")
        expect(CanvasZoomConfiguration(expansion: 100, isPro: true) == extended,
               "Stored values cannot exceed the supported extended range")

        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            expect(extended.clampedScale(invalid) == 1, "Invalid zoom recovers to 100%")
        }
        expect(extended.clampedScale(0) == extended.minimumScale,
               "A pinch cannot produce a zero or negative scale")
        expect(extended.clampedScale(100_000) == extended.maximumScale,
               "Scroll and pinch overshoot stay inside the chosen range")

        // Zoom must keep the same content under a pinch, or at the center when
        // limits shrink after Reset or a change in the purchase entitlement.
        let oldOffset = CGSize(width: -170, height: 280)
        let anchor = CGPoint(x: 390, y: 512)
        for oldScale in [extended.minimumScale, 1, extended.maximumScale] {
            for nextScale in [standard.clampedScale(oldScale), extended.minimumScale, extended.maximumScale] {
                let nextOffset = extended.offsetPreservingAnchor(
                    from: oldOffset, oldScale: oldScale, newScale: nextScale, anchor: anchor
                )
                let canvasX = (anchor.x - oldOffset.width) / oldScale
                let canvasY = (anchor.y - oldOffset.height) / oldScale
                expect(abs(canvasX * nextScale + nextOffset.width - anchor.x) < 0.00001,
                       "Zoom and entitlement changes preserve the horizontal anchor")
                expect(abs(canvasY * nextScale + nextOffset.height - anchor.y) < 0.00001,
                       "Zoom and entitlement changes preserve the vertical anchor")
            }
        }

        print("Canvas zoom regressions passed")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }
}
