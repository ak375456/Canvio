//
//  DrawingCanvasView.swift
//  Canvio
//

import SwiftUI
import PencilKit

#if os(iOS)

final class PencilShapeSnapController {
    var isEnabled: Bool = true {
        didSet {
            if !isEnabled { cancelPendingSnap() }
        }
    }

    private var pendingSnap: DispatchWorkItem?
    private var isApplyingSnap = false
    private let snapDelay: TimeInterval = 0.55

    func scheduleSnap(on canvas: PKCanvasView, commit: @escaping (PKDrawing) -> Void) {
        guard isEnabled,
              !isApplyingSnap,
              canvas.tool is PKInkingTool,
              !canvas.drawing.strokes.isEmpty
        else {
            cancelPendingSnap()
            return
        }

        pendingSnap?.cancel()
        let work = DispatchWorkItem { [weak self, weak canvas] in
            guard let self, let canvas else { return }
            self.snapNow(on: canvas, commit: commit)
        }
        pendingSnap = work
        DispatchQueue.main.asyncAfter(deadline: .now() + snapDelay, execute: work)
    }

    func cancelPendingSnap() {
        pendingSnap?.cancel()
        pendingSnap = nil
    }

    func snapNow(on canvas: PKCanvasView, commit: @escaping (PKDrawing) -> Void) {
        guard isEnabled,
              !isApplyingSnap,
              canvas.tool is PKInkingTool,
              let snapped = drawingBySnappingLatestStroke(in: canvas.drawing),
              snapped.dataRepresentation() != canvas.drawing.dataRepresentation()
        else {
            pendingSnap = nil
            return
        }

        isApplyingSnap = true
        pendingSnap?.cancel()
        pendingSnap = nil
        canvas.drawing = snapped
        commit(snapped)
        isApplyingSnap = false
    }

    var isApplyingProgrammaticSnap: Bool {
        isApplyingSnap
    }

    func drawingBySnappingLatestStroke(in drawing: PKDrawing) -> PKDrawing? {
        guard isEnabled else { return nil }
        return PencilShapeSnapper.snappedDrawing(from: drawing)
    }
}

private struct PencilShapeSnapper {
    private struct Candidate {
        let points: [CGPoint]
        let score: CGFloat
    }

    private struct StraightStrokeCandidate {
        let index: Int
        let stroke: PKStroke
        let start: CGPoint
        let end: CGPoint
        let length: CGFloat
    }

    static func snappedDrawing(from drawing: PKDrawing) -> PKDrawing? {
        guard let lastIndex = drawing.strokes.indices.last else { return nil }

        var strokes = drawing.strokes
        let originalStroke = strokes[lastIndex]
        guard originalStroke.mask == nil else { return nil }

        if let multiStrokeArrow = snappedMultiStrokeArrow(from: strokes) {
            return multiStrokeArrow
        }

        let rawPoints = renderedPoints(from: originalStroke)
        guard let cleanPoints = cleanShapePoints(from: rawPoints),
              let snappedStroke = stroke(from: cleanPoints, matching: originalStroke)
        else { return nil }

        strokes[lastIndex] = snappedStroke
        return PKDrawing(strokes: strokes)
    }

    private static func renderedPoints(from stroke: PKStroke) -> [CGPoint] {
        stroke.path.map { $0.location.applying(stroke.transform) }
    }

    private static func snappedMultiStrokeArrow(from strokes: [PKStroke]) -> PKDrawing? {
        if let twoStroke = snappedTwoStrokeArrow(from: strokes) { return twoStroke }
        if let threeStroke = snappedThreeStrokeArrow(from: strokes) { return threeStroke }
        return nil
    }

    // Supports a straight shaft plus a single V-shaped head stroke.
    private static func snappedTwoStrokeArrow(from strokes: [PKStroke]) -> PKDrawing? {
        guard strokes.count >= 2 else { return nil }
        let indices = Array(strokes.indices.suffix(2))

        for shaftIndex in indices {
            let headIndex = indices.first { $0 != shaftIndex }!
            guard let shaft = straightStrokeCandidate(strokes[shaftIndex], index: shaftIndex),
                  strokes[headIndex].mask == nil else { continue }

            let headPoints = removingNearDuplicates(
                renderedPoints(from: strokes[headIndex]),
                minimumDistance: 2
            )
            guard headPoints.count >= 3,
                  let headStart = headPoints.first,
                  let headEnd = headPoints.last else { continue }

            let internalIndices = headPoints.indices.dropFirst().dropLast()
            guard let tipIndex = internalIndices.max(by: {
                distanceFromPoint(headPoints[$0], toSegmentStart: headStart, end: headEnd)
                    < distanceFromPoint(headPoints[$1], toSegmentStart: headStart, end: headEnd)
            }) else { continue }

            let rawTip = headPoints[tipIndex]
            let firstArmPoints = Array(headPoints[...tipIndex])
            let secondArmPoints = Array(headPoints[tipIndex...])
            guard isStraightEnough(firstArmPoints), isStraightEnough(secondArmPoints) else { continue }

            for orientation in [(tail: shaft.start, tip: shaft.end),
                                (tail: shaft.end, tip: shaft.start)] {
                let attachmentDistance = distance(orientation.tip, rawTip)
                let allowedAttachmentDistance = max(16, shaft.length * 0.14)
                guard attachmentDistance <= allowedAttachmentDistance else { continue }

                let tip = average([orientation.tip, rawTip])
                guard validArrowWings(
                    tail: orientation.tail,
                    tip: tip,
                    firstWing: headStart,
                    secondWing: headEnd,
                    shaftLength: shaft.length
                ) else { continue }

                var snapped = strokes
                guard let snappedShaft = stroke(
                    from: sampledPolyline([orientation.tail, tip]),
                    matching: shaft.stroke
                ),
                let snappedHead = stroke(
                    from: sampledPolyline([headStart, tip, headEnd]),
                    matching: strokes[headIndex]
                ) else { continue }
                snapped[shaftIndex] = snappedShaft
                snapped[headIndex] = snappedHead
                return PKDrawing(strokes: snapped)
            }
        }

        return nil
    }

    // Supports a shaft and two separately drawn arrowhead wings.
    private static func snappedThreeStrokeArrow(from strokes: [PKStroke]) -> PKDrawing? {
        guard strokes.count >= 3 else { return nil }
        let indices = Array(strokes.indices.suffix(3))
        let lineCandidates = indices.compactMap {
            straightStrokeCandidate(strokes[$0], index: $0)
        }
        guard lineCandidates.count == 3,
              let shaft = lineCandidates.max(by: { $0.length < $1.length }) else { return nil }
        let wings = lineCandidates.filter { $0.index != shaft.index }

        for orientation in [(tail: shaft.start, tip: shaft.end),
                            (tail: shaft.end, tip: shaft.start)] {
            let resolvedWings = wings.map { wing -> (candidate: StraightStrokeCandidate, attached: CGPoint, outer: CGPoint) in
                if distance(wing.start, orientation.tip) <= distance(wing.end, orientation.tip) {
                    return (wing, wing.start, wing.end)
                }
                return (wing, wing.end, wing.start)
            }
            let allowedAttachmentDistance = max(16, shaft.length * 0.14)
            guard resolvedWings.allSatisfy({
                distance($0.attached, orientation.tip) <= allowedAttachmentDistance
            }) else { continue }

            let tip = average([orientation.tip] + resolvedWings.map(\.attached))
            guard validArrowWings(
                tail: orientation.tail,
                tip: tip,
                firstWing: resolvedWings[0].outer,
                secondWing: resolvedWings[1].outer,
                shaftLength: shaft.length
            ) else { continue }

            var snapped = strokes
            guard let snappedShaft = stroke(
                from: sampledPolyline([orientation.tail, tip]),
                matching: shaft.stroke
            ) else { continue }
            snapped[shaft.index] = snappedShaft

            var successfullySnappedWings = true
            for wing in resolvedWings {
                guard let snappedWing = stroke(
                    from: sampledPolyline([tip, wing.outer]),
                    matching: wing.candidate.stroke
                ) else {
                    successfullySnappedWings = false
                    break
                }
                snapped[wing.candidate.index] = snappedWing
            }
            if successfullySnappedWings { return PKDrawing(strokes: snapped) }
        }

        return nil
    }

    private static func straightStrokeCandidate(_ stroke: PKStroke,
                                                index: Int) -> StraightStrokeCandidate? {
        guard stroke.mask == nil else { return nil }
        let points = removingNearDuplicates(renderedPoints(from: stroke), minimumDistance: 2)
        guard let start = points.first, let end = points.last,
              points.count >= 2 else { return nil }
        let length = distance(start, end)
        guard length >= 10, isStraightEnough(points) else { return nil }
        return StraightStrokeCandidate(index: index, stroke: stroke,
                                       start: start, end: end, length: length)
    }

    private static func isStraightEnough(_ points: [CGPoint]) -> Bool {
        guard let start = points.first, let end = points.last else { return false }
        let directLength = distance(start, end)
        guard directLength >= 8 else { return false }
        let pathRatio = polylineLength(points) / max(directLength, 1)
        let deviation = points
            .map { distanceFromPoint($0, toSegmentStart: start, end: end) }
            .max() ?? 0
        return pathRatio <= 1.38 && deviation <= max(9, directLength * 0.12)
    }

    private static func validArrowWings(tail: CGPoint, tip: CGPoint,
                                        firstWing: CGPoint, secondWing: CGPoint,
                                        shaftLength: CGFloat) -> Bool {
        let shaftDirection = normalized(vector(from: tail, to: tip))
        let firstVector = vector(from: tip, to: firstWing)
        let secondVector = vector(from: tip, to: secondWing)
        let firstLength = hypot(firstVector.dx, firstVector.dy)
        let secondLength = hypot(secondVector.dx, secondVector.dy)
        let minimumLength = max(10, shaftLength * 0.07)
        let maximumLength = max(22, shaftLength * 0.55)

        guard firstLength >= minimumLength, secondLength >= minimumLength,
              firstLength <= maximumLength, secondLength <= maximumLength,
              dot(normalized(firstVector), shaftDirection) <= 0.15,
              dot(normalized(secondVector), shaftDirection) <= 0.15 else { return false }

        let firstCross = shaftDirection.dx * firstVector.dy - shaftDirection.dy * firstVector.dx
        let secondCross = shaftDirection.dx * secondVector.dy - shaftDirection.dy * secondVector.dx
        return firstCross * secondCross < 0
            && abs(firstCross) >= firstLength * 0.22
            && abs(secondCross) >= secondLength * 0.22
    }

    private static func average(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let total = points.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }
        return CGPoint(x: total.x / CGFloat(points.count),
                       y: total.y / CGFloat(points.count))
    }

    private static func cleanShapePoints(from rawPoints: [CGPoint]) -> [CGPoint]? {
        let points = removingNearDuplicates(rawPoints, minimumDistance: 2)
        guard points.count >= 2 else { return nil }

        let bounds = bounds(for: points)
        let diagonal = hypot(bounds.width, bounds.height)

        if let arrow = arrowCandidate(from: points, diagonal: diagonal) {
            return arrow.points
        }

        if let line = lineCandidate(from: points, diagonal: diagonal) {
            return line.points
        }

        guard points.count >= 8,
              diagonal >= 34,
              isClosed(points, diagonal: diagonal)
        else { return nil }

        let polygon = polygonCandidate(from: points, bounds: bounds, diagonal: diagonal)
        let ellipse = ellipseCandidate(from: points, bounds: bounds, diagonal: diagonal)

        switch (polygon, ellipse) {
        case let (polygon?, ellipse?):
            return ellipse.score < polygon.score ? ellipse.points : polygon.points
        case let (polygon?, nil):
            return polygon.points
        case let (nil, ellipse?):
            return ellipse.points
        default:
            return nil
        }
    }

    private static func lineCandidate(from points: [CGPoint], diagonal: CGFloat) -> Candidate? {
        guard let first = points.first, let last = points.last else { return nil }

        let directDistance = distance(first, last)
        guard directDistance >= 28,
              diagonal >= 28
        else { return nil }

        let length = polylineLength(points)
        guard length / max(directDistance, 1) <= 1.22 else { return nil }

        let maxDeviation = points
            .map { distanceFromPoint($0, toSegmentStart: first, end: last) }
            .max() ?? 0
        let allowedDeviation = max(8, directDistance * 0.08)
        guard maxDeviation <= allowedDeviation else { return nil }

        return Candidate(
            points: sampledPolyline([first, last]),
            score: (maxDeviation / max(directDistance, 1)) + abs(length / max(directDistance, 1) - 1)
        )
    }

    private static func arrowCandidate(from points: [CGPoint], diagonal: CGFloat) -> Candidate? {
        guard points.count >= 5, diagonal >= 36 else { return nil }

        // A natural one-stroke arrow visits its tip twice:
        // tail → tip → first wing → tip → second wing. Detect that repeated
        // tip directly instead of requiring RDP to produce exactly 5 points,
        // which was too brittle for real Pencil sampling and hand jitter.
        let forward = directionalArrowCandidate(from: points, diagonal: diagonal)
        let backward = directionalArrowCandidate(from: points.reversed(), diagonal: diagonal)

        switch (forward, backward) {
        case let (forward?, backward?):
            return forward.score <= backward.score ? forward : backward
        case let (forward?, nil):
            return forward
        case let (nil, backward?):
            return backward
        default:
            return nil
        }
    }

    private static func directionalArrowCandidate<C: Collection>(
        from source: C,
        diagonal: CGFloat
    ) -> Candidate? where C.Element == CGPoint {
        let points = Array(source)
        guard points.count >= 5 else { return nil }

        let recurrenceDistance = max(14, diagonal * 0.14)
        let minimumIndexSeparation = max(2, points.count / 18)
        var candidates: [Candidate] = []

        for firstTipIndex in 1..<(points.count - 3) {
            let tail = points[0]
            let firstTip = points[firstTipIndex]
            let initialShaftLength = distance(tail, firstTip)
            guard initialShaftLength >= 32 else { continue }

            let shaftPoints = Array(points[0...firstTipIndex])
            let shaftPathRatio = polylineLength(shaftPoints) / max(initialShaftLength, 1)
            let shaftDeviation = shaftPoints
                .map { distanceFromPoint($0, toSegmentStart: tail, end: firstTip) }
                .max() ?? 0
            guard shaftPathRatio <= 1.38,
                  shaftDeviation <= max(11, initialShaftLength * 0.11)
            else { continue }

            let firstPossibleReturn = firstTipIndex + minimumIndexSeparation
            guard firstPossibleReturn < points.count - 1 else { continue }

            for secondTipIndex in firstPossibleReturn..<(points.count - 1) {
                let secondTip = points[secondTipIndex]
                let tipSeparation = distance(firstTip, secondTip)
                guard tipSeparation <= recurrenceDistance else { continue }

                let firstWingRange = (firstTipIndex + 1)..<secondTipIndex
                let secondWingRange = (secondTipIndex + 1)..<points.count
                guard !firstWingRange.isEmpty, !secondWingRange.isEmpty,
                      let firstWingIndex = firstWingRange.max(by: {
                          distance(points[$0], firstTip) < distance(points[$1], firstTip)
                      }),
                      let secondWingIndex = secondWingRange.max(by: {
                          distance(points[$0], secondTip) < distance(points[$1], secondTip)
                      })
                else { continue }

                let tip = CGPoint(x: (firstTip.x + secondTip.x) / 2,
                                  y: (firstTip.y + secondTip.y) / 2)
                let shaftLength = distance(tail, tip)
                let shaftDirection = normalized(vector(from: tail, to: tip))
                let firstWing = points[firstWingIndex]
                let secondWing = points[secondWingIndex]
                let firstWingVector = vector(from: tip, to: firstWing)
                let secondWingVector = vector(from: tip, to: secondWing)
                let firstWingLength = hypot(firstWingVector.dx, firstWingVector.dy)
                let secondWingLength = hypot(secondWingVector.dx, secondWingVector.dy)

                let minimumWingLength = max(10, shaftLength * 0.07)
                let maximumWingLength = max(22, shaftLength * 0.52)
                guard shaftLength >= 32,
                      firstWingLength >= minimumWingLength,
                      secondWingLength >= minimumWingLength,
                      firstWingLength <= maximumWingLength,
                      secondWingLength <= maximumWingLength,
                      dot(normalized(firstWingVector), shaftDirection) <= 0.12,
                      dot(normalized(secondWingVector), shaftDirection) <= 0.12
                else { continue }

                let firstCross = shaftDirection.dx * firstWingVector.dy
                    - shaftDirection.dy * firstWingVector.dx
                let secondCross = shaftDirection.dx * secondWingVector.dy
                    - shaftDirection.dy * secondWingVector.dx
                guard firstCross * secondCross < 0,
                      abs(firstCross) >= firstWingLength * 0.24,
                      abs(secondCross) >= secondWingLength * 0.24
                else { continue }

                let firstWingSource = Array(points[firstTipIndex...secondTipIndex])
                let secondWingSource = Array(points[secondTipIndex...secondWingIndex])
                let firstWingError = meanDistance(
                    from: firstWingSource,
                    toOpenPolyline: [tip, firstWing, tip]
                )
                let secondWingError = meanDistance(
                    from: secondWingSource,
                    toOpenPolyline: [tip, secondWing]
                )
                let allowedWingError = max(10, diagonal * 0.08)
                guard firstWingError <= allowedWingError,
                      secondWingError <= allowedWingError else { continue }

                let cleaned = [tail, tip, firstWing, tip, secondWing]
                let score = tipSeparation / max(diagonal, 1)
                    + shaftDeviation / max(shaftLength, 1)
                    + (firstWingError + secondWingError) / max(diagonal * 2, 1)
                candidates.append(Candidate(
                    points: sampledPolyline(cleaned),
                    score: score
                ))
            }
        }

        return candidates.min { $0.score < $1.score }
    }

    private static func polygonCandidate(from points: [CGPoint],
                                         bounds: CGRect,
                                         diagonal: CGFloat) -> Candidate? {
        let tolerances = [
            max(7, diagonal * 0.055),
            max(9, diagonal * 0.08),
            max(11, diagonal * 0.11)
        ]

        var candidates: [Candidate] = []

        for tolerance in tolerances {
            let vertices = closedVertices(from: points, tolerance: tolerance)

            if vertices.count == 3,
               let triangle = triangleCandidate(vertices: vertices, sourcePoints: points, diagonal: diagonal) {
                candidates.append(triangle)
            }

            if vertices.count == 4,
               let rectangle = rectangleCandidate(vertices: vertices, sourcePoints: points, diagonal: diagonal) {
                candidates.append(rectangle)
            }

            if (5...8).contains(vertices.count),
               let polygon = multiSidedPolygonCandidate(
                    vertices: vertices,
                    sourcePoints: points,
                    diagonal: diagonal
               ) {
                candidates.append(polygon)
            }
        }

        return candidates.min { $0.score < $1.score }
    }

    private static func triangleCandidate(vertices: [CGPoint],
                                          sourcePoints: [CGPoint],
                                          diagonal: CGFloat) -> Candidate? {
        guard polygonArea(vertices) >= diagonal * diagonal * 0.035 else { return nil }

        let closed = vertices + [vertices[0]]
        let meanError = meanDistance(from: sourcePoints, toClosedPolyline: closed)
        guard meanError <= max(11, diagonal * 0.08) else { return nil }

        return Candidate(
            points: sampledPolyline(closed),
            score: meanError / max(diagonal, 1)
        )
    }

    private static func rectangleCandidate(vertices: [CGPoint],
                                           sourcePoints: [CGPoint],
                                           diagonal: CGFloat) -> Candidate? {
        let cornerCosines = vertices.indices.map { index -> CGFloat in
            let current = vertices[index]
            let previous = vertices[(index + vertices.count - 1) % vertices.count]
            let next = vertices[(index + 1) % vertices.count]
            return abs(cosineBetween(vector(from: current, to: previous),
                                     vector(from: current, to: next)))
        }

        guard let worstCorner = cornerCosines.max(),
              worstCorner <= 0.58,
              let rectangle = orientedRectangle(from: vertices, sourcePoints: sourcePoints)
        else { return nil }

        let closed = rectangle + [rectangle[0]]
        let meanError = meanDistance(from: sourcePoints, toClosedPolyline: closed)
        guard meanError <= max(11, diagonal * 0.075) else { return nil }

        return Candidate(
            points: sampledPolyline(rotate(closed, toStartNear: sourcePoints[0])),
            score: (meanError / max(diagonal, 1)) + worstCorner * 0.015
        )
    }

    private static func multiSidedPolygonCandidate(vertices: [CGPoint],
                                                   sourcePoints: [CGPoint],
                                                   diagonal: CGFloat) -> Candidate? {
        guard (5...8).contains(vertices.count),
              polygonArea(vertices) >= diagonal * diagonal * 0.06 else { return nil }

        let edgeLengths = vertices.indices.map {
            distance(vertices[$0], vertices[($0 + 1) % vertices.count])
        }
        guard edgeLengths.allSatisfy({ $0 >= diagonal * 0.075 }) else { return nil }

        let closed = vertices + [vertices[0]]
        let meanError = meanDistance(from: sourcePoints, toClosedPolyline: closed)
        guard meanError <= max(10, diagonal * 0.07) else { return nil }

        return Candidate(
            points: sampledPolyline(rotate(closed, toStartNear: sourcePoints[0])),
            score: meanError / max(diagonal, 1) + CGFloat(vertices.count) * 0.002
        )
    }

    private static func ellipseCandidate(from points: [CGPoint],
                                         bounds: CGRect,
                                         diagonal: CGFloat) -> Candidate? {
        var radiusX = bounds.width / 2
        var radiusY = bounds.height / 2
        guard radiusX >= 14, radiusY >= 14 else { return nil }

        let aspect = radiusX / max(radiusY, 1)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if aspect > 0.76 && aspect < 1.32 {
            let radius = (radiusX + radiusY) / 2
            radiusX = radius
            radiusY = radius
        }

        var totalError: CGFloat = 0
        var maxError: CGFloat = 0
        var sectors = Set<Int>()

        for point in points {
            let dx = (point.x - center.x) / max(radiusX, 1)
            let dy = (point.y - center.y) / max(radiusY, 1)
            let radialDistance = hypot(dx, dy)
            let error = abs(radialDistance - 1)
            totalError += error
            maxError = max(maxError, error)

            let angle = atan2(point.y - center.y, point.x - center.x)
            let normalized = angle < 0 ? angle + 2 * .pi : angle
            sectors.insert(Int((normalized / (2 * .pi)) * 8))
        }

        let meanError = totalError / CGFloat(points.count)
        guard sectors.count >= 6,
              meanError <= 0.19,
              maxError <= 0.62
        else { return nil }

        return Candidate(
            points: ellipsePoints(center: center, radiusX: radiusX, radiusY: radiusY),
            score: meanError * 0.35 + CGFloat(8 - sectors.count) * 0.01
        )
    }

    private static func stroke(from cleanPoints: [CGPoint], matching original: PKStroke) -> PKStroke? {
        let sourcePoints = Array(original.path)
        guard let firstSource = sourcePoints.first else { return nil }

        let averageSize = sourcePoints.reduce(CGSize.zero) { partial, point in
            CGSize(width: partial.width + point.size.width,
                   height: partial.height + point.size.height)
        }
        let pointCount = CGFloat(sourcePoints.count)
        let size = CGSize(
            width: max(1, averageSize.width / max(pointCount, 1)),
            height: max(1, averageSize.height / max(pointCount, 1))
        )
        let opacity = sourcePoints.reduce(CGFloat(0)) { $0 + $1.opacity } / max(pointCount, 1)
        let force = sourcePoints.reduce(CGFloat(0)) { $0 + $1.force } / max(pointCount, 1)
        let azimuth = sourcePoints.last?.azimuth ?? firstSource.azimuth
        let altitude = sourcePoints.last?.altitude ?? firstSource.altitude

        let controls = cleanPoints.enumerated().map { index, point in
            PKStrokePoint(
                location: point,
                timeOffset: TimeInterval(index) * 0.006,
                size: size,
                opacity: max(0.05, min(opacity, 1)),
                force: max(0, force),
                azimuth: azimuth,
                altitude: altitude
            )
        }

        guard controls.count >= 2 else { return nil }
        let path = PKStrokePath(controlPoints: controls, creationDate: original.path.creationDate)
        return PKStroke(ink: original.ink, path: path, transform: .identity, mask: nil)
    }

    private static func closedVertices(from points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard let first = points.first else { return [] }
        var loop = points
        if distance(first, loop.last ?? first) > 0.1 {
            loop.append(first)
        } else {
            loop[loop.count - 1] = first
        }

        var vertices = Array(simplify(loop, tolerance: tolerance).dropLast())
        while vertices.count > 1,
              let last = vertices.last,
              distance(vertices[0], last) < tolerance {
            vertices.removeLast()
        }
        return vertices
    }

    private static func orientedRectangle(from vertices: [CGPoint],
                                          sourcePoints: [CGPoint]) -> [CGPoint]? {
        guard vertices.count == 4 else { return nil }

        let edges = vertices.indices.map { index -> (start: CGPoint, end: CGPoint, length: CGFloat) in
            let start = vertices[index]
            let end = vertices[(index + 1) % vertices.count]
            return (start, end, distance(start, end))
        }
        guard let longestEdge = edges.max(by: { $0.length < $1.length }),
              longestEdge.length > 0
        else { return nil }

        let axis = normalized(vector(from: longestEdge.start, to: longestEdge.end))
        let perpendicular = CGVector(dx: -axis.dy, dy: axis.dx)
        let projectionsA = sourcePoints.map { dot($0, axis) }
        let projectionsB = sourcePoints.map { dot($0, perpendicular) }

        guard let minA = projectionsA.min(),
              let maxA = projectionsA.max(),
              let minB = projectionsB.min(),
              let maxB = projectionsB.max()
        else { return nil }

        let centerA = (minA + maxA) / 2
        let centerB = (minB + maxB) / 2
        var halfA = (maxA - minA) / 2
        var halfB = (maxB - minB) / 2
        guard halfA >= 10, halfB >= 10 else { return nil }

        let ratio = halfA / max(halfB, 1)
        if ratio > 0.72 && ratio < 1.38 {
            let side = (halfA + halfB) / 2
            halfA = side
            halfB = side
        }

        let center = point(axis, scaledBy: centerA, plus: point(perpendicular, scaledBy: centerB))
        return [
            offset(center, axis, -halfA, perpendicular, -halfB),
            offset(center, axis, halfA, perpendicular, -halfB),
            offset(center, axis, halfA, perpendicular, halfB),
            offset(center, axis, -halfA, perpendicular, halfB)
        ]
    }

    private static func ellipsePoints(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat) -> [CGPoint] {
        let count = 96
        var points: [CGPoint] = []
        points.reserveCapacity(count + 1)

        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
            points.append(CGPoint(
                x: center.x + cos(angle) * radiusX,
                y: center.y + sin(angle) * radiusY
            ))
        }
        if let first = points.first { points.append(first) }
        return points
    }

    private static func sampledPolyline(_ points: [CGPoint], spacing: CGFloat = 7) -> [CGPoint] {
        guard points.count > 1 else { return points }
        var sampled = [points[0]]

        for index in 1..<points.count {
            let start = points[index - 1]
            let end = points[index]
            let segmentLength = distance(start, end)
            let steps = max(1, Int(ceil(segmentLength / spacing)))

            for step in 1...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                sampled.append(CGPoint(
                    x: start.x + (end.x - start.x) * progress,
                    y: start.y + (end.y - start.y) * progress
                ))
            }
        }

        return sampled
    }

    private static func rotate(_ points: [CGPoint], toStartNear start: CGPoint) -> [CGPoint] {
        guard points.count > 2 else { return points }
        let closed = distance(points[0], points[points.count - 1]) < 0.1
        let body = closed ? Array(points.dropLast()) : points
        guard let startIndex = body.indices.min(by: {
            distance(body[$0], start) < distance(body[$1], start)
        }) else { return points }

        let rotated = Array(body[startIndex...]) + Array(body[..<startIndex])
        return closed ? rotated + [rotated[0]] : rotated
    }

    private static func simplify(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2,
              let first = points.first,
              let last = points.last
        else { return points }

        var maxDistance: CGFloat = 0
        var index = 0

        for candidateIndex in 1..<(points.count - 1) {
            let currentDistance = distanceFromPoint(points[candidateIndex],
                                                    toSegmentStart: first,
                                                    end: last)
            if currentDistance > maxDistance {
                maxDistance = currentDistance
                index = candidateIndex
            }
        }

        guard maxDistance > tolerance else { return [first, last] }

        let left = simplify(Array(points[0...index]), tolerance: tolerance)
        let right = simplify(Array(points[index...]), tolerance: tolerance)
        return Array(left.dropLast()) + right
    }

    private static func removingNearDuplicates(_ points: [CGPoint],
                                               minimumDistance: CGFloat) -> [CGPoint] {
        guard let first = points.first else { return [] }
        var cleaned = [first]

        for point in points.dropFirst() {
            if distance(point, cleaned[cleaned.count - 1]) >= minimumDistance {
                cleaned.append(point)
            }
        }

        if let last = points.last,
           distance(last, cleaned[cleaned.count - 1]) > 0.1 {
            cleaned.append(last)
        }

        return cleaned
    }

    private static func isClosed(_ points: [CGPoint], diagonal: CGFloat) -> Bool {
        guard let first = points.first, let last = points.last else { return false }
        return distance(first, last) <= max(18, diagonal * 0.18)
    }

    private static func bounds(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func polylineLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        return (1..<points.count).reduce(CGFloat(0)) { partial, index in
            partial + distance(points[index - 1], points[index])
        }
    }

    private static func meanDistance(from points: [CGPoint],
                                     toClosedPolyline polyline: [CGPoint]) -> CGFloat {
        guard polyline.count > 1 else { return .greatestFiniteMagnitude }
        let total = points.reduce(CGFloat(0)) { partial, point in
            var best = CGFloat.greatestFiniteMagnitude
            for index in 1..<polyline.count {
                best = min(best, distanceFromPoint(point,
                                                   toSegmentStart: polyline[index - 1],
                                                   end: polyline[index]))
            }
            return partial + best
        }
        return total / max(CGFloat(points.count), 1)
    }

    private static func meanDistance(from points: [CGPoint],
                                     toOpenPolyline polyline: [CGPoint]) -> CGFloat {
        guard polyline.count > 1 else { return .greatestFiniteMagnitude }
        let total = points.reduce(CGFloat(0)) { partial, point in
            var best = CGFloat.greatestFiniteMagnitude
            for index in 1..<polyline.count {
                best = min(best, distanceFromPoint(point,
                                                   toSegmentStart: polyline[index - 1],
                                                   end: polyline[index]))
            }
            return partial + best
        }
        return total / max(CGFloat(points.count), 1)
    }

    private static func polygonArea(_ vertices: [CGPoint]) -> CGFloat {
        guard vertices.count >= 3 else { return 0 }
        var area: CGFloat = 0
        for index in vertices.indices {
            let current = vertices[index]
            let next = vertices[(index + 1) % vertices.count]
            area += current.x * next.y - next.x * current.y
        }
        return abs(area) / 2
    }

    private static func distanceFromPoint(_ point: CGPoint,
                                          toSegmentStart start: CGPoint,
                                          end: CGPoint) -> CGFloat {
        let segment = vector(from: start, to: end)
        let lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy
        guard lengthSquared > 0 else { return distance(point, start) }

        let pointVector = vector(from: start, to: point)
        let progress = max(0, min(1, dot(pointVector, segment) / lengthSquared))
        let projection = CGPoint(x: start.x + segment.dx * progress,
                                 y: start.y + segment.dy * progress)
        return distance(point, projection)
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func vector(from start: CGPoint, to end: CGPoint) -> CGVector {
        CGVector(dx: end.x - start.x, dy: end.y - start.y)
    }

    private static func normalized(_ vector: CGVector) -> CGVector {
        let length = hypot(vector.dx, vector.dy)
        guard length > 0 else { return .zero }
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }

    private static func cosineBetween(_ lhs: CGVector, _ rhs: CGVector) -> CGFloat {
        let lhsLength = hypot(lhs.dx, lhs.dy)
        let rhsLength = hypot(rhs.dx, rhs.dy)
        guard lhsLength > 0, rhsLength > 0 else { return 1 }
        return dot(lhs, rhs) / (lhsLength * rhsLength)
    }

    private static func dot(_ point: CGPoint, _ vector: CGVector) -> CGFloat {
        point.x * vector.dx + point.y * vector.dy
    }

    private static func dot(_ lhs: CGVector, _ rhs: CGVector) -> CGFloat {
        lhs.dx * rhs.dx + lhs.dy * rhs.dy
    }

    private static func point(_ vector: CGVector, scaledBy scale: CGFloat) -> CGPoint {
        CGPoint(x: vector.dx * scale, y: vector.dy * scale)
    }

    private static func point(_ lhs: CGVector, scaledBy lhsScale: CGFloat,
                              plus rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.dx * lhsScale + rhs.x, y: lhs.dy * lhsScale + rhs.y)
    }

    private static func offset(_ center: CGPoint,
                               _ firstAxis: CGVector,
                               _ firstAmount: CGFloat,
                               _ secondAxis: CGVector,
                               _ secondAmount: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + firstAxis.dx * firstAmount + secondAxis.dx * secondAmount,
            y: center.y + firstAxis.dy * firstAmount + secondAxis.dy * secondAmount
        )
    }
}

struct DrawingCanvasView: View {
    @EnvironmentObject private var settings: AppSettings
    let drawing: PKDrawing
    let isEditing: Bool
    let canvasScale: CGFloat
    let smartShapeSnappingEnabled: Bool
    let onDrawingChanged: (PKDrawing) -> Void

    @State private var selectedColor = UIColor.systemOrange
    @State private var isPickingColor = false
    @State private var pickedColorRevision = 0

    var body: some View {
        if isEditing {
            ZStack(alignment: .topTrailing) {
                LivePKCanvas(
                    drawing: drawing,
                    smartShapeSnappingEnabled: smartShapeSnappingEnabled,
                    selectedColor: $selectedColor,
                    colorRevision: pickedColorRevision,
                    penConfiguration: settings.drawingPenConfiguration,
                    colorCycleConfiguration: settings.effectiveDrawingColorCycleConfiguration,
                    onDrawingChanged: onDrawingChanged
                )

                HStack(spacing: 6) {
                    DrawingAssistanceButton()

                    DrawingColorPickerButton(
                        selectedColor: $selectedColor,
                        compact: true,
                        isActive: isPickingColor
                    ) {
                        isPickingColor.toggle()
                    }
                    .disabled(settings.effectiveDrawingColorCycleConfiguration.isActive)
                    .opacity(settings.effectiveDrawingColorCycleConfiguration.isActive ? 0.5 : 1)
                }
                .padding(8)

                if isPickingColor {
                    DrawingColorSamplingOverlay(
                        onColorPicked: { color in
                            selectedColor = color
                            pickedColorRevision += 1
                            isPickingColor = false
                        },
                        onCancel: {
                            isPickingColor = false
                        }
                    )
                    .zIndex(2)
                }
            }
        } else {
            DrawingSnapshot(drawing: drawing, canvasScale: canvasScale)
        }
    }

}

// MARK: - Static snapshot
private struct DrawingSnapshot: View {
    let drawing: PKDrawing
    let canvasScale: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var renderedImage: UIImage?

    var body: some View {
        GeometryReader { geo in
            let request = renderRequest(for: geo.size)

            if drawing.strokes.isEmpty {
                Color.clear
            } else if let renderedImage {
                Image(uiImage: renderedImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .task(id: request) {
                        render(request: request, size: geo.size)
                    }
            } else {
                Color.clear
                    .task(id: request) {
                        render(request: request, size: geo.size)
                    }
            }
        }
    }

    private func renderRequest(for size: CGSize) -> DrawingSnapshotRenderRequest {
        let data = drawing.dataRepresentation()
        let zoomBucket = ceil(max(canvasScale, 1) * 2) / 2
        let desiredScale = max(displayScale, 1) * zoomBucket
        let longestSide = max(max(size.width, size.height), 1)
        let renderScale = min(desiredScale, DrawingSnapshotImageCache.maxPixelDimension / longestSide)

        return DrawingSnapshotRenderRequest(
            drawingHash: data.hashValue,
            drawingByteCount: data.count,
            width: Int((size.width * 100).rounded()),
            height: Int((size.height * 100).rounded()),
            scale: Int((max(renderScale, 0.01) * 100).rounded())
        )
    }

    @MainActor
    private func render(request: DrawingSnapshotRenderRequest, size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            renderedImage = nil
            return
        }

        if let cached = DrawingSnapshotImageCache.shared.image(for: request) {
            renderedImage = cached
            return
        }

        let image = drawing.image(
            from: CGRect(origin: .zero, size: size),
            scale: request.renderScale
        )
        DrawingSnapshotImageCache.shared.insert(image, for: request)
        renderedImage = image
    }
}

private struct DrawingSnapshotRenderRequest: Hashable {
    let drawingHash: Int
    let drawingByteCount: Int
    let width: Int
    let height: Int
    let scale: Int

    var renderScale: CGFloat { CGFloat(scale) / 100 }
}

@MainActor
private final class DrawingSnapshotImageCache {
    static let shared = DrawingSnapshotImageCache()
    static let maxPixelDimension: CGFloat = 4_096

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 64 * 1_024 * 1_024
    }

    func image(for request: DrawingSnapshotRenderRequest) -> UIImage? {
        cache.object(forKey: key(for: request))
    }

    func insert(_ image: UIImage, for request: DrawingSnapshotRenderRequest) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key(for: request), cost: cost)
    }

    private func key(for request: DrawingSnapshotRenderRequest) -> NSString {
        "\(request.drawingHash):\(request.drawingByteCount):\(request.width)x\(request.height)@\(request.scale)" as NSString
    }
}

// MARK: - Live PKCanvasView (card drawing)
// The default policy follows the system "Draw with Finger" preference.
// Two-finger pan is handled by PKCanvasView's built-in scroll view —
// it automatically reserves two-finger for scroll when isScrollEnabled=true.
private struct LivePKCanvas: UIViewRepresentable {
    let drawing: PKDrawing
    let smartShapeSnappingEnabled: Bool
    @Binding var selectedColor: UIColor
    let colorRevision: Int
    let penConfiguration: DrawingPenConfiguration
    let colorCycleConfiguration: DrawingColorCycleConfiguration
    let onDrawingChanged: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedColor: $selectedColor,
            penConfiguration: penConfiguration,
            colorCycleConfiguration: colorCycleConfiguration,
            smartShapeSnappingEnabled: smartShapeSnappingEnabled,
            onDrawingChanged: onDrawingChanged
        )
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing         = drawing
        canvas.backgroundColor = .clear
        canvas.isOpaque        = false
        canvas.drawingPolicy   = .default
        canvas.delegate        = context.coordinator
        context.coordinator.canvas = canvas

        // Enable built-in two-finger pan and pinch zoom
        canvas.isScrollEnabled  = true
        canvas.bouncesZoom      = true
        canvas.minimumZoomScale = 0.5
        canvas.maximumZoomScale = 5.0

        let toolPicker = PKToolPicker()
        context.coordinator.toolPicker = toolPicker
        toolPicker.addObserver(canvas)
        toolPicker.addObserver(context.coordinator)
        context.coordinator.rememberPickerSelection(toolPicker)
        context.coordinator.markAppliedColorRevision(colorRevision)
        toolPicker.setVisible(true, forFirstResponder: canvas)
        context.coordinator.syncSelectedColorFromCurrentInkingTool(canvas)
        context.coordinator.updatePenConfiguration(penConfiguration, on: canvas)
        context.coordinator.updateColorCycleConfiguration(
            colorCycleConfiguration,
            on: canvas,
            force: true
        )
        context.coordinator.attachPatternGesture(to: canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.drawingPolicy = .default
        context.coordinator.smartShapeSnappingEnabled = smartShapeSnappingEnabled
        if canvas.drawing.dataRepresentation() != drawing.dataRepresentation()
            && !canvas.isFirstResponder {
            canvas.drawing = drawing
        }
        context.coordinator.applyPickedColorIfNeeded(
            to: canvas,
            selectedColor: selectedColor,
            colorRevision: colorRevision
        )
        context.coordinator.updatePenConfiguration(penConfiguration, on: canvas)
        context.coordinator.updateColorCycleConfiguration(
            colorCycleConfiguration,
            on: canvas
        )
        context.coordinator.toolPicker?.setVisible(true, forFirstResponder: canvas)
        if !canvas.isFirstResponder {
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.flushPendingWork(on: canvas)
        coordinator.detachPatternPreview(from: canvas)
        coordinator.toolPicker?.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker?.removeObserver(coordinator)
        coordinator.toolPicker?.removeObserver(canvas)
        canvas.resignFirstResponder()
    }

    class Coordinator: NSObject, PKCanvasViewDelegate, PKToolPickerObserver {
        @Binding var selectedColor: UIColor
        var penConfiguration: DrawingPenConfiguration
        private var colorCycleState: DrawingColorCycleState
        let onDrawingChanged: (PKDrawing) -> Void
        weak var canvas: PKCanvasView?
        var toolPicker: PKToolPicker?
        var smartShapeSnappingEnabled: Bool {
            didSet {
                shapeSnapController.isEnabled = smartShapeSnappingEnabled
            }
        }
        private var lastAppliedColorRevision = 0
        private var lastPickerToolItemIdentifier: String?
        private var lastPickerInkType: PKInkingTool.InkType?
        private var isApplyingPickedColor = false
        private var isApplyingStrokeProcessing = false
        private var isUsingDrawingTool = false
        private var hasUnpublishedDrawingChanges = false
        private var pendingStrokeBaseline: DrawingStrokeBaseline?
        private var pendingStrokeConfiguration: DrawingPenConfiguration?
        private var pendingReplacementInk: PKInk?
        private var pendingStrokeProcessing: DispatchWorkItem?
        private var pendingDrawingPublication: DispatchWorkItem?
        private var drawingAwaitingPublication: PKDrawing?
        private var lastVisiblePreviewDrawing: PKDrawing?
        private let shapeSnapController = PencilShapeSnapController()
        private let patternPreview = LivePatternStrokePreview()

        init(selectedColor: Binding<UIColor>,
             penConfiguration: DrawingPenConfiguration,
             colorCycleConfiguration: DrawingColorCycleConfiguration,
             smartShapeSnappingEnabled: Bool,
             onDrawingChanged: @escaping (PKDrawing) -> Void) {
            self._selectedColor = selectedColor
            self.penConfiguration = penConfiguration
            self.colorCycleState = DrawingColorCycleState()
            _ = self.colorCycleState.updateConfiguration(
                colorCycleConfiguration,
                force: true
            )
            self.smartShapeSnappingEnabled = smartShapeSnappingEnabled
            self.onDrawingChanged = onDrawingChanged
            self.shapeSnapController.isEnabled = smartShapeSnappingEnabled
        }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            guard !isApplyingStrokeProcessing else { return }
            if hasUnpublishedDrawingChanges {
                shapeSnapController.cancelPendingSnap()
                if patternPreview.isActive {
                    patternPreview.update(with: canvas.drawing, on: canvas)
                }
                if !isUsingDrawingTool {
                    schedulePendingStrokeProcessing(on: canvas)
                }
                return
            }
            if !isUsingDrawingTool,
               patternPreview.isActive,
               canvas.drawing.strokes.contains(where: {
                    $0.ink.color.cgColor.alpha <= 0.01
               }),
               let lastVisiblePreviewDrawing {
                isApplyingStrokeProcessing = true
                canvas.drawing = lastVisiblePreviewDrawing
                canvas.setNeedsDisplay()
                isApplyingStrokeProcessing = false
                return
            }
            onDrawingChanged(canvas.drawing)
            guard !shapeSnapController.isApplyingProgrammaticSnap else { return }
            guard !penConfiguration.usesPattern else {
                shapeSnapController.cancelPendingSnap()
                return
            }
            shapeSnapController.scheduleSnap(on: canvas) { [weak self] snappedDrawing in
                self?.onDrawingChanged(snappedDrawing)
            }
        }

        func canvasViewDidBeginUsingTool(_ canvas: PKCanvasView) {
            cancelScheduledStrokeProcessing()
            cancelScheduledDrawingPublication()
            shapeSnapController.cancelPendingSnap()
            lastVisiblePreviewDrawing = nil
            isUsingDrawingTool = true
            if !hasUnpublishedDrawingChanges {
                pendingStrokeBaseline = canvas.tool is PKInkingTool
                    ? DrawingStrokeBaseline(drawing: canvas.drawing)
                    : nil
                pendingStrokeConfiguration = penConfiguration
                pendingReplacementInk = patternPreview.visibleReplacementInk(
                    fallbackColorHex: colorCycleState.activeColorHex
                )
            }
            hasUnpublishedDrawingChanges = true
            patternPreview.beginGestureStroke(
                at: canvas.drawingGestureRecognizer.location(in: canvas),
                on: canvas
            )
        }

        func canvasViewDidEndUsingTool(_ canvas: PKCanvasView) {
            isUsingDrawingTool = false
            patternPreview.endGestureStroke(cancelled: false, on: canvas)
            if penConfiguration.usesPattern
                || colorCycleState.configuration.isContinuousActive {
                shapeSnapController.cancelPendingSnap()
            }
            schedulePendingStrokeProcessing(on: canvas)
        }

        private func schedulePendingStrokeProcessing(on canvas: PKCanvasView) {
            cancelScheduledStrokeProcessing()
            let work = DispatchWorkItem { [weak self, weak canvas] in
                guard let self, let canvas, !self.isUsingDrawingTool else { return }
                self.pendingStrokeProcessing = nil
                self.finishPendingStrokes(on: canvas)
            }
            pendingStrokeProcessing = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + (
                    patternPreview.isActive
                        ? DrawingInputDebounce.livePreviewFinalization
                        : colorCycleState.configuration.isActive
                            ? 0.015
                        : DrawingInputDebounce.strokeProcessing
                ),
                execute: work
            )
        }

        private func finishPendingStrokes(on canvas: PKCanvasView) {
            let baseline = pendingStrokeBaseline
            let configuration = pendingStrokeConfiguration ?? penConfiguration
            let replacementInk = pendingReplacementInk
            pendingStrokeBaseline = nil
            pendingStrokeConfiguration = nil
            pendingReplacementInk = nil
            hasUnpublishedDrawingChanges = false

            let drawingBeforeProcessing = canvas.drawing
            let drawingForProcessing: PKDrawing
            if (configuration.usesPattern
                || colorCycleState.configuration.isContinuousActive),
               let snappedDrawing = shapeSnapController
                .drawingBySnappingLatestStroke(in: drawingBeforeProcessing) {
                drawingForProcessing = snappedDrawing
            } else {
                drawingForProcessing = drawingBeforeProcessing
            }

            var finalDrawing = drawingForProcessing
            if let baseline,
               let processed = DrawingStrokeProcessor.processingLatestStroke(
                   in: drawingForProcessing,
                   since: baseline,
                   configuration: configuration,
                   replacementInk: replacementInk,
                   colorCycleConfiguration: colorCycleState.configuration
               ) {
                finalDrawing = processed
            }
            if let replacementInk,
               let recovered = DrawingStrokeProcessor.recoveringInvisiblePreviewStrokes(
                    in: finalDrawing,
                    configuration: configuration,
                    replacementInk: replacementInk,
                    colorCycleConfiguration: colorCycleState.configuration
               ) {
                finalDrawing = recovered
            }

            if finalDrawing.dataRepresentation() != drawingBeforeProcessing.dataRepresentation() {
                isApplyingStrokeProcessing = true
                canvas.drawing = finalDrawing
                canvas.setNeedsDisplay()
                isApplyingStrokeProcessing = false
            }

            patternPreview.clear()
            if patternPreview.isActive {
                lastVisiblePreviewDrawing = finalDrawing
            }
            if baseline != nil,
               colorCycleState.recordCompletedStroke() {
                applyActiveCycleColor(to: canvas)
            }
            scheduleDrawingPublication(finalDrawing)
            guard !configuration.usesPattern,
                  !colorCycleState.configuration.isContinuousActive else { return }
            shapeSnapController.scheduleSnap(on: canvas) { [weak self] snappedDrawing in
                self?.scheduleDrawingPublication(snappedDrawing)
            }
        }

        private func cancelScheduledStrokeProcessing() {
            pendingStrokeProcessing?.cancel()
            pendingStrokeProcessing = nil
        }

        private func cancelPendingStrokeProcessing() {
            cancelScheduledStrokeProcessing()
            pendingStrokeBaseline = nil
            pendingStrokeConfiguration = nil
            pendingReplacementInk = nil
            hasUnpublishedDrawingChanges = false
            isUsingDrawingTool = false
        }

        private func scheduleDrawingPublication(_ drawing: PKDrawing) {
            cancelScheduledDrawingPublication()
            drawingAwaitingPublication = drawing
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingDrawingPublication = nil
                self.publishPendingDrawing()
            }
            pendingDrawingPublication = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + DrawingInputDebounce.drawingPublication,
                execute: work
            )
        }

        private func cancelScheduledDrawingPublication() {
            pendingDrawingPublication?.cancel()
            pendingDrawingPublication = nil
        }

        private func publishPendingDrawing() {
            guard let drawing = drawingAwaitingPublication else { return }
            drawingAwaitingPublication = nil
            onDrawingChanged(drawing)
        }

        func flushPendingWork(on canvas: PKCanvasView) {
            cancelScheduledStrokeProcessing()
            if hasUnpublishedDrawingChanges, !isUsingDrawingTool {
                finishPendingStrokes(on: canvas)
            }
            cancelPendingStrokeProcessing()
            shapeSnapController.cancelPendingSnap()
            cancelScheduledDrawingPublication()
            publishPendingDrawing()
        }

        func cancelPendingShapeSnap() {
            shapeSnapController.cancelPendingSnap()
        }

        func updatePenConfiguration(
            _ configuration: DrawingPenConfiguration,
            on canvas: PKCanvasView
        ) {
            penConfiguration = configuration
            patternPreview.synchronize(configuration: configuration, on: canvas)
            if configuration.usesPattern {
                cancelPendingShapeSnap()
            }
        }

        func updateColorCycleConfiguration(
            _ configuration: DrawingColorCycleConfiguration,
            on canvas: PKCanvasView,
            force: Bool = false
        ) {
            let shouldApplyFirstColor = colorCycleState.updateConfiguration(
                configuration,
                force: force
            )
            patternPreview.synchronize(
                colorConfiguration: colorCycleState.configuration,
                on: canvas
            )
            if colorCycleState.configuration.isContinuousActive {
                cancelPendingShapeSnap()
            }
            if shouldApplyFirstColor {
                applyActiveCycleColor(to: canvas)
            }
        }

        func attachPatternGesture(to canvas: PKCanvasView) {
            canvas.drawingGestureRecognizer.addTarget(
                self,
                action: #selector(handlePatternDrawingGesture(_:))
            )
        }

        func detachPatternPreview(from canvas: PKCanvasView) {
            canvas.drawingGestureRecognizer.removeTarget(
                self,
                action: #selector(handlePatternDrawingGesture(_:))
            )
            patternPreview.detach()
        }

        @objc private func handlePatternDrawingGesture(_ recognizer: UIGestureRecognizer) {
            guard let canvas else { return }
            let location = recognizer.location(in: canvas)
            switch recognizer.state {
            case .began:
                patternPreview.beginGestureStroke(at: location, on: canvas)
            case .changed:
                patternPreview.continueGestureStroke(at: location, on: canvas)
            case .ended:
                patternPreview.endGestureStroke(cancelled: false, on: canvas)
            case .cancelled, .failed:
                patternPreview.endGestureStroke(cancelled: true, on: canvas)
            case .possible:
                break
            @unknown default:
                patternPreview.endGestureStroke(cancelled: true, on: canvas)
            }
        }

        func toolPickerSelectedToolDidChange(_ toolPicker: PKToolPicker) {
            handleToolPickerChange(toolPicker)
        }

        @available(iOS 18.0, *)
        func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker) {
            handleToolPickerChange(toolPicker)
        }

        func markAppliedColorRevision(_ revision: Int) {
            lastAppliedColorRevision = revision
        }

        func applyPickedColorIfNeeded(to canvas: PKCanvasView,
                                      selectedColor: UIColor,
                                      colorRevision: Int) {
            guard colorRevision != lastAppliedColorRevision else { return }
            applyColor(selectedColor, to: canvas, switchToPenIfNeeded: true)
            lastAppliedColorRevision = colorRevision
        }

        func syncSelectedColorFromCurrentInkingTool(_ canvas: PKCanvasView) {
            guard !isApplyingPickedColor,
                  let color = currentInkingTool(for: canvas)?.color.withAlphaComponent(1),
                  !selectedColor.isDrawingEquivalent(to: color) else { return }
            selectedColor = color
        }

        func rememberPickerSelection(_ toolPicker: PKToolPicker) {
            _ = updatePickerSelectionState(toolPicker)
        }

        private func handleToolPickerChange(_ toolPicker: PKToolPicker) {
            _ = updatePickerSelectionState(toolPicker)
            let selectedInkingTool = pickerInkingTool(from: toolPicker)
            if selectedInkingTool == nil {
                shapeSnapController.cancelPendingSnap()
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, let canvas = self.canvas else { return }
                var appliedCycleColor = false

                if let selectedInkingTool {
                    let toolColor = selectedInkingTool.color.withAlphaComponent(1)
                    if self.colorCycleState.configuration.isActive,
                       let cycleColor = self.activeCycleColor,
                       !cycleColor.isDrawingEquivalent(to: toolColor) {
                        self.applyColor(cycleColor, to: canvas, switchToPenIfNeeded: false)
                        appliedCycleColor = true
                    } else if !self.selectedColor.isDrawingEquivalent(to: toolColor) {
                        self.selectedColor = toolColor
                    }
                } else {
                    self.syncSelectedColorFromCurrentInkingTool(canvas)
                }
                if !appliedCycleColor {
                    self.patternPreview.selectedInkingToolDidChange(
                        selectedInkingTool,
                        on: canvas
                    )
                }
            }
        }

        private func applyColor(_ selectedColor: UIColor,
                                to canvas: PKCanvasView,
                                switchToPenIfNeeded: Bool) {
            guard !isApplyingPickedColor else { return }

            let color = selectedColor.withAlphaComponent(1)
            let nextTool: PKInkingTool

            if let inkingTool = canvas.tool as? PKInkingTool {
                let alpha = patternPreview.visibleInkAlpha
                    ?? inkingTool.color.cgColor.alpha
                nextTool = PKInkingTool(
                    inkingTool.inkType,
                    color: color.withAlphaComponent(alpha),
                    width: inkingTool.width
                )
            } else if let pickerTool = pickerInkingTool(from: toolPicker) {
                nextTool = PKInkingTool(
                    pickerTool.inkType,
                    color: color.withAlphaComponent(pickerTool.color.cgColor.alpha),
                    width: pickerTool.width
                )
            } else if switchToPenIfNeeded {
                nextTool = PKInkingTool(.pen, color: color, width: 5)
            } else {
                return
            }

            isApplyingPickedColor = true
            canvas.tool = nextTool
            isApplyingPickedColor = false
            patternPreview.selectedInkingToolDidChange(nextTool, on: canvas)
        }

        private var activeCycleColor: UIColor? {
            guard let hex = colorCycleState.activeColorHex else { return nil }
            return UIColor(ShapeColorPalette.color(named: hex, fallback: .orange))
                .withAlphaComponent(1)
        }

        private func applyActiveCycleColor(to canvas: PKCanvasView) {
            guard let color = activeCycleColor else { return }
            if !selectedColor.isDrawingEquivalent(to: color) {
                selectedColor = color
            }
            applyColor(color, to: canvas, switchToPenIfNeeded: false)
        }

        private func currentInkingTool(for canvas: PKCanvasView) -> PKInkingTool? {
            if let inkingTool = canvas.tool as? PKInkingTool { return inkingTool }
            return pickerInkingTool(from: toolPicker)
        }

        private func pickerInkingTool(from toolPicker: PKToolPicker?) -> PKInkingTool? {
            guard let toolPicker else { return nil }
            if #available(iOS 18.0, *) {
                return (toolPicker.selectedToolItem as? PKToolPickerInkingItem)?.inkingTool
            } else {
                return toolPicker.selectedTool as? PKInkingTool
            }
        }

        private func updatePickerSelectionState(_ toolPicker: PKToolPicker) -> Bool {
            let previousIdentifier = lastPickerToolItemIdentifier
            let previousInkType = lastPickerInkType

            if #available(iOS 18.0, *) {
                lastPickerToolItemIdentifier = toolPicker.selectedToolItem.identifier
            }
            lastPickerInkType = pickerInkingTool(from: toolPicker)?.inkType

            if #available(iOS 18.0, *) {
                return previousIdentifier != nil &&
                    previousIdentifier != lastPickerToolItemIdentifier
            }
            return previousInkType != nil && previousInkType != lastPickerInkType
        }
    }
}

extension UIColor {
    fileprivate func isDrawingEquivalent(to other: UIColor) -> Bool {
        guard let lhs = drawingRGBAComponents(),
              let rhs = other.drawingRGBAComponents() else {
            return cgColor == other.cgColor
        }

        return zip(lhs, rhs).allSatisfy { abs($0 - $1) < 0.001 }
    }

    fileprivate func drawingRGBAComponents() -> [CGFloat]? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        return [red, green, blue, alpha]
    }
}

#else

// MARK: - macOS
struct DrawingCanvasView: View {
    let drawing: PKDrawing
    let isEditing: Bool
    let canvasScale: CGFloat
    let smartShapeSnappingEnabled: Bool
    let onDrawingChanged: (PKDrawing) -> Void

    var body: some View {
        if isEditing {
            MacDrawingEditor(
                drawing: drawing,
                canvasScale: canvasScale,
                onDrawingChanged: onDrawingChanged
            )
        } else {
            MacDrawingSnapshot(drawing: drawing, canvasScale: canvasScale)
        }
    }
}

struct MacDrawingToolState: Equatable {
    var ink: MacDrawingInk = .pen
    var color: MacDrawingColor = .adaptive
    var sampledColor: MacDrawingSampledColor?
    var usesSampledColor = false
    var width: CGFloat = 4
    var opacity: CGFloat = 1
    var smoothing: CGFloat = 0.35
    var lineStyle: DrawingStrokeStyle = .solid
    var patternWidth: CGFloat = 4
    var dashLength: CGFloat = 12
    var patternGap: CGFloat = 8
    var eraserWidth: CGFloat = 24
    var isErasing = false

    var penConfiguration: DrawingPenConfiguration {
        DrawingPenConfiguration(
            smoothing: Double(smoothing),
            lineStyle: lineStyle,
            patternWidth: Double(patternWidth),
            dashLength: Double(dashLength),
            patternGap: Double(patternGap)
        )
    }

    func strokeNSColor(colorScheme: ColorScheme) -> NSColor {
        if usesSampledColor, let sampledColor {
            return sampledColor.nsColor
        }
        return color.nsColor(colorScheme: colorScheme)
    }

    func strokeSwatchColor(colorScheme: ColorScheme) -> Color {
        if usesSampledColor, let sampledColor {
            return sampledColor.swiftUIColor
        }
        return color.swatchColor(colorScheme: colorScheme)
    }

}

struct MacDrawingSampledColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init?(nsColor: NSColor) {
        guard let rgbColor = nsColor.usingColorSpace(.deviceRGB)
            ?? nsColor.usingColorSpace(.sRGB) else { return nil }
        self.red = rgbColor.redComponent
        self.green = rgbColor.greenComponent
        self.blue = rgbColor.blueComponent
        self.alpha = rgbColor.alphaComponent
    }

    var nsColor: NSColor {
        NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha)
    }

    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }
}

enum MacDrawingInk: String, CaseIterable, Identifiable {
    case pen
    case monoline
    case pencil
    case marker
    case fountainPen
    case watercolor
    case crayon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen:         return "Pen"
        case .monoline:    return "Monoline"
        case .pencil:      return "Pencil"
        case .marker:      return "Marker"
        case .fountainPen: return "Fountain Pen"
        case .watercolor:  return "Watercolor"
        case .crayon:      return "Crayon"
        }
    }

    var icon: String {
        switch self {
        case .pen:         return "pencil.tip"
        case .monoline:    return "scribble.variable"
        case .pencil:      return "pencil"
        case .marker:      return "highlighter"
        case .fountainPen: return "paintbrush.pointed"
        case .watercolor:  return "paintbrush"
        case .crayon:      return "scribble"
        }
    }

    var inkType: PKInkingTool.InkType {
        switch self {
        case .pen:         return .pen
        case .monoline:    return .monoline
        case .pencil:      return .pencil
        case .marker:      return .marker
        case .fountainPen: return .fountainPen
        case .watercolor:  return .watercolor
        case .crayon:      return .crayon
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .pen:         return 4
        case .monoline:    return 5
        case .pencil:      return 5
        case .marker:      return 12
        case .fountainPen: return 4
        case .watercolor:  return 10
        case .crayon:      return 8
        }
    }

}

enum MacDrawingColor: String, CaseIterable, Identifiable {
    case adaptive
    case black
    case white
    case gray
    case red
    case orange
    case yellow
    case green
    case blue
    case purple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adaptive: return "Auto"
        case .black:    return "Black"
        case .white:    return "White"
        case .gray:     return "Gray"
        case .red:      return "Red"
        case .orange:   return "Orange"
        case .yellow:   return "Yellow"
        case .green:    return "Green"
        case .blue:     return "Blue"
        case .purple:   return "Purple"
        }
    }

    func nsColor(colorScheme: ColorScheme) -> NSColor {
        switch self {
        case .adaptive: return colorScheme == .dark ? .white : .black
        case .black:    return .black
        case .white:    return .white
        case .gray:     return .systemGray
        case .red:      return .systemRed
        case .orange:   return .systemOrange
        case .yellow:   return .systemYellow
        case .green:    return .systemGreen
        case .blue:     return .systemBlue
        case .purple:   return .systemPurple
        }
    }

    func swatchColor(colorScheme: ColorScheme) -> Color {
        Color(nsColor: nsColor(colorScheme: colorScheme))
    }
}

struct MacDrawingEditor: View {
    @EnvironmentObject private var settings: AppSettings
    let drawing: PKDrawing
    let canvasScale: CGFloat
    let onDrawingChanged: (PKDrawing) -> Void

    @State private var tool = MacDrawingToolState()
    @State private var colorCycleState = DrawingColorCycleState()

    var body: some View {
        ZStack {
            MacFreehandPKDrawingView(
                drawing: drawing,
                tool: tool,
                canvasScale: canvasScale,
                colorCycleConfiguration: settings.effectiveDrawingColorCycleConfiguration,
                onDrawingChanged: onDrawingChanged,
                onStrokeCompleted: advanceColorCycle
            )

            VStack {
                Spacer()
                MacDrawingToolControls(tool: $tool)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
            .zIndex(1)
        }
        .onAppear {
            syncDrawingAssistance(settings.drawingPenConfiguration)
            syncColorCycle(settings.effectiveDrawingColorCycleConfiguration, force: true)
        }
        .onChange(of: settings.drawingPenConfiguration) { _, configuration in
            syncDrawingAssistance(configuration)
        }
        .onChange(of: settings.effectiveDrawingColorCycleConfiguration) { _, configuration in
            syncColorCycle(configuration)
        }
    }

    private func syncDrawingAssistance(_ configuration: DrawingPenConfiguration) {
        let normalized = configuration.normalized
        tool.smoothing = CGFloat(normalized.smoothing)
        tool.lineStyle = normalized.lineStyle
        tool.patternWidth = CGFloat(normalized.patternWidth)
        tool.dashLength = CGFloat(normalized.dashLength)
        tool.patternGap = CGFloat(normalized.patternGap)
    }

    private func syncColorCycle(
        _ configuration: DrawingColorCycleConfiguration,
        force: Bool = false
    ) {
        guard colorCycleState.updateConfiguration(configuration, force: force) else { return }
        applyActiveCycleColor()
    }

    private func advanceColorCycle() {
        guard !tool.isErasing,
              colorCycleState.recordCompletedStroke() else { return }
        applyActiveCycleColor()
    }

    private func applyActiveCycleColor() {
        guard let hex = colorCycleState.activeColorHex,
              let sampledColor = MacDrawingSampledColor(
                nsColor: NSColor(ShapeColorPalette.color(named: hex, fallback: .orange))
              ) else { return }
        tool.sampledColor = sampledColor
        tool.usesSampledColor = true
    }
}

private struct MacDrawingToolControls: View {
    @Binding var tool: MacDrawingToolState
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    private var activeWidth: Binding<Double> {
        Binding(
            get: {
                if tool.isErasing {
                    return Double(tool.eraserWidth)
                }
                if tool.lineStyle != .solid {
                    return settings.drawingPatternWidth
                }
                return Double(tool.width)
            },
            set: { value in
                if tool.isErasing {
                    tool.eraserWidth = CGFloat(value)
                } else if tool.lineStyle != .solid {
                    settings.drawingPatternWidth = value
                    tool.patternWidth = CGFloat(settings.drawingPatternWidth)
                } else {
                    tool.width = CGFloat(value)
                }
            }
        )
    }

    private var widthRange: ClosedRange<Double> {
        if tool.isErasing {
            return 8...60
        }
        if tool.lineStyle != .solid {
            return DrawingPenConfiguration.patternWidthRange
        }
        return 1...28
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(MacDrawingInk.allCases) { ink in
                        toolButton(
                            icon: ink.icon,
                            isSelected: !tool.isErasing && tool.ink == ink,
                            help: ink.title
                        ) {
                            tool.isErasing = false
                            tool.ink = ink
                            tool.width = ink.defaultWidth
                        }
                    }

                    toolButton(
                        icon: "eraser",
                        isSelected: tool.isErasing,
                        help: "Eraser"
                    ) {
                        tool.isErasing = true
                    }
                }

                Divider().frame(height: 24)

                HStack(spacing: 5) {
                    ForEach(MacDrawingColor.allCases) { color in
                        colorButton(color)
                    }

                    sampleColorButton
                }
                .disabled(settings.effectiveDrawingColorCycleConfiguration.isActive)
                .opacity(
                    tool.isErasing || settings.effectiveDrawingColorCycleConfiguration.isActive
                        ? 0.45
                        : 1
                )

                Divider().frame(height: 24)

                Slider(value: activeWidth, in: widthRange)
                    .frame(width: 96)
                    .help(tool.isErasing ? "Eraser Size" : "Stroke Width")

                DrawingAssistanceButton(arrowEdge: .bottom)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func toolButton(icon: String, isSelected: Bool, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 30, height: 28)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func colorButton(_ color: MacDrawingColor) -> some View {
        Button {
            tool.isErasing = false
            tool.usesSampledColor = false
            tool.color = color
        } label: {
            Circle()
                .fill(color.swatchColor(colorScheme: colorScheme))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(color == .white ? 0.35 : 0.12), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .frame(width: 26, height: 26)
                        .opacity(tool.color == color && !tool.isErasing && !tool.usesSampledColor ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .help(color.title)
    }

    private var sampleColorButton: some View {
        Button {
            tool.isErasing = false
            NSColorSampler().show { selectedColor in
                guard let selectedColor,
                      let sampledColor = MacDrawingSampledColor(nsColor: selectedColor) else { return }
                tool.sampledColor = sampledColor
                tool.usesSampledColor = true
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "eyedropper.halffull")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tool.usesSampledColor && !tool.isErasing ? Color.white : Color.primary)
                    .frame(width: 30, height: 28)
                    .background(
                        tool.usesSampledColor && !tool.isErasing
                            ? Color.accentColor
                            : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 7)
                    )

                Circle()
                    .fill(tool.strokeSwatchColor(colorScheme: colorScheme))
                    .frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.75))
                    .offset(x: 1, y: 1)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 32, height: 28)
        .help("Pick Color from Screen")
    }
}

private struct MacFreehandPKDrawingView: View {
    let drawing: PKDrawing
    let tool: MacDrawingToolState
    let canvasScale: CGFloat
    let colorCycleConfiguration: DrawingColorCycleConfiguration
    var onDrawingChanged: (PKDrawing) -> Void
    var onStrokeCompleted: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var workingDrawing = PKDrawing()
    @State private var committedDrawing = PKDrawing()
    @State private var currentPoints: [CGPoint] = []
    @State private var isDrawing = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if workingDrawing.strokes.isEmpty {
                    Color.clear
                } else {
                    MacDrawingSnapshot(drawing: workingDrawing, canvasScale: canvasScale)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(drawingGesture)
            .onAppear { syncFromExternalDrawing(drawing) }
            .onChange(of: drawing) { _, newValue in
                guard !isDrawing else { return }
                syncFromExternalDrawing(newValue)
            }
        }
    }

    private var strokeColor: NSColor {
        tool.strokeNSColor(colorScheme: colorScheme)
            .withAlphaComponent(tool.opacity)
    }

    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !isDrawing {
                    isDrawing = true
                    committedDrawing = workingDrawing
                    currentPoints = [value.startLocation]
                }

                appendPointIfNeeded(value.location)
                workingDrawing = drawingAfterCurrentGesture()
            }
            .onEnded { value in
                appendPointIfNeeded(value.location)
                let completedStroke = !tool.isErasing && currentPoints.count > 1
                let finalDrawing = drawingAfterCurrentGesture()
                workingDrawing = finalDrawing
                committedDrawing = finalDrawing
                currentPoints = []
                isDrawing = false
                onDrawingChanged(finalDrawing)
                if completedStroke {
                    onStrokeCompleted()
                }
            }
    }

    private func syncFromExternalDrawing(_ newValue: PKDrawing) {
        workingDrawing = newValue
        committedDrawing = newValue
    }

    private func appendPointIfNeeded(_ point: CGPoint) {
        guard let lastPoint = currentPoints.last else {
            currentPoints.append(point)
            return
        }

        let distance = hypot(point.x - lastPoint.x, point.y - lastPoint.y)
        if distance >= 0.75 {
            currentPoints.append(point)
        }
    }

    private func drawingAfterCurrentGesture() -> PKDrawing {
        tool.isErasing ? drawingByErasingCurrentPath() : drawingByAppendingCurrentStroke()
    }

    private func drawingByAppendingCurrentStroke() -> PKDrawing {
        guard currentPoints.count > 1 else { return committedDrawing }

        let renderedPoints = DrawingStrokeProcessor.smoothedLocations(
            currentPoints,
            amount: tool.smoothing
        )
        let strokePoints = renderedPoints.enumerated().map { index, point in
            PKStrokePoint(
                location: point,
                timeOffset: TimeInterval(index) * 0.01,
                size: CGSize(width: tool.width, height: tool.width),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: strokePoints, creationDate: Date())
        let stroke = PKStroke(
            ink: PKInk(tool.ink.inkType, color: strokeColor),
            path: path,
            transform: .identity,
            mask: nil
        )

        var renderedStrokes = DrawingStrokeProcessor.applyingLineStyle(
            to: stroke,
            configuration: tool.penConfiguration
        )
        if colorCycleConfiguration.isContinuousActive {
            renderedStrokes = DrawingStrokeProcessor.applyingContinuousColors(
                to: renderedStrokes,
                configuration: colorCycleConfiguration,
                matchSourceThickness: !tool.penConfiguration.usesPattern
            )
        }
        return PKDrawing(strokes: committedDrawing.strokes + renderedStrokes)
    }

    private func drawingByErasingCurrentPath() -> PKDrawing {
        guard !currentPoints.isEmpty else { return committedDrawing }

        let radius = max(tool.eraserWidth / 2, 4)
        let remainingStrokes = committedDrawing.strokes.filter { stroke in
            !strokeIntersectsEraser(stroke, radius: radius)
        }
        return PKDrawing(strokes: remainingStrokes)
    }

    private func strokeIntersectsEraser(_ stroke: PKStroke, radius: CGFloat) -> Bool {
        let expandedBounds = stroke.renderBounds.insetBy(dx: -radius, dy: -radius)
        guard currentPoints.contains(where: { expandedBounds.contains($0) }) else {
            return false
        }

        var previousPoint: CGPoint?
        for strokePoint in stroke.path {
            let location = strokePoint.location.applying(stroke.transform)

            for eraserPoint in currentPoints {
                if distance(from: eraserPoint, to: location) <= radius {
                    return true
                }

                if let previousPoint,
                   distance(from: eraserPoint, toSegmentStart: previousPoint, end: location) <= radius {
                    return true
                }
            }

            previousPoint = location
        }

        return false
    }

    private func distance(from a: CGPoint, to b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func distance(from point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(from: point, to: start) }

        let rawProjection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let projection = min(1, max(0, rawProjection))
        let closest = CGPoint(x: start.x + projection * dx, y: start.y + projection * dy)
        return distance(from: point, to: closest)
    }
}

private struct MacDrawingSnapshot: View {
    let drawing: PKDrawing
    let canvasScale: CGFloat

    @State private var renderedImage: NSImage?

    var body: some View {
        GeometryReader { geo in
            let request = renderRequest(for: geo.size)

            if drawing.strokes.isEmpty {
                Color.clear
            } else if let renderedImage {
                Image(nsImage: renderedImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .task(id: request) {
                        render(request: request, size: geo.size)
                    }
            } else {
                Color.clear
                    .task(id: request) {
                        render(request: request, size: geo.size)
                    }
            }
        }
    }

    private func renderRequest(for size: CGSize) -> MacDrawingSnapshotRenderRequest {
        let data = drawing.dataRepresentation()
        let zoomBucket = ceil(max(canvasScale, 1) * 2) / 2
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let desiredScale = max(backingScale, 1) * zoomBucket
        let longestSide = max(max(size.width, size.height), 1)
        let renderScale = min(desiredScale, MacDrawingSnapshotImageCache.maxPixelDimension / longestSide)

        return MacDrawingSnapshotRenderRequest(
            drawingHash: data.hashValue,
            drawingByteCount: data.count,
            width: Int((size.width * 100).rounded()),
            height: Int((size.height * 100).rounded()),
            scale: Int((max(renderScale, 0.01) * 100).rounded())
        )
    }

    @MainActor
    private func render(request: MacDrawingSnapshotRenderRequest, size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            renderedImage = nil
            return
        }

        if let cached = MacDrawingSnapshotImageCache.shared.image(for: request) {
            renderedImage = cached
            return
        }

        let image = drawing.image(
            from: CGRect(origin: .zero, size: size),
            scale: request.renderScale
        )
        MacDrawingSnapshotImageCache.shared.insert(image, for: request)
        renderedImage = image
    }
}

private struct MacDrawingSnapshotRenderRequest: Hashable {
    let drawingHash: Int
    let drawingByteCount: Int
    let width: Int
    let height: Int
    let scale: Int

    var renderScale: CGFloat { CGFloat(scale) / 100 }
}

@MainActor
private final class MacDrawingSnapshotImageCache {
    static let shared = MacDrawingSnapshotImageCache()
    static let maxPixelDimension: CGFloat = 4_096

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 64 * 1_024 * 1_024
    }

    func image(for request: MacDrawingSnapshotRenderRequest) -> NSImage? {
        cache.object(forKey: key(for: request))
    }

    func insert(_ image: NSImage, for request: MacDrawingSnapshotRenderRequest) {
        let pixelWidth = max(1, Int(image.size.width * request.renderScale))
        let pixelHeight = max(1, Int(image.size.height * request.renderScale))
        cache.setObject(image, forKey: key(for: request), cost: pixelWidth * pixelHeight * 4)
    }

    private func key(for request: MacDrawingSnapshotRenderRequest) -> NSString {
        "\(request.drawingHash):\(request.drawingByteCount):\(request.width)x\(request.height)@\(request.scale)" as NSString
    }
}

#endif
