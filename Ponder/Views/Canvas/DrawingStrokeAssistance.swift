import Foundation
import CoreGraphics
import PencilKit
import SwiftUI

struct DrawingPenConfiguration: Equatable {
    static let smoothingRange: ClosedRange<Double> = 0...1
    static let `default` = DrawingPenConfiguration(smoothing: 0.35)

    var smoothing: Double

    var normalized: DrawingPenConfiguration {
        DrawingPenConfiguration(
            smoothing: Self.smoothingRange.clamped(smoothing)
        )
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
        configuration: DrawingPenConfiguration
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
            configuration: configuration
        )
    }

    static func processingNewStrokes(
        in drawing: PKDrawing,
        startingAt startIndex: Int,
        configuration: DrawingPenConfiguration
    ) -> PKDrawing? {
        let config = configuration.normalized
        guard startIndex >= 0,
              startIndex < drawing.strokes.count,
              config.smoothing > 0.001
        else { return nil }

        var strokes = drawing.strokes
        var changed = false

        for index in startIndex..<strokes.count {
            let original = strokes[index]
            guard original.mask == nil,
                  let processed = processedStroke(original, configuration: config)
            else { continue }
            strokes[index] = processed
            changed = true
        }

        return changed ? PKDrawing(strokes: strokes) : nil
    }

    private static func processedStroke(
        _ stroke: PKStroke,
        configuration: DrawingPenConfiguration
    ) -> PKStroke? {
        let source = Array(stroke.path)
        guard source.count >= 2 else { return nil }

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
        return PKStroke(
            ink: stroke.ink,
            path: path,
            transform: stroke.transform,
            mask: stroke.mask,
            randomSeed: stroke.randomSeed
        )
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

struct DrawingAssistanceButton: View {
    var compact = true
    var arrowEdge: Edge = .top
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 13, weight: .semibold))
                if !compact {
                    Text("Assist")
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stroke Assist")
        .accessibilityHint("Adjust stroke smoothing.")
        .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
            DrawingAssistancePanel()
                .frame(idealWidth: 340)
                #if os(iOS)
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.height(330)])
                #endif
        }
    }
}

private struct DrawingAssistancePanel: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stroke Assist")
                        .font(.headline)
                    Text("Applies when each new stroke finishes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .font(.subheadline.weight(.semibold))
            }

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
                    value: Binding(
                        get: { settings.drawingPenSmoothing },
                        set: { settings.drawingPenSmoothing = $0 }
                    ),
                    in: DrawingPenConfiguration.smoothingRange,
                    step: 0.05
                )
                .accessibilityLabel("Stroke smoothing")
                .accessibilityValue(smoothingLabel)

                Text("Higher values remove more hand jitter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Label {
                Text("For a pressure-free, uniform-width line, select Monoline in Apple’s drawing toolbar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "applepencil.and.scribble")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 300)
    }

    private var smoothingLabel: String {
        switch settings.drawingPenSmoothing {
        case ..<0.05: return "Off"
        case ..<0.3:  return "Light"
        case ..<0.65: return "Medium"
        default:      return "Strong"
        }
    }
}
