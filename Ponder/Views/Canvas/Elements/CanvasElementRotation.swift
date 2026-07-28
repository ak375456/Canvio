import CoreGraphics

/// Accumulates the shortest angular change between consecutive pointer samples.
/// Using a delta preserves the element's rotation at touch-down, prevents corner
/// handles from snapping, and permits continuous turns through the ±180° seam.
struct CanvasElementRotationState {
    private var previousPointerAngle: Double?
    private var accumulatedRotation: Double = 0

    mutating func update(pointer: CGPoint, center: CGPoint, currentRotation: Double) -> Double {
        let dx = pointer.x - center.x
        let dy = pointer.y - center.y
        guard abs(dx) + abs(dy) > 0.001 else { return currentRotation }

        let pointerAngle = Double(atan2(dy, dx) * 180 / .pi)
        guard let previousPointerAngle else {
            self.previousPointerAngle = pointerAngle
            accumulatedRotation = currentRotation
            return currentRotation
        }

        var delta = pointerAngle - previousPointerAngle
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }

        accumulatedRotation += delta
        self.previousPointerAngle = pointerAngle
        return accumulatedRotation
    }

    mutating func reset() {
        previousPointerAngle = nil
        accumulatedRotation = 0
    }
}
