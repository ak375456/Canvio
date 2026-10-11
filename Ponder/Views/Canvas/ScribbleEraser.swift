import Foundation
import CoreGraphics
import PencilKit

struct DrawingStrokeBaseline {
    let strokeCount: Int
    let lastStroke: DrawingStrokeSignature?

    init(drawing: PKDrawing) {
        strokeCount = drawing.strokes.count
        lastStroke = drawing.strokes.last.map(DrawingStrokeSignature.init)
    }

    func latestStrokeIndex(in drawing: PKDrawing) -> Int? {
        guard let index = drawing.strokes.indices.last else { return nil }
        if drawing.strokes.count > strokeCount { return index }
        if drawing.strokes.count == strokeCount,
           DrawingStrokeSignature(drawing.strokes[index]) != lastStroke {
            return index
        }
        return nil
    }

    func firstNewStrokeIndex(in drawing: PKDrawing) -> Int? {
        let provisionalIndex = strokeCount - 1
        if provisionalIndex >= 0, provisionalIndex < drawing.strokes.count,
           DrawingStrokeSignature(drawing.strokes[provisionalIndex]) != lastStroke {
            return provisionalIndex
        }
        return strokeCount < drawing.strokes.count ? strokeCount : nil
    }
}

struct DrawingStrokeSignature: Equatable {
    let randomSeed: UInt32
    let pointCount: Int
    let creationDate: Date
    let lastPointLocation: CGPoint?
    let renderBounds: CGRect

    init(_ stroke: PKStroke) {
        randomSeed = stroke.randomSeed
        pointCount = stroke.path.count
        creationDate = stroke.path.creationDate
        lastPointLocation = stroke.path.last?.location
        renderBounds = stroke.renderBounds
    }
}

struct ScribbleEraseTarget {
    let id: UUID
    let drawing: PKDrawing
}

struct ScribbleEraseResult {
    /// The gesture itself is excluded from both snapshots.
    let before: PKDrawing
    let after: PKDrawing
    let externalTargets: [ScribbleEraseTarget]
}

enum ScribbleEraser {
    /// A quick next stroke mustn't cancel recognition of the preceding scratch.
    /// Resolve all gestures in a publication batch, in the order they were drawn.
    static func erasePendingStrokes(
        in drawing: PKDrawing,
        since baselines: [DrawingStrokeBaseline],
        viewScale: CGFloat = 1,
        additionalTargets: () -> [ScribbleEraseTarget] = { [] }
    ) -> ScribbleEraseResult? {
        var after = drawing
        var removedGestures = Set<Int>()
        var external: [ScribbleEraseTarget]?
        var changedExternal = Set<UUID>()
        let candidates = Set(baselines.compactMap { $0.firstNewStrokeIndex(in: drawing) }).sorted()
        for originalIndex in candidates {
            let original = drawing.strokes[originalIndex]
            let currentIndex = removedGestures.isEmpty ? originalIndex : after.strokes.firstIndex(where: {
                $0.path.creationDate == original.path.creationDate && $0.randomSeed == original.randomSeed
            })
            guard let currentIndex else { continue }
            let result = eraseStroke(in: after, at: currentIndex, viewScale: viewScale) {
                if external == nil { external = additionalTargets() }
                return external ?? []
            }
            guard let result else { continue }
            after = result.after
            removedGestures.insert(originalIndex)
            for target in result.externalTargets {
                changedExternal.insert(target.id)
                if let index = external?.firstIndex(where: { $0.id == target.id }) {
                    external?[index] = target
                }
            }
        }
        guard !removedGestures.isEmpty else { return nil }
        let before = PKDrawing(strokes: drawing.strokes.enumerated().compactMap {
            removedGestures.contains($0.offset) ? nil : $0.element
        })
        return ScribbleEraseResult(before: before, after: after,
                                   externalTargets: (external ?? []).filter { changedExternal.contains($0.id) })
    }

    static func eraseLatestStroke(
        in drawing: PKDrawing,
        since baseline: DrawingStrokeBaseline,
        viewScale: CGFloat = 1,
        additionalTargets: () -> [ScribbleEraseTarget] = { [] }
    ) -> ScribbleEraseResult? {
        guard let index = baseline.latestStrokeIndex(in: drawing) else { return nil }
        return eraseStroke(in: drawing, at: index, viewScale: viewScale, additionalTargets: additionalTargets)
    }

    private static func eraseStroke(
        in drawing: PKDrawing, at index: Int, viewScale: CGFloat,
        additionalTargets: () -> [ScribbleEraseTarget]
    ) -> ScribbleEraseResult? {
        let stroke = drawing.strokes[index]
        guard stroke.mask == nil,
              (stroke.path.last?.timeOffset ?? 0) <= 3.5 else { return nil }
        let scale = max(viewScale, 0.01)
        let points = stroke.path.interpolatedPoints(by: .distance(2 / scale))
            .map { $0.location.applying(stroke.transform) }
        guard let gesture = ScribbleEraseGesture(points: points, viewScale: scale) else {
            return nil
        }

        var precedingStrokes = drawing.strokes
        precedingStrokes.remove(at: index)
        let before = PKDrawing(strokes: precedingStrokes)
        // Later handwriting in the same batch wasn't present when this gesture
        // was made and must never become an erase target.
        let preceding = PKDrawing(strokes: Array(drawing.strokes[..<index]))
        let remaining = gesture.erasingStrokes(in: preceding)
        let after = PKDrawing(strokes: remaining.strokes + drawing.strokes[(index + 1)...])
        let external = additionalTargets().compactMap { target -> ScribbleEraseTarget? in
            let erased = gesture.erasingStrokes(in: target.drawing)
            guard erased.strokes.count != target.drawing.strokes.count else { return nil }
            return ScribbleEraseTarget(id: target.id, drawing: erased)
        }
        // A scratch on empty space remains an ordinary drawing.
        guard after.strokes.count != before.strokes.count || !external.isEmpty else {
            return nil
        }
        return ScribbleEraseResult(before: before, after: after, externalTargets: external)
    }
}

/// Recognition uses the original path, before smoothing, dashing or shape snapping.
/// Require five substantial passes along the same axis and contact with existing
/// visible ink on at least two passes. A line, circle, arrow or short zigzag fails.
struct ScribbleEraseGesture {
    private let passes: [[CGPoint]]
    private let bounds: CGRect
    private let viewScale: CGFloat

    init?(points: [CGPoint], viewScale: CGFloat = 1) {
        guard points.count >= 6,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              viewScale.isFinite, viewScale > 0 else { return nil }
        let scaled = points.map { CGPoint(x: $0.x * viewScale, y: $0.y * viewScale) }
        let mean = CGPoint(
            x: scaled.reduce(0) { $0 + $1.x } / CGFloat(scaled.count),
            y: scaled.reduce(0) { $0 + $1.y } / CGFloat(scaled.count)
        )
        var xx: CGFloat = 0, yy: CGFloat = 0, xy: CGFloat = 0
        for point in scaled {
            let x = point.x - mean.x, y = point.y - mean.y
            xx += x * x; yy += y * y; xy += x * y
        }
        let angle = 0.5 * atan2(2 * xy, xx - yy)
        let axis = CGPoint(x: cos(angle), y: sin(angle))
        let projections = scaled.map { $0.x * axis.x + $0.y * axis.y }
        let normals = scaled.map { -$0.x * axis.y + $0.y * axis.x }
        let span = (projections.max() ?? 0) - (projections.min() ?? 0)
        let thickness = (normals.max() ?? 0) - (normals.min() ?? 0)
        let length = zip(scaled, scaled.dropFirst()).reduce(CGFloat.zero) {
            $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)
        }
        guard span >= 20, thickness <= span * 0.9,
              length >= max(100, span * 4) else { return nil }

        let excursion = max(10, span * 0.45)
        var direction = 0
        var extreme = 0
        var turns: [Int] = []
        for index in projections.indices.dropFirst() {
            let delta = projections[index] - projections[extreme]
            if direction == 0 {
                if abs(delta) >= excursion {
                    direction = delta > 0 ? 1 : -1
                    extreme = index
                }
            } else if CGFloat(direction) * delta >= 0 {
                extreme = index
            } else if abs(delta) >= excursion {
                turns.append(extreme)
                direction = -direction
                extreme = index
            }
        }
        guard turns.count >= 4 else { return nil }
        let boundaries = [0] + turns + [points.count - 1]
        let passes = zip(boundaries, boundaries.dropFirst()).compactMap { start, end -> [CGPoint]? in
            guard abs(projections[end] - projections[start]) >= span * 0.45 else { return nil }
            return Array(points[start...end])
        }
        guard passes.count >= 5 else { return nil }
        self.passes = passes
        self.viewScale = viewScale
        self.bounds = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    func erasingStrokes(in drawing: PKDrawing) -> PKDrawing {
        PKDrawing(strokes: drawing.strokes.filter { !intersects($0) })
    }

    private func intersects(_ stroke: PKStroke) -> Bool {
        let radius = 6 / viewScale
        guard bounds.insetBy(dx: -radius, dy: -radius).intersects(stroke.renderBounds) else {
            return false
        }
        var hitPasses = Set<Int>()
        // Respect pixel-erased masks: invisible parts of strokes aren't targets.
        for range in stroke.maskedPathRanges {
            for point in stroke.path.interpolatedPoints(in: range, by: .distance(3 / viewScale)) {
                let location = point.location.applying(stroke.transform)
                let transformScale = hypot(stroke.transform.a, stroke.transform.b)
                let tolerance = radius + min(12 / viewScale, max(point.size.width, point.size.height) * transformScale / 2)
                guard bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(location) else { continue }
                for (index, pass) in passes.enumerated() where !hitPasses.contains(index) {
                    if zip(pass, pass.dropFirst()).contains(where: {
                        Self.distance(location, from: $0.0, to: $0.1) <= tolerance
                    }) {
                        hitPasses.insert(index)
                        if hitPasses.count >= 2 { return true }
                    }
                }
            }
        }
        return false
    }

    private static func distance(_ point: CGPoint, from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x, dy = end.y - start.y
        let squaredLength = dx * dx + dy * dy
        guard squaredLength > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / squaredLength))
        return hypot(point.x - start.x - t * dx, point.y - start.y - t * dy)
    }
}
