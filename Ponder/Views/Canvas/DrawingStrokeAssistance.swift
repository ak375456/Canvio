import Foundation
import CoreGraphics
import PencilKit
import SwiftUI
#if os(iOS)
import QuartzCore
import UIKit
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
        replacementInk: PKInk? = nil
    ) -> PKDrawing? {
        guard !drawing.strokes.isEmpty else { return nil }

        let startIndex: Int
        if drawing.strokes.count > baseline.strokeCount {
            startIndex = baseline.strokeCount
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
            replacementInk: replacementInk
        )
    }

    static func processingNewStrokes(
        in drawing: PKDrawing,
        startingAt startIndex: Int,
        configuration: DrawingPenConfiguration,
        replacementInk: PKInk? = nil
    ) -> PKDrawing? {
        let config = configuration.normalized
        guard startIndex >= 0,
              startIndex < drawing.strokes.count,
              config.smoothing > 0.001 || config.usesPattern
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
                    replacementInk: replacementInk
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

    private static func processedStrokes(
        _ stroke: PKStroke,
        configuration: DrawingPenConfiguration,
        replacementInk: PKInk?
    ) -> [PKStroke]? {
        let source = Array(stroke.path)
        guard source.count >= 2 else {
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

        return applyingLineStyle(
            to: smoothedStroke,
            configuration: configuration
        )
    }

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
final class LivePatternStrokePreview {
    private let previewLayer = CAShapeLayer()
    private var configuration = DrawingPenConfiguration.default
    private var visibleTool: PKInkingTool?
    private var gesturePoints: [CGPoint] = []
    private var isTrackingGesture = false

    private(set) var replacementInk: PKInk?
    private(set) var isActive = false

    var visibleInkAlpha: CGFloat? {
        visibleTool?.color.cgColor.alpha
    }

    func synchronize(
        configuration: DrawingPenConfiguration,
        on canvas: PKCanvasView
    ) {
        self.configuration = configuration.normalized

        guard self.configuration.usesPattern else {
            restoreVisibleToolIfNeeded(on: canvas)
            reset()
            return
        }

        guard let currentTool = canvas.tool as? PKInkingTool else {
            reset()
            return
        }

        if isActive, currentTool.color.cgColor.alpha <= 0.01 {
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

        guard configuration.usesPattern else {
            reset()
            return
        }

        activate(using: tool, on: canvas)
    }

    func update(with drawing: PKDrawing, on canvas: PKCanvasView) {
        guard !isTrackingGesture,
              isActive,
              configuration.usesPattern,
              let stroke = drawing.strokes.last,
              visibleTool != nil
        else {
            return
        }

        var points = stroke.path.map(\.location)
        guard !points.isEmpty else {
            clear()
            return
        }

        let zoom = max(canvas.zoomScale, 0.0001)
        points = points.map { point -> CGPoint in
            let drawingPoint = point.applying(stroke.transform)
            return CGPoint(
                x: drawingPoint.x * zoom - canvas.contentOffset.x,
                y: drawingPoint.y * zoom - canvas.contentOffset.y
            )
        }
        render(points: points, zoom: zoom, on: canvas)
    }

    func beginGestureStroke(at location: CGPoint, on canvas: PKCanvasView) {
        guard isActive, configuration.usesPattern, visibleTool != nil else {
            return
        }
        clear()
        isTrackingGesture = true
        gesturePoints = [viewportPoint(from: location, on: canvas)]
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
        renderGesturePoints(on: canvas)
    }

    func endGestureStroke(cancelled: Bool) {
        isTrackingGesture = false
        if cancelled {
            clear()
        }
    }

    private func renderGesturePoints(on canvas: PKCanvasView) {
        render(
            points: gesturePoints,
            zoom: max(canvas.zoomScale, 0.0001),
            on: canvas
        )
    }

    private func render(
        points: [CGPoint],
        zoom: CGFloat,
        on canvas: PKCanvasView
    ) {
        guard let visibleTool, !points.isEmpty else {
            clear()
            return
        }

        let renderedPoints = DrawingStrokeProcessor.smoothedLocations(
            points,
            amount: CGFloat(configuration.smoothing)
        )

        let path = CGMutablePath()
        if let first = renderedPoints.first {
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
        CATransaction.commit()
    }

    private func viewportPoint(from location: CGPoint, on canvas: PKCanvasView) -> CGPoint {
        CGPoint(
            x: location.x - canvas.bounds.minX,
            y: location.y - canvas.bounds.minY
        )
    }

    func clear() {
        gesturePoints.removeAll(keepingCapacity: true)
        isTrackingGesture = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.path = nil
        previewLayer.isHidden = true
        CATransaction.commit()
    }

    func detach() {
        clear()
        previewLayer.removeFromSuperlayer()
        reset()
    }

    private func activate(using tool: PKInkingTool, on canvas: PKCanvasView) {
        visibleTool = tool
        replacementInk = PKInk(tool.inkType, color: tool.color)
        isActive = true

        let hiddenColor = tool.color.withAlphaComponent(0.001)
        canvas.tool = PKInkingTool(
            tool.inkType,
            color: hiddenColor,
            width: tool.width
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
        guard previewLayer.superlayer == nil else { return }
        previewLayer.fillColor = UIColor.clear.cgColor
        previewLayer.lineCap = .round
        previewLayer.lineJoin = .round
        previewLayer.contentsScale = UIScreen.main.scale
        previewLayer.zPosition = 10_000
        previewLayer.isHidden = true
        canvas.layer.addSublayer(previewLayer)
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
                Image(systemName: settings.drawingStrokeStyle.icon)
                    .font(.system(size: 13, weight: .semibold))
                if !compact {
                    Text(settings.drawingStrokeStyle == .solid ? "Pen" : settings.drawingStrokeStyle.title)
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(settings.drawingStrokeStyle == .solid ? Color.primary : Color.orange)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pen style: \(settings.drawingStrokeStyle.title)")
        .accessibilityHint("Adjust line style, pattern width, spacing, and stroke smoothing.")
        .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
            DrawingAssistancePanel()
                .frame(idealWidth: 360)
                #if os(iOS)
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.height(560), .large])
                #endif
        }
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
                        Text("Applies when each new stroke finishes")
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
