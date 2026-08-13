import Foundation
import CoreGraphics
import PencilKit
import SwiftUI
#if os(iOS)
import QuartzCore
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum DrawingStrokeStyle: String, CaseIterable, Identifiable {
    case solid
    case dotted
    case dashed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid:  return "Solid"
        case .dotted: return "Dotted"
        case .dashed: return "Dashed"
        }
    }

    var icon: String {
        switch self {
        case .solid:  return "pencil.tip"
        case .dotted: return "ellipsis"
        case .dashed: return "line.3.horizontal"
        }
    }
}

struct DrawingPenConfiguration: Equatable {
    static let smoothingRange: ClosedRange<Double> = 0...1
    static let patternWidthRange: ClosedRange<Double> = 1...24
    static let dashLengthRange: ClosedRange<Double> = 2...40
    static let patternGapRange: ClosedRange<Double> = 1...40
    static let `default` = DrawingPenConfiguration(
        smoothing: 0.35,
        lineStyle: .solid,
        patternWidth: 4,
        dashLength: 12,
        patternGap: 8
    )

    var smoothing: Double
    var lineStyle: DrawingStrokeStyle
    var patternWidth: Double
    var dashLength: Double
    var patternGap: Double

    init(
        smoothing: Double,
        lineStyle: DrawingStrokeStyle = .solid,
        patternWidth: Double = 4,
        dashLength: Double = 12,
        patternGap: Double = 8
    ) {
        self.smoothing = smoothing
        self.lineStyle = lineStyle
        self.patternWidth = patternWidth
        self.dashLength = dashLength
        self.patternGap = patternGap
    }

    var normalized: DrawingPenConfiguration {
        DrawingPenConfiguration(
            smoothing: Self.smoothingRange.clamped(smoothing),
            lineStyle: lineStyle,
            patternWidth: Self.patternWidthRange.clamped(patternWidth),
            dashLength: Self.dashLengthRange.clamped(dashLength),
            patternGap: Self.patternGapRange.clamped(patternGap)
        )
    }

    var usesPattern: Bool { lineStyle != .solid }

    fileprivate var visiblePatternLength: CGFloat {
        switch lineStyle {
        case .solid:
            return .greatestFiniteMagnitude
        case .dotted:
            // A very short path with round ink caps renders as a clean dot.
            return CGFloat(min(max(patternWidth * 0.15, 0.65), 1.5))
        case .dashed:
            return CGFloat(dashLength)
        }
    }

    fileprivate var hiddenPatternLength: CGFloat {
        // PencilKit's rounded caps extend by roughly half the stroke width on
        // either side. Including the width keeps the visible blank gap close
        // to the value selected by the user.
        CGFloat(patternGap + patternWidth)
    }
}

enum DrawingColorCycleMode: String, CaseIterable, Codable, Identifiable {
    case byStroke
    case continuous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byStroke:   return "By stroke"
        case .continuous: return "Continuous"
        }
    }
}

enum DrawingContinuousColorSpeed: String, CaseIterable, Codable, Identifiable {
    case slow
    case medium
    case fast

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    /// Drawing-space distance used to blend from one palette color to the next.
    var transitionLength: CGFloat {
        switch self {
        case .slow:   return 180
        case .medium: return 105
        case .fast:   return 55
        }
    }
}

struct DrawingColorCycleConfiguration: Equatable, Codable {
    static let maximumColorCount = 5
    static let strokeIntervalRange = 1...50
    static let `default` = DrawingColorCycleConfiguration(
        isEnabled: false,
        colorHexes: ["#FF9500", "#007AFF", "#AF52DE"],
        strokesPerColor: 3,
        mode: .byStroke,
        continuousSpeed: .medium
    )

    var isEnabled: Bool
    var colorHexes: [String]
    var strokesPerColor: Int
    var mode: DrawingColorCycleMode = .byStroke
    var continuousSpeed: DrawingContinuousColorSpeed = .medium

    var normalized: DrawingColorCycleConfiguration {
        var colors = colorHexes
            .prefix(Self.maximumColorCount)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if colors.isEmpty {
            colors = Self.default.colorHexes
        }

        return DrawingColorCycleConfiguration(
            isEnabled: isEnabled,
            colorHexes: colors,
            strokesPerColor: min(
                Self.strokeIntervalRange.upperBound,
                max(Self.strokeIntervalRange.lowerBound, strokesPerColor)
            ),
            mode: mode,
            continuousSpeed: continuousSpeed
        )
    }

    var isActive: Bool {
        let configuration = normalized
        return configuration.isEnabled && configuration.colorHexes.count >= 2
    }

    var isContinuousActive: Bool {
        isActive && mode == .continuous
    }
}

struct DrawingColorCycleState {
    private(set) var configuration = DrawingColorCycleConfiguration.default
    private(set) var activeColorIndex = 0
    private var completedStrokesForActiveColor = 0

    var activeColorHex: String? {
        guard configuration.isActive,
              configuration.colorHexes.indices.contains(activeColorIndex) else { return nil }
        return configuration.colorHexes[activeColorIndex]
    }

    /// Returns true when callers should apply the first color immediately.
    mutating func updateConfiguration(
        _ newValue: DrawingColorCycleConfiguration,
        force: Bool = false
    ) -> Bool {
        let normalized = newValue.normalized
        guard force || normalized != configuration else { return false }
        configuration = normalized
        activeColorIndex = 0
        completedStrokesForActiveColor = 0
        return normalized.isActive
    }

    /// Returns true when a completed gesture advances to another palette color.
    mutating func recordCompletedStroke() -> Bool {
        guard configuration.isActive, configuration.mode == .byStroke else { return false }
        completedStrokesForActiveColor += 1
        guard completedStrokesForActiveColor >= configuration.strokesPerColor else {
            return false
        }

        completedStrokesForActiveColor = 0
        activeColorIndex = (activeColorIndex + 1) % configuration.colorHexes.count
        return true
    }
}

enum DrawingInputDebounce {
    /// PencilKit can publish one final path update just after it reports that
    /// the Pencil lifted. Give the hidden live-preview ink time to settle
    /// before replacing it with the visible patterned/gradient drawing.
    static let livePreviewFinalization: TimeInterval = 0.045

    /// Keep all expensive PencilKit rewriting out of the gap between letters.
    /// A new touch cancels this work and extends the same batch.
    static let strokeProcessing: TimeInterval = 0.18

    /// SwiftData persistence, undo snapshots, and sync are substantially more
    /// expensive than rendering. Publish them only after the user has paused.
    static let drawingPublication: TimeInterval = 0.8
}

extension ClosedRange where Bound == Double {
    func clamped(_ value: Double) -> Double {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

struct DrawingStrokeBaseline {
    fileprivate let strokeCount: Int
    fileprivate let lastStroke: DrawingStrokeSignature?

    init(drawing: PKDrawing) {
        strokeCount = drawing.strokes.count
        lastStroke = drawing.strokes.last.map(DrawingStrokeSignature.init)
    }
}

private struct DrawingStrokeSignature: Equatable {
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

enum DrawingStrokeProcessor {
    static func processingLatestStroke(
        in drawing: PKDrawing,
        since baseline: DrawingStrokeBaseline,
        configuration: DrawingPenConfiguration,
        replacementInk: PKInk? = nil,
        colorCycleConfiguration: DrawingColorCycleConfiguration? = nil
    ) -> PKDrawing? {
        guard !drawing.strokes.isEmpty else { return nil }

        let startIndex: Int
        if drawing.strokes.count > baseline.strokeCount {
            // If PencilKit had already inserted the first control point when
            // the baseline was captured, that in-progress stroke sits at
            // strokeCount - 1. Include it along with any later rapid strokes.
            let possibleInProgressIndex = baseline.strokeCount - 1
            if possibleInProgressIndex >= 0,
               possibleInProgressIndex < drawing.strokes.count,
               let baselineLastStroke = baseline.lastStroke,
               DrawingStrokeSignature(
                   drawing.strokes[possibleInProgressIndex]
               ) != baselineLastStroke {
                startIndex = possibleInProgressIndex
            } else {
                startIndex = baseline.strokeCount
            }
        } else if let lastStroke = drawing.strokes.last,
                  DrawingStrokeSignature(lastStroke) != baseline.lastStroke {
            // PencilKit can publish an initial control point before it calls
            // canvasViewDidBeginUsingTool. In that case the stroke count does
            // not grow, but the last path and its point count still change.
            startIndex = drawing.strokes.count - 1
        } else {
            return nil
        }

        return processingNewStrokes(
            in: drawing,
            startingAt: startIndex,
            configuration: configuration,
            replacementInk: replacementInk,
            colorCycleConfiguration: colorCycleConfiguration
        )
    }

    static func processingNewStrokes(
        in drawing: PKDrawing,
        startingAt startIndex: Int,
        configuration: DrawingPenConfiguration,
        replacementInk: PKInk? = nil,
        colorCycleConfiguration: DrawingColorCycleConfiguration? = nil
    ) -> PKDrawing? {
        let config = configuration.normalized
        let colorConfig = colorCycleConfiguration?.normalized
        guard startIndex >= 0,
              startIndex < drawing.strokes.count,
              config.smoothing > 0.001
                || config.usesPattern
                || colorConfig?.isContinuousActive == true
        else { return nil }

        let sourceStrokes = drawing.strokes
        var strokes = Array(sourceStrokes[..<startIndex])
        var changed = false

        for index in startIndex..<sourceStrokes.count {
            let original = sourceStrokes[index]
            guard original.mask == nil,
                  let processed = processedStrokes(
                    original,
                    configuration: config,
                    replacementInk: replacementInk,
                    colorCycleConfiguration: colorConfig
                  )
            else {
                strokes.append(original)
                continue
            }
            strokes.append(contentsOf: processed)
            changed = true
        }

        return changed ? PKDrawing(strokes: strokes) : nil
    }

    /// A PencilKit live preview uses almost-transparent ink underneath its
    /// visible overlay. Recover any such strokes before persistence without
    /// touching already-visible marks.
    static func recoveringInvisiblePreviewStrokes(
        in drawing: PKDrawing,
        configuration: DrawingPenConfiguration,
        replacementInk: PKInk,
        colorCycleConfiguration: DrawingColorCycleConfiguration? = nil
    ) -> PKDrawing? {
        let source = drawing.strokes
        guard source.contains(where: {
            $0.ink.color.cgColor.alpha <= 0.01
        }) else { return nil }

        let config = configuration.normalized
        let colorConfig = colorCycleConfiguration?.normalized
        var visibleStrokes: [PKStroke] = []

        for stroke in source {
            guard stroke.ink.color.cgColor.alpha <= 0.01 else {
                visibleStrokes.append(stroke)
                continue
            }

            if stroke.mask == nil,
               let processed = processedStrokes(
                    stroke,
                    configuration: config,
                    replacementInk: replacementInk,
                    colorCycleConfiguration: colorConfig
               ), processed.contains(where: {
                    $0.ink.color.cgColor.alpha > 0.01
               }) {
                visibleStrokes.append(contentsOf: processed)
            } else {
                // Final safety net: preserving the original path in visible
                // ink is preferable to persisting an empty drawing box.
                visibleStrokes.append(
                    PKStroke(
                        ink: replacementInk,
                        path: stroke.path,
                        transform: stroke.transform,
                        mask: stroke.mask,
                        randomSeed: stroke.randomSeed
                    )
                )
            }
        }

        return PKDrawing(strokes: visibleStrokes)
    }

    private static func processedStrokes(
        _ stroke: PKStroke,
        configuration: DrawingPenConfiguration,
        replacementInk: PKInk?,
        colorCycleConfiguration: DrawingColorCycleConfiguration?
    ) -> [PKStroke]? {
        let source = Array(stroke.path)
        guard source.count >= 2 else {
            if let colorCycleConfiguration,
               colorCycleConfiguration.isContinuousActive,
               let firstHex = colorCycleConfiguration.colorHexes.first {
                let sourceInk = replacementInk ?? stroke.ink
                #if os(iOS)
                let color = UIColor(
                    ShapeColorPalette.color(named: firstHex, fallback: .orange)
                ).withAlphaComponent(sourceInk.color.cgColor.alpha)
                #elseif os(macOS)
                let color = NSColor(
                    ShapeColorPalette.color(named: firstHex, fallback: .orange)
                ).withAlphaComponent(sourceInk.color.cgColor.alpha)
                #endif
                return [
                    PKStroke(
                        ink: PKInk(sourceInk.inkType, color: color),
                        path: stroke.path,
                        transform: stroke.transform,
                        mask: stroke.mask,
                        randomSeed: stroke.randomSeed
                    )
                ]
            }
            guard configuration.usesPattern else { return nil }
            return [
                strokeWithUniformWidth(
                    stroke,
                    width: configuration.patternWidth,
                    replacementInk: replacementInk
                )
            ]
        }

        let locations = smoothedLocations(
            source.map(\.location),
            amount: CGFloat(configuration.smoothing)
        )

        let controls = source.indices.map { index -> PKStrokePoint in
            let point = source[index]
            return PKStrokePoint(
                location: locations[index],
                timeOffset: point.timeOffset,
                size: point.size,
                opacity: point.opacity,
                force: point.force,
                azimuth: point.azimuth,
                altitude: point.altitude,
                secondaryScale: point.secondaryScale
            )
        }

        let path = PKStrokePath(
            controlPoints: controls,
            creationDate: stroke.path.creationDate
        )
        let smoothedStroke = PKStroke(
            ink: replacementInk ?? stroke.ink,
            path: path,
            transform: stroke.transform,
            mask: stroke.mask,
            randomSeed: stroke.randomSeed
        )

        let styledStrokes = applyingLineStyle(
            to: smoothedStroke,
            configuration: configuration
        )
        guard let colorCycleConfiguration,
              colorCycleConfiguration.isContinuousActive else {
            return styledStrokes
        }
        return applyingContinuousColors(
            to: styledStrokes,
            configuration: colorCycleConfiguration,
            matchSourceThickness: !configuration.usesPattern
        )
    }

    static func applyingContinuousColors(
        to strokes: [PKStroke],
        configuration: DrawingColorCycleConfiguration,
        matchSourceThickness: Bool = true
    ) -> [PKStroke] {
        let config = configuration.normalized
        guard config.isContinuousActive else { return strokes }

        #if os(iOS)
        let palette = config.colorHexes.map {
            UIColor(ShapeColorPalette.color(named: $0, fallback: .orange))
                .withAlphaComponent(1)
        }
        #elseif os(macOS)
        let palette = config.colorHexes.map {
            NSColor(ShapeColorPalette.color(named: $0, fallback: .orange))
                .usingColorSpace(.deviceRGB) ?? .systemOrange
        }
        #endif

        guard palette.count >= 2 else { return strokes }
        let transitionLength = max(config.continuousSpeed.transitionLength, 1)
        // Eight color samples per transition remains visually smooth while
        // keeping the finalized PKDrawing light enough to pan and zoom. More
        // importantly, samples now span multiple PencilKit control points
        // instead of turning every raw input point into its own PKStroke.
        let sampleLength = max(8, transitionLength / 8)
        let epsilon: CGFloat = 0.0001
        var distanceOffset: CGFloat = 0
        var output: [PKStroke] = []

        for stroke in strokes {
            let points = Array(stroke.path)
            guard points.count >= 2 else {
                output.append(stroke)
                continue
            }
            var coloredSegments: [PKStroke] = []
            var segmentPoints = [points[0]]
            var segmentLength: CGFloat = 0

            func appendColoredSegment() {
                guard segmentPoints.count >= 2,
                      segmentLength > epsilon else { return }

                let colorProgress = (
                    distanceOffset - segmentLength * 0.5
                ) / transitionLength
                let baseIndex = Int(floor(colorProgress)) % palette.count
                let nextIndex = (baseIndex + 1) % palette.count
                let blend = colorProgress - floor(colorProgress)
                let alpha = stroke.ink.color.cgColor.alpha

                #if os(iOS)
                let segmentColor = interpolatedColor(
                    from: palette[baseIndex],
                    to: palette[nextIndex],
                    fraction: blend
                ).withAlphaComponent(alpha)
                #elseif os(macOS)
                let segmentColor = interpolatedColor(
                    from: palette[baseIndex],
                    to: palette[nextIndex],
                    fraction: blend
                ).withAlphaComponent(alpha)
                #endif

                coloredSegments.append(
                    PKStroke(
                        ink: PKInk(stroke.ink.inkType, color: segmentColor),
                        path: PKStrokePath(
                            controlPoints: segmentPoints,
                            creationDate: stroke.path.creationDate
                        ),
                        transform: stroke.transform,
                        mask: stroke.mask,
                        randomSeed: stroke.randomSeed
                            &+ UInt32(output.count + coloredSegments.count)
                    )
                )
            }

            for index in 1..<points.count {
                var cursor = points[index - 1]
                let end = points[index]
                var remaining = pointDistance(cursor.location, end.location)
                guard remaining > epsilon else { continue }

                while remaining > epsilon {
                    let remainingInColorSegment = sampleLength - segmentLength
                    let step = min(remainingInColorSegment, remaining)
                    let fraction = step / remaining
                    let boundary = interpolatedPoint(
                        from: cursor,
                        to: end,
                        fraction: fraction
                    )
                    appendIfDistinct(boundary, to: &segmentPoints)
                    cursor = boundary
                    remaining -= step
                    segmentLength += step
                    distanceOffset += step

                    if segmentLength >= sampleLength - epsilon {
                        appendColoredSegment()
                        segmentPoints = [boundary]
                        segmentLength = 0
                    }
                }
            }

            appendColoredSegment()

            if matchSourceThickness {
                coloredSegments = strokesByMatchingRenderedThickness(
                    coloredSegments,
                    to: stroke
                )
            }
            output.append(contentsOf: coloredSegments)
        }

        return output.isEmpty ? strokes : output
    }

    /// PencilKit gives very short strokes a different rendered footprint than
    /// one continuous stroke. Continuous color is represented by many short
    /// strokes, so adjust their control-point sizes until their measured ink
    /// bounds match the single source stroke that was visible while drawing.
    private static func strokesByMatchingRenderedThickness(
        _ strokes: [PKStroke],
        to source: PKStroke
    ) -> [PKStroke] {
        guard !strokes.isEmpty,
              let centerlineBounds = centerlineBounds(of: source),
              let targetThickness = renderedThickness(
                of: [source],
                around: centerlineBounds
              ),
              targetThickness > 0.01 else {
            return strokes
        }

        var adjusted = strokes
        for _ in 0..<2 {
            guard let currentThickness = renderedThickness(
                of: adjusted,
                around: centerlineBounds
            ), currentThickness > 0.01 else { break }

            let scale = min(max(targetThickness / currentThickness, 0.25), 4)
            guard abs(scale - 1) > 0.015 else { break }
            adjusted = adjusted.map {
                strokeByScalingPointSizes($0, by: scale)
            }
        }
        return adjusted
    }

    /// Converts a PKStrokePoint width into PencilKit's actual rendered ink
    /// width. The ratio depends on ink type and is therefore measured instead
    /// of being hard-coded.
    static func renderedInkWidthScale(for stroke: PKStroke) -> CGFloat {
        let points = Array(stroke.path)
        guard !points.isEmpty,
              let centerlineBounds = centerlineBounds(of: stroke),
              let renderedWidth = renderedThickness(
                of: [stroke],
                around: centerlineBounds
              ) else { return 1 }

        let transformScale = max(
            hypot(stroke.transform.a, stroke.transform.c),
            0.0001
        )
        let sampledWidth = points.reduce(CGFloat.zero) { current, point in
            max(
                current,
                (point.size.width + point.size.height) * 0.5 * transformScale
            )
        }
        guard sampledWidth > 0.01 else { return 1 }
        return min(max(renderedWidth / sampledWidth, 0.5), 4)
    }

    private static func centerlineBounds(of stroke: PKStroke) -> CGRect? {
        let points = Array(stroke.path)
        guard let first = points.first else { return nil }
        let firstLocation = first.location.applying(stroke.transform)
        var minX = firstLocation.x
        var minY = firstLocation.y
        var maxX = firstLocation.x
        var maxY = firstLocation.y

        for point in points.dropFirst() {
            let location = point.location.applying(stroke.transform)
            minX = min(minX, location.x)
            minY = min(minY, location.y)
            maxX = max(maxX, location.x)
            maxY = max(maxY, location.y)
        }
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private static func renderedThickness(
        of strokes: [PKStroke],
        around centerlineBounds: CGRect
    ) -> CGFloat? {
        guard let first = strokes.first else { return nil }
        let renderedBounds = strokes.dropFirst().reduce(first.renderBounds) {
            $0.union($1.renderBounds)
        }
        guard !renderedBounds.isNull,
              !renderedBounds.isInfinite else { return nil }

        let horizontalExpansion = max(
            renderedBounds.width - centerlineBounds.width,
            0
        )
        let verticalExpansion = max(
            renderedBounds.height - centerlineBounds.height,
            0
        )
        let expansions = [horizontalExpansion, verticalExpansion].filter {
            $0 > 0.001 && $0.isFinite
        }
        guard !expansions.isEmpty else { return nil }
        return expansions.reduce(0, +) / CGFloat(expansions.count)
    }

    private static func strokeByScalingPointSizes(
        _ stroke: PKStroke,
        by scale: CGFloat
    ) -> PKStroke {
        let controls = stroke.path.map { point in
            PKStrokePoint(
                location: point.location,
                timeOffset: point.timeOffset,
                size: CGSize(
                    width: max(point.size.width * scale, 0.01),
                    height: max(point.size.height * scale, 0.01)
                ),
                opacity: point.opacity,
                force: point.force,
                azimuth: point.azimuth,
                altitude: point.altitude,
                secondaryScale: point.secondaryScale
            )
        }
        return PKStroke(
            ink: stroke.ink,
            path: PKStrokePath(
                controlPoints: controls,
                creationDate: stroke.path.creationDate
            ),
            transform: stroke.transform,
            mask: stroke.mask,
            randomSeed: stroke.randomSeed
        )
    }

    #if os(iOS)
    private static func interpolatedColor(
        from start: UIColor,
        to end: UIColor,
        fraction: CGFloat
    ) -> UIColor {
        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
        var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
        guard start.getRed(&sr, green: &sg, blue: &sb, alpha: &sa),
              end.getRed(&er, green: &eg, blue: &eb, alpha: &ea) else { return start }
        let amount = min(max(fraction, 0), 1)
        return UIColor(
            red: interpolate(sr, er, amount),
            green: interpolate(sg, eg, amount),
            blue: interpolate(sb, eb, amount),
            alpha: interpolate(sa, ea, amount)
        )
    }
    #elseif os(macOS)
    private static func interpolatedColor(
        from start: NSColor,
        to end: NSColor,
        fraction: CGFloat
    ) -> NSColor {
        let startRGB = start.usingColorSpace(.deviceRGB) ?? start
        let endRGB = end.usingColorSpace(.deviceRGB) ?? end
        let amount = min(max(fraction, 0), 1)
        return NSColor(
            red: interpolate(startRGB.redComponent, endRGB.redComponent, amount),
            green: interpolate(startRGB.greenComponent, endRGB.greenComponent, amount),
            blue: interpolate(startRGB.blueComponent, endRGB.blueComponent, amount),
            alpha: interpolate(startRGB.alphaComponent, endRGB.alphaComponent, amount)
        )
    }
    #endif

    static func applyingLineStyle(
        to stroke: PKStroke,
        configuration: DrawingPenConfiguration
    ) -> [PKStroke] {
        let config = configuration.normalized
        guard config.usesPattern else { return [stroke] }

        let source = Array(stroke.path).map { point in
            PKStrokePoint(
                location: point.location,
                timeOffset: point.timeOffset,
                size: CGSize(width: config.patternWidth, height: config.patternWidth),
                opacity: point.opacity,
                force: point.force,
                azimuth: point.azimuth,
                altitude: point.altitude,
                secondaryScale: point.secondaryScale
            )
        }
        guard source.count >= 2 else { return [stroke] }

        let visibleLength = config.visiblePatternLength
        let hiddenLength = config.hiddenPatternLength
        let epsilon: CGFloat = 0.0001
        var isVisible = true
        var remainingInPhase = visibleLength
        var visiblePoints = [source[0]]
        var segments: [[PKStrokePoint]] = []

        for index in 1..<source.count {
            var cursor = source[index - 1]
            let destination = source[index]
            var remainingInSourceSegment = pointDistance(
                cursor.location,
                destination.location
            )

            guard remainingInSourceSegment > epsilon else { continue }

            while remainingInSourceSegment > epsilon {
                let step = min(remainingInSourceSegment, remainingInPhase)
                let fraction = step / remainingInSourceSegment
                let boundary = interpolatedPoint(
                    from: cursor,
                    to: destination,
                    fraction: fraction
                )

                if isVisible {
                    if visiblePoints.isEmpty {
                        visiblePoints.append(cursor)
                    }
                    appendIfDistinct(boundary, to: &visiblePoints)
                }

                cursor = boundary
                remainingInSourceSegment -= step
                remainingInPhase -= step

                if remainingInPhase <= epsilon {
                    if isVisible, visiblePoints.count >= 2 {
                        segments.append(visiblePoints)
                    }
                    isVisible.toggle()
                    remainingInPhase = isVisible ? visibleLength : hiddenLength
                    visiblePoints = isVisible ? [boundary] : []
                }
            }
        }

        if isVisible, visiblePoints.count >= 2 {
            segments.append(visiblePoints)
        }

        guard !segments.isEmpty else {
            // Preserve taps and extremely short marks as a single dot.
            return [strokeWithUniformWidth(stroke, width: config.patternWidth)]
        }

        return segments.enumerated().map { index, points in
            PKStroke(
                ink: stroke.ink,
                path: PKStrokePath(
                    controlPoints: points,
                    creationDate: stroke.path.creationDate
                ),
                transform: stroke.transform,
                mask: stroke.mask,
                randomSeed: stroke.randomSeed &+ UInt32(index)
            )
        }
    }

    private static func strokeWithUniformWidth(
        _ stroke: PKStroke,
        width: Double,
        replacementInk: PKInk? = nil
    ) -> PKStroke {
        let points = stroke.path.map { point in
            PKStrokePoint(
                location: point.location,
                timeOffset: point.timeOffset,
                size: CGSize(width: width, height: width),
                opacity: point.opacity,
                force: point.force,
                azimuth: point.azimuth,
                altitude: point.altitude,
                secondaryScale: point.secondaryScale
            )
        }
        return PKStroke(
            ink: replacementInk ?? stroke.ink,
            path: PKStrokePath(
                controlPoints: points,
                creationDate: stroke.path.creationDate
            ),
            transform: stroke.transform,
            mask: stroke.mask,
            randomSeed: stroke.randomSeed
        )
    }

    private static func interpolatedPoint(
        from start: PKStrokePoint,
        to end: PKStrokePoint,
        fraction: CGFloat
    ) -> PKStrokePoint {
        let amount = min(max(fraction, 0), 1)
        return PKStrokePoint(
            location: CGPoint(
                x: interpolate(start.location.x, end.location.x, amount),
                y: interpolate(start.location.y, end.location.y, amount)
            ),
            timeOffset: interpolate(start.timeOffset, end.timeOffset, Double(amount)),
            size: CGSize(
                width: interpolate(start.size.width, end.size.width, amount),
                height: interpolate(start.size.height, end.size.height, amount)
            ),
            opacity: interpolate(start.opacity, end.opacity, amount),
            force: interpolate(start.force, end.force, amount),
            azimuth: interpolate(start.azimuth, end.azimuth, amount),
            altitude: interpolate(start.altitude, end.altitude, amount),
            secondaryScale: interpolate(start.secondaryScale, end.secondaryScale, amount)
        )
    }

    private static func appendIfDistinct(
        _ point: PKStrokePoint,
        to points: inout [PKStrokePoint]
    ) {
        guard points.last.map({
            pointDistance($0.location, point.location) > 0.0001
        }) ?? true else { return }
        points.append(point)
    }

    private static func pointDistance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }

    private static func interpolate<T: BinaryFloatingPoint>(
        _ start: T,
        _ end: T,
        _ amount: T
    ) -> T {
        start + (end - start) * amount
    }

    static func smoothedLocations(_ points: [CGPoint], amount: CGFloat) -> [CGPoint] {
        guard points.count > 2, amount > 0.001 else { return points }

        let strength = min(max(amount, 0), 1)
        let radius = max(1, Int((1 + strength * 11).rounded()))
        let passCount = 1 + Int((strength * 2).rounded(.down))
        let blend = 0.22 + strength * 0.78
        var output = points

        for _ in 0..<passCount {
            let input = output
            for index in input.indices {
                guard index != input.startIndex,
                      index != input.index(before: input.endIndex)
                else { continue }

                let lower = max(input.startIndex, index - radius)
                let upper = min(input.index(before: input.endIndex), index + radius)
                var sum = CGPoint.zero
                var totalWeight: CGFloat = 0

                for sampleIndex in lower...upper {
                    let distance = abs(sampleIndex - index)
                    let weight = CGFloat(radius + 1 - distance)
                    sum.x += input[sampleIndex].x * weight
                    sum.y += input[sampleIndex].y * weight
                    totalWeight += weight
                }

                guard totalWeight > 0 else { continue }
                let average = CGPoint(x: sum.x / totalWeight, y: sum.y / totalWeight)
                output[index] = CGPoint(
                    x: input[index].x + (average.x - input[index].x) * blend,
                    y: input[index].y + (average.y - input[index].y) * blend
                )
            }
        }

        return output
    }
}

#if os(iOS)
@MainActor
private final class ContinuousColorPreviewLayer: CALayer {
    var strokes: [[CGPoint]] = []
    var strokeWidths: [[CGFloat]] = []
    var palette: [UIColor] = []
    var transitionLength: CGFloat = 105
    var strokeWidth: CGFloat = 4
    var dashPattern: [CGFloat] = []

    override func draw(in context: CGContext) {
        guard palette.count >= 2 else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)

        var distanceOffset: CGFloat = 0
        for (strokeIndex, points) in strokes.enumerated() where points.count >= 2 {
            let widths = strokeWidths.indices.contains(strokeIndex)
                ? strokeWidths[strokeIndex]
                : []
            for index in 1..<points.count {
                let start = points[index - 1]
                let end = points[index]
                let length = hypot(end.x - start.x, end.y - start.y)
                guard length > 0.0001 else { continue }
                let colorProgress = (distanceOffset + length * 0.5) / max(transitionLength, 1)
                let baseIndex = Int(floor(colorProgress)) % palette.count
                let nextIndex = (baseIndex + 1) % palette.count
                let blend = colorProgress - floor(colorProgress)
                let color = Self.interpolatedColor(
                    from: palette[baseIndex],
                    to: palette[nextIndex],
                    fraction: blend
                )

                context.setStrokeColor(color.cgColor)
                if widths.count == points.count {
                    context.setLineWidth(
                        max((widths[index - 1] + widths[index]) * 0.5, 0.5)
                    )
                } else {
                    context.setLineWidth(strokeWidth)
                }
                if dashPattern.isEmpty {
                    context.setLineDash(phase: 0, lengths: [])
                } else {
                    let patternLength = dashPattern.reduce(0, +)
                    let phase = patternLength > 0
                        ? -(distanceOffset.truncatingRemainder(dividingBy: patternLength))
                        : 0
                    context.setLineDash(phase: phase, lengths: dashPattern)
                }
                context.beginPath()
                context.move(to: start)
                context.addLine(to: end)
                context.strokePath()
                distanceOffset += length
            }
        }
    }

    private static func interpolatedColor(
        from start: UIColor,
        to end: UIColor,
        fraction: CGFloat
    ) -> UIColor {
        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
        var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
        guard start.getRed(&sr, green: &sg, blue: &sb, alpha: &sa),
              end.getRed(&er, green: &eg, blue: &eb, alpha: &ea) else { return start }
        let amount = min(max(fraction, 0), 1)
        return UIColor(
            red: sr + (er - sr) * amount,
            green: sg + (eg - sg) * amount,
            blue: sb + (eb - sb) * amount,
            alpha: sa + (ea - sa) * amount
        )
    }
}

@MainActor
final class LivePatternStrokePreview {
    private let previewLayer = CAShapeLayer()
    private let continuousPreviewLayer = ContinuousColorPreviewLayer()
    private var configuration = DrawingPenConfiguration.default
    private var colorConfiguration = DrawingColorCycleConfiguration.default
    private var visibleTool: PKInkingTool?
    private var completedGesturePoints: [[CGPoint]] = []
    private var completedGestureWidths: [[CGFloat]] = []
    private var gesturePoints: [CGPoint] = []
    private var gestureWidths: [CGFloat] = []
    private var isTrackingGesture = false

    private(set) var replacementInk: PKInk?
    private(set) var isActive = false

    var visibleInkAlpha: CGFloat? {
        visibleTool?.color.cgColor.alpha
    }

    func visibleReplacementInk(fallbackColorHex: String?) -> PKInk? {
        if let replacementInk,
           replacementInk.color.cgColor.alpha > 0.01 {
            return replacementInk
        }

        guard let tool = visibleTool else { return replacementInk }
        let fallbackColor: UIColor
        if let fallbackColorHex {
            fallbackColor = UIColor(
                ShapeColorPalette.color(named: fallbackColorHex, fallback: .orange)
            )
        } else {
            fallbackColor = tool.color
        }
        return PKInk(
            tool.inkType,
            color: fallbackColor.withAlphaComponent(
                tool.color.cgColor.alpha > 0.01
                    ? tool.color.cgColor.alpha
                    : 1
            )
        )
    }

    private var requiresLivePreview: Bool {
        configuration.usesPattern || colorConfiguration.isContinuousActive
    }

    func synchronize(
        configuration: DrawingPenConfiguration,
        on canvas: PKCanvasView
    ) {
        self.configuration = configuration.normalized

        refreshActivation(on: canvas)
    }

    func synchronize(
        colorConfiguration: DrawingColorCycleConfiguration,
        on canvas: PKCanvasView
    ) {
        self.colorConfiguration = colorConfiguration.normalized
        refreshActivation(on: canvas)
    }

    private func refreshActivation(on canvas: PKCanvasView) {
        guard requiresLivePreview else {
            restoreVisibleToolIfNeeded(on: canvas)
            reset()
            return
        }

        if isActive,
           let currentTool = canvas.tool as? PKInkingTool,
           currentTool.color.cgColor.alpha <= 0.01,
           visibleTool != nil {
            renderGesturePoints(on: canvas)
            return
        }

        guard let currentTool = canvas.tool as? PKInkingTool else {
            reset()
            return
        }

        activate(using: currentTool, on: canvas)
    }

    func selectedInkingToolDidChange(
        _ tool: PKInkingTool?,
        on canvas: PKCanvasView
    ) {
        guard let tool else {
            reset()
            return
        }

        guard requiresLivePreview else {
            reset()
            return
        }

        activate(using: tool, on: canvas)
    }

    func update(with drawing: PKDrawing, on canvas: PKCanvasView) {
        guard isActive,
              requiresLivePreview,
              let stroke = drawing.strokes.last,
              visibleTool != nil
        else {
            return
        }

        let pathPoints = Array(stroke.path)
        guard !pathPoints.isEmpty else {
            clear()
            return
        }

        let zoom = max(canvas.zoomScale, 0.0001)
        let points = pathPoints.map { point -> CGPoint in
            let drawingPoint = point.location.applying(stroke.transform)
            return CGPoint(
                x: drawingPoint.x * zoom - canvas.contentOffset.x,
                y: drawingPoint.y * zoom - canvas.contentOffset.y
            )
        }
        let transformScale = max(
            hypot(stroke.transform.a, stroke.transform.c),
            0.0001
        )
        let renderedWidthScale = configuration.usesPattern
            ? 1
            : DrawingStrokeProcessor.renderedInkWidthScale(for: stroke)
        let widths = pathPoints.map {
            max(
                ($0.size.width + $0.size.height)
                    * 0.5
                    * transformScale
                    * renderedWidthScale,
                0.5
            )
        }

        if isTrackingGesture, colorConfiguration.isContinuousActive {
            // Use PencilKit's sampled point sizes instead of the tool's nominal
            // width so Apple Pencil pressure looks identical before and after
            // the hidden source stroke is finalized.
            gesturePoints = points
            gestureWidths = widths
            renderGesturePoints(on: canvas)
            return
        }

        guard !isTrackingGesture, completedGesturePoints.isEmpty else { return }
        render(strokes: [points], strokeWidths: [widths], zoom: zoom, on: canvas)
    }

    func beginGestureStroke(at location: CGPoint, on canvas: PKCanvasView) {
        guard isActive, requiresLivePreview, visibleTool != nil else {
            return
        }
        // Both PKCanvasViewDelegate and the gesture recognizer can report the
        // same beginning. Treat the second notification as a no-op.
        guard !isTrackingGesture else { return }
        isTrackingGesture = true
        gesturePoints = [viewportPoint(from: location, on: canvas)]
        gestureWidths = [visibleTool?.width ?? 4]
        renderGesturePoints(on: canvas)
    }

    func continueGestureStroke(at location: CGPoint, on canvas: PKCanvasView) {
        guard isTrackingGesture else { return }
        let point = viewportPoint(from: location, on: canvas)
        if let previous = gesturePoints.last,
           hypot(point.x - previous.x, point.y - previous.y) < 0.25 {
            return
        }
        gesturePoints.append(point)
        gestureWidths.append(gestureWidths.last ?? visibleTool?.width ?? 4)
        renderGesturePoints(on: canvas)
    }

    func endGestureStroke(cancelled: Bool, on canvas: PKCanvasView) {
        guard isTrackingGesture else { return }
        isTrackingGesture = false
        if cancelled {
            gesturePoints.removeAll(keepingCapacity: true)
            gestureWidths.removeAll(keepingCapacity: true)
        } else if !gesturePoints.isEmpty {
            completedGesturePoints.append(gesturePoints)
            completedGestureWidths.append(gestureWidths)
            gesturePoints.removeAll(keepingCapacity: true)
            gestureWidths.removeAll(keepingCapacity: true)
        }
        renderGesturePoints(on: canvas)
    }

    private func renderGesturePoints(on canvas: PKCanvasView) {
        var strokes = completedGesturePoints
        var widths = completedGestureWidths
        if !gesturePoints.isEmpty {
            strokes.append(gesturePoints)
            widths.append(gestureWidths)
        }
        render(
            strokes: strokes,
            strokeWidths: widths,
            zoom: max(canvas.zoomScale, 0.0001),
            on: canvas
        )
    }

    private func render(
        strokes: [[CGPoint]],
        strokeWidths: [[CGFloat]] = [],
        zoom: CGFloat,
        on canvas: PKCanvasView
    ) {
        guard let visibleTool, !strokes.isEmpty else {
            hidePreviewLayers()
            return
        }

        let renderedStrokes = strokes.map {
            DrawingStrokeProcessor.smoothedLocations(
                $0,
                amount: CGFloat(configuration.smoothing)
            )
        }

        if colorConfiguration.isContinuousActive {
            renderContinuous(
                strokes: renderedStrokes,
                strokeWidths: strokeWidths,
                visibleTool: visibleTool,
                zoom: zoom,
                on: canvas
            )
            return
        }

        let path = CGMutablePath()
        for renderedPoints in renderedStrokes {
            guard let first = renderedPoints.first else { continue }
            path.move(to: first)
            if renderedPoints.count == 1 {
                path.addLine(to: CGPoint(x: first.x + 0.01, y: first.y))
            } else {
                for point in renderedPoints.dropFirst() {
                    path.addLine(to: point)
                }
            }
        }

        installLayerIfNeeded(on: canvas)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // PKCanvasView is a UIScrollView. Matching its full bounds (including
        // the content offset) keeps this viewport-space path aligned while the
        // user is zoomed or panned.
        previewLayer.frame = canvas.bounds
        previewLayer.path = path
        previewLayer.strokeColor = visibleTool.color.cgColor
        previewLayer.lineWidth = CGFloat(configuration.patternWidth) * zoom
        previewLayer.lineDashPattern = [
            NSNumber(value: Double(configuration.visiblePatternLength * zoom)),
            NSNumber(value: Double(configuration.hiddenPatternLength * zoom))
        ]
        previewLayer.isHidden = false
        continuousPreviewLayer.isHidden = true
        CATransaction.commit()
    }

    private func renderContinuous(
        strokes: [[CGPoint]],
        strokeWidths: [[CGFloat]],
        visibleTool: PKInkingTool,
        zoom: CGFloat,
        on canvas: PKCanvasView
    ) {
        installLayerIfNeeded(on: canvas)
        let palette = colorConfiguration.colorHexes.map {
            UIColor(ShapeColorPalette.color(named: $0, fallback: .orange))
                .withAlphaComponent(visibleTool.color.cgColor.alpha)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        continuousPreviewLayer.frame = canvas.bounds
        continuousPreviewLayer.strokes = strokes
        continuousPreviewLayer.strokeWidths = configuration.usesPattern
            ? []
            : strokeWidths.map { widths in
                widths.map { $0 * zoom }
            }
        continuousPreviewLayer.palette = palette
        continuousPreviewLayer.transitionLength =
            colorConfiguration.continuousSpeed.transitionLength * zoom
        continuousPreviewLayer.strokeWidth = (
            configuration.usesPattern
                ? CGFloat(configuration.patternWidth)
                : visibleTool.width
        ) * zoom
        continuousPreviewLayer.dashPattern = configuration.usesPattern
            ? [
                configuration.visiblePatternLength * zoom,
                configuration.hiddenPatternLength * zoom
            ]
            : []
        continuousPreviewLayer.isHidden = false
        continuousPreviewLayer.setNeedsDisplay()
        previewLayer.isHidden = true
        CATransaction.commit()
    }

    private func viewportPoint(from location: CGPoint, on canvas: PKCanvasView) -> CGPoint {
        CGPoint(
            x: location.x - canvas.bounds.minX,
            y: location.y - canvas.bounds.minY
        )
    }

    func clear() {
        completedGesturePoints.removeAll(keepingCapacity: true)
        completedGestureWidths.removeAll(keepingCapacity: true)
        gesturePoints.removeAll(keepingCapacity: true)
        gestureWidths.removeAll(keepingCapacity: true)
        isTrackingGesture = false
        hidePreviewLayers()
    }

    private func hidePreviewLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.path = nil
        previewLayer.isHidden = true
        continuousPreviewLayer.strokes = []
        continuousPreviewLayer.strokeWidths = []
        continuousPreviewLayer.isHidden = true
        CATransaction.commit()
    }

    func detach() {
        clear()
        previewLayer.removeFromSuperlayer()
        continuousPreviewLayer.removeFromSuperlayer()
        reset()
    }

    private func activate(using tool: PKInkingTool, on canvas: PKCanvasView) {
        let resolvedTool: PKInkingTool
        if tool.color.cgColor.alpha <= 0.01,
           let previousTool = visibleTool,
           previousTool.color.cgColor.alpha > 0.01 {
            resolvedTool = previousTool
        } else if tool.color.cgColor.alpha <= 0.01 {
            resolvedTool = PKInkingTool(
                tool.inkType,
                color: tool.color.withAlphaComponent(1),
                width: tool.width
            )
        } else {
            resolvedTool = tool
        }

        visibleTool = resolvedTool
        replacementInk = PKInk(resolvedTool.inkType, color: resolvedTool.color)
        isActive = true

        let hiddenColor = resolvedTool.color.withAlphaComponent(0.001)
        canvas.tool = PKInkingTool(
            resolvedTool.inkType,
            color: hiddenColor,
            width: resolvedTool.width
        )
    }

    private func restoreVisibleToolIfNeeded(on canvas: PKCanvasView) {
        guard isActive,
              let visibleTool,
              let currentTool = canvas.tool as? PKInkingTool,
              currentTool.color.cgColor.alpha <= 0.01
        else { return }
        canvas.tool = visibleTool
    }

    private func installLayerIfNeeded(on canvas: PKCanvasView) {
        if previewLayer.superlayer == nil {
            previewLayer.fillColor = UIColor.clear.cgColor
            previewLayer.lineCap = .round
            previewLayer.lineJoin = .round
            previewLayer.contentsScale = UIScreen.main.scale
            previewLayer.zPosition = 10_000
            previewLayer.isHidden = true
            canvas.layer.addSublayer(previewLayer)
        }
        if continuousPreviewLayer.superlayer == nil {
            continuousPreviewLayer.contentsScale = UIScreen.main.scale
            continuousPreviewLayer.zPosition = 10_001
            continuousPreviewLayer.isHidden = true
            canvas.layer.addSublayer(continuousPreviewLayer)
        }
    }

    private func reset() {
        clear()
        visibleTool = nil
        replacementInk = nil
        isActive = false
    }
}
#endif

struct DrawingAssistanceButton: View {
    var compact = true
    var arrowEdge: Edge = .top
    @EnvironmentObject private var settings: AppSettings
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: buttonIcon)
                    .font(.system(size: 13, weight: .semibold))
                if !compact {
                    Text(buttonTitle)
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(hasActiveEffect ? Color.orange : Color.primary)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pen settings")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Adjust line style, automatic colors, spacing, and stroke smoothing.")
        .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
            DrawingAssistancePanel()
                .frame(idealWidth: 360)
                #if os(iOS)
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.height(560), .large])
                #endif
        }
    }

    private var hasActiveEffect: Bool {
        settings.drawingStrokeStyle != .solid
            || settings.effectiveDrawingColorCycleConfiguration.isActive
    }

    private var buttonIcon: String {
        settings.effectiveDrawingColorCycleConfiguration.isActive
            ? "paintpalette.fill"
            : settings.drawingStrokeStyle.icon
    }

    private var buttonTitle: String {
        if settings.effectiveDrawingColorCycleConfiguration.isActive { return "Colors" }
        return settings.drawingStrokeStyle == .solid ? "Pen" : settings.drawingStrokeStyle.title
    }

    private var accessibilityValue: String {
        let colorConfiguration = settings.effectiveDrawingColorCycleConfiguration
        if colorConfiguration.isContinuousActive {
            return "Continuous color flow on, \(colorConfiguration.continuousSpeed.title.lowercased()) speed"
        }
        if colorConfiguration.isActive {
            return "Color cycling on, every \(colorConfiguration.strokesPerColor) strokes"
        }
        return "\(settings.drawingStrokeStyle.title) line"
    }
}

private struct DrawingAssistancePanel: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var draftPatternWidth = DrawingPenConfiguration.default.patternWidth
    @State private var draftDashLength = DrawingPenConfiguration.default.dashLength
    @State private var draftPatternGap = DrawingPenConfiguration.default.patternGap
    @State private var draftSmoothing = DrawingPenConfiguration.default.smoothing

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pen & Stroke")
                            .font(.headline)
                        Text("Shape and color how every line is drawn")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Done") {
                        commitDrafts()
                        dismiss()
                    }
                        .font(.subheadline.weight(.semibold))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Line style", systemImage: "pencil.tip")
                        .font(.subheadline.weight(.semibold))

                    Picker(
                        "Line style",
                        selection: Binding(
                            get: { settings.drawingStrokeStyle },
                            set: { settings.drawingStrokeStyle = $0 }
                        )
                    ) {
                        ForEach(DrawingStrokeStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    DrawingLineStylePreview(configuration: draftConfiguration)

                    Text(lineStyleExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if settings.drawingStrokeStyle != .solid {
                    Divider()

                    configurationSlider(
                        title: "Pattern width",
                        icon: "lineweight",
                        value: $draftPatternWidth,
                        range: DrawingPenConfiguration.patternWidthRange,
                        step: 0.5,
                        displayValue: "\(draftPatternWidth.formatted(.number.precision(.fractionLength(0...1)))) pt",
                        onEditingChanged: commitWhenEditingEnds
                    )

                    if settings.drawingStrokeStyle == .dashed {
                        configurationSlider(
                            title: "Dash length",
                            icon: "arrow.left.and.right",
                            value: $draftDashLength,
                            range: DrawingPenConfiguration.dashLengthRange,
                            step: 1,
                            displayValue: "\(Int(draftDashLength.rounded())) pt",
                            onEditingChanged: commitWhenEditingEnds
                        )
                    }

                    configurationSlider(
                        title: "Gap",
                        icon: "arrow.left.and.right",
                        value: $draftPatternGap,
                        range: DrawingPenConfiguration.patternGapRange,
                        step: 1,
                        displayValue: "\(Int(draftPatternGap.rounded())) pt",
                        onEditingChanged: commitWhenEditingEnds
                    )
                }

                Divider()

                DrawingColorCycleSettingsSection()

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Smoothing", systemImage: "waveform.path")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(smoothingLabel)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $draftSmoothing,
                        in: DrawingPenConfiguration.smoothingRange,
                        step: 0.05,
                        onEditingChanged: commitWhenEditingEnds
                    )
                    .accessibilityLabel("Stroke smoothing")
                    .accessibilityValue(smoothingLabel)

                    Text("Higher values remove more hand jitter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label {
                    Text("Solid lines keep the width from Apple’s drawing toolbar. Patterned lines use the width above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "applepencil.and.scribble")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 300)
        .onAppear(perform: syncDraftsFromSettings)
        .onDisappear(perform: commitDrafts)
    }

    private func configurationSlider(
        title: String,
        icon: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        displayValue: String,
        onEditingChanged: @escaping (Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(displayValue)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: value,
                in: range,
                step: step,
                onEditingChanged: onEditingChanged
            )
                .accessibilityLabel(title)
                .accessibilityValue(displayValue)
        }
    }

    private var lineStyleExplanation: String {
        switch settings.drawingStrokeStyle {
        case .solid:
            return "Draw a continuous line using the selected Apple pen."
        case .dotted:
            return "Draw evenly spaced dots; Gap controls when the next dot appears."
        case .dashed:
            return "Alternate short lines and blank spaces using your chosen Dash length and Gap."
        }
    }

    private var smoothingLabel: String {
        switch draftSmoothing {
        case ..<0.05: return "Off"
        case ..<0.3:  return "Light"
        case ..<0.65: return "Medium"
        default:      return "Strong"
        }
    }

    private var draftConfiguration: DrawingPenConfiguration {
        DrawingPenConfiguration(
            smoothing: draftSmoothing,
            lineStyle: settings.drawingStrokeStyle,
            patternWidth: draftPatternWidth,
            dashLength: draftDashLength,
            patternGap: draftPatternGap
        )
    }

    private func syncDraftsFromSettings() {
        let configuration = settings.drawingPenConfiguration
        draftPatternWidth = configuration.patternWidth
        draftDashLength = configuration.dashLength
        draftPatternGap = configuration.patternGap
        draftSmoothing = configuration.smoothing
    }

    private func commitWhenEditingEnds(_ isEditing: Bool) {
        if !isEditing {
            commitDrafts()
        }
    }

    private func commitDrafts() {
        settings.drawingPenConfiguration = draftConfiguration
    }
}

private struct DrawingColorCycleSettingsSection: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var pro = ProManager.shared
    @State private var showPaywall = false

    private var configuration: DrawingColorCycleConfiguration {
        settings.effectiveDrawingColorCycleConfiguration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: enabledBinding) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cycle stroke colors")
                            .font(.subheadline.weight(.semibold))
                        Text("Move through your palette while you draw")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "paintpalette.fill")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Palette")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(configuration.colorHexes.count)/\(DrawingColorCycleConfiguration.maximumColorCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    ForEach(Array(configuration.colorHexes.enumerated()), id: \.offset) { index, hex in
                        colorControl(index: index, hex: hex)
                    }

                    if configuration.colorHexes.count < DrawingColorCycleConfiguration.maximumColorCount {
                        Button(action: addColor) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 32, height: 32)
                                .background(Color.secondary.opacity(0.10), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add palette color")
                    }
                }
            }

            HStack(spacing: 3) {
                ForEach(DrawingColorCycleMode.allCases) { mode in
                    modeButton(mode)
                }
            }
            .padding(3)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Color behavior")
            .accessibilityHint("Choose whether colors change between strokes or within one stroke")

            if !pro.isPro {
                Label(
                    "Continuous blends colors inside one stroke and is included with Canvio Pro.",
                    systemImage: "lock.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if configuration.mode == .byStroke {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Change after")
                            .font(.subheadline.weight(.semibold))
                        Text(intervalDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Stepper(value: intervalBinding,
                            in: DrawingColorCycleConfiguration.strokeIntervalRange) {
                        Text("\(configuration.strokesPerColor)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .frame(minWidth: 24)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Strokes before changing color")
                    .accessibilityValue("\(configuration.strokesPerColor)")
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Color flow speed")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(configuration.continuousSpeed.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Picker("Color flow speed", selection: speedBinding) {
                        ForEach(DrawingContinuousColorSpeed.allCases) { speed in
                            Text(speed.title).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Colors blend while your finger or Pencil stays on the screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if configuration.colorHexes.count < 2 {
                Label("Add at least two colors to turn cycling on.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if configuration.isEnabled {
                Label(cycleSummary, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet {
                settings.isPro = true
                selectMode(.continuous)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
    }

    private func modeButton(_ mode: DrawingColorCycleMode) -> some View {
        let isSelected = configuration.mode == mode
        let isLocked = mode == .continuous && !pro.isPro

        return Button {
            if isLocked {
                showPaywall = true
            } else {
                selectMode(mode)
            }
        } label: {
            HStack(spacing: 5) {
                Text(mode.title)
                    .font(.caption.weight(.semibold))

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.35) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityValue(isLocked ? "Requires Canvio Pro" : (isSelected ? "Selected" : "Not selected"))
        .accessibilityHint(isLocked ? "Opens the Canvio Pro upgrade screen" : "Selects this color behavior")
    }

    private func colorControl(index: Int, hex: String) -> some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                ColorPicker(
                    "Color \(index + 1)",
                    selection: colorBinding(at: index),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 34, height: 34)

                if configuration.colorHexes.count > 2 {
                    Button {
                        removeColor(at: index)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 15, height: 15)
                            .background(Color.black.opacity(0.68), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .accessibilityLabel("Remove color \(index + 1)")
                }
            }

            Text("\(index + 1)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Palette color \(index + 1), \(ShapeColorPalette.title(for: hex))")
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { configuration.isEnabled },
            set: { isEnabled in
                var updated = configuration
                updated.isEnabled = isEnabled
                settings.drawingColorCycleConfiguration = updated
            }
        )
    }

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { configuration.strokesPerColor },
            set: { interval in
                var updated = configuration
                updated.strokesPerColor = interval
                settings.drawingColorCycleConfiguration = updated
            }
        )
    }

    private func selectMode(_ mode: DrawingColorCycleMode) {
        guard mode != .continuous || pro.isPro else {
            showPaywall = true
            return
        }
        var updated = configuration
        updated.mode = mode
        settings.drawingColorCycleConfiguration = updated
    }

    private var speedBinding: Binding<DrawingContinuousColorSpeed> {
        Binding(
            get: { configuration.continuousSpeed },
            set: { speed in
                var updated = configuration
                updated.continuousSpeed = speed
                settings.drawingColorCycleConfiguration = updated
            }
        )
    }

    private func colorBinding(at index: Int) -> Binding<Color> {
        Binding(
            get: {
                guard configuration.colorHexes.indices.contains(index) else { return .orange }
                return ShapeColorPalette.color(named: configuration.colorHexes[index], fallback: .orange)
            },
            set: { color in
                guard configuration.colorHexes.indices.contains(index) else { return }
                var updated = configuration
                updated.colorHexes[index] = ShapeColorPalette.storageName(
                    for: color,
                    fallback: updated.colorHexes[index]
                )
                settings.drawingColorCycleConfiguration = updated
            }
        )
    }

    private func addColor() {
        var updated = configuration
        guard updated.colorHexes.count < DrawingColorCycleConfiguration.maximumColorCount else { return }
        let suggestions = ["#34C759", "#FF2D55", "#FFCC00", "#5AC8FA", "#5856D6"]
        let next = suggestions.first { !updated.colorHexes.contains($0) } ?? "#FF9500"
        updated.colorHexes.append(next)
        settings.drawingColorCycleConfiguration = updated
    }

    private func removeColor(at index: Int) {
        var updated = configuration
        guard updated.colorHexes.count > 2,
              updated.colorHexes.indices.contains(index) else { return }
        updated.colorHexes.remove(at: index)
        settings.drawingColorCycleConfiguration = updated
    }

    private var intervalDescription: String {
        let count = configuration.strokesPerColor
        return count == 1 ? "Every stroke" : "Every \(count) strokes"
    }

    private var cycleSummary: String {
        switch configuration.mode {
        case .byStroke:
            return "Starts with color 1, then changes after \(intervalDescription.lowercased())."
        case .continuous:
            return "Blends through the full palette inside every uninterrupted stroke."
        }
    }
}

private struct DrawingLineStylePreview: View {
    let configuration: DrawingPenConfiguration

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 14, y: size.height / 2))
            path.addLine(to: CGPoint(x: max(14, size.width - 14), y: size.height / 2))
            context.stroke(
                path,
                with: .color(.primary),
                style: StrokeStyle(
                    lineWidth: previewWidth,
                    lineCap: .round,
                    dash: dashPattern
                )
            )
        }
        .frame(height: 42)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    private var previewWidth: CGFloat {
        configuration.lineStyle == .solid
            ? 4
            : CGFloat(configuration.normalized.patternWidth)
    }

    private var dashPattern: [CGFloat] {
        let config = configuration.normalized
        switch config.lineStyle {
        case .solid:
            return []
        case .dotted:
            return [config.visiblePatternLength, config.hiddenPatternLength]
        case .dashed:
            return [CGFloat(config.dashLength), config.hiddenPatternLength]
        }
    }
}
