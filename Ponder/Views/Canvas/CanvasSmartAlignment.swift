//
//  CanvasSmartAlignment.swift
//  Canvio
//

import SwiftUI
import Combine

enum CanvasSmartAlignmentSessionID: Equatable {
    case element(UUID)
    case group(UUID)
    case selection
}

/// A small bridge used by every element's existing drag gesture. The callbacks
/// return the translation that should be rendered and eventually committed.
struct CanvasSmartDragAdjustment {
    private let onChanged: @MainActor (CGSize) -> CGSize
    private let onEnded: @MainActor (CGSize) -> CGSize
    private let onCancelled: @MainActor () -> Void

    init(
        onChanged: @escaping @MainActor (CGSize) -> CGSize = { $0 },
        onEnded: @escaping @MainActor (CGSize) -> CGSize = { $0 },
        onCancelled: @escaping @MainActor () -> Void = {}
    ) {
        self.onChanged = onChanged
        self.onEnded = onEnded
        self.onCancelled = onCancelled
    }

    @MainActor
    func changed(_ proposed: CGSize) -> CGSize {
        onChanged(proposed)
    }

    @MainActor
    func ended(_ rendered: CGSize) -> CGSize {
        onEnded(rendered)
    }

    @MainActor
    func cancelled() {
        onCancelled()
    }
}

struct CanvasSmartAlignmentGuide: Equatable {
    enum Axis: Equatable {
        case vertical
        case horizontal
    }

    let axis: Axis
    let position: CGFloat
    let start: CGFloat
    let end: CGFloat
}

/// Performs all high-frequency snapping math outside the root canvas view.
/// Candidate anchors are built once per drag and binary-searched thereafter.
@MainActor
final class CanvasSmartAlignmentState: ObservableObject {
    @Published private(set) var guides: [CanvasSmartAlignmentGuide] = []
    @Published private(set) var feedbackTrigger = 0

    private enum AnchorRole: Int {
        case minimum
        case center
        case maximum
    }

    private struct TargetAnchor {
        let position: CGFloat
        let role: AnchorRole
        let rect: CGRect
    }

    private struct SnapLatch: Equatable {
        let sourceOffset: CGFloat
        let sourceRole: AnchorRole
        let targetPosition: CGFloat
        let targetRole: AnchorRole
        let targetRect: CGRect
    }

    private var sessionID: CanvasSmartAlignmentSessionID?
    private var movingBounds: CGRect = .zero
    private var horizontalAnchors: [TargetAnchor] = []
    private var verticalAnchors: [TargetAnchor] = []
    private var horizontalLatch: SnapLatch?
    private var verticalLatch: SnapLatch?

    func isActive(for sessionID: CanvasSmartAlignmentSessionID) -> Bool {
        self.sessionID == sessionID
    }

    func begin(
        sessionID: CanvasSmartAlignmentSessionID,
        movingBounds: CGRect,
        targetBounds: [CGRect]
    ) {
        self.sessionID = sessionID
        self.movingBounds = movingBounds.standardized
        horizontalLatch = nil
        verticalLatch = nil
        setGuides([])

        let validTargets = targetBounds.lazy
            .map(\.standardized)
            .filter(Self.isValid(rect:))

        horizontalAnchors = validTargets.flatMap { rect in
            [
                TargetAnchor(position: rect.minX, role: .minimum, rect: rect),
                TargetAnchor(position: rect.midX, role: .center, rect: rect),
                TargetAnchor(position: rect.maxX, role: .maximum, rect: rect)
            ]
        }
        .sorted { $0.position < $1.position }

        verticalAnchors = validTargets.flatMap { rect in
            [
                TargetAnchor(position: rect.minY, role: .minimum, rect: rect),
                TargetAnchor(position: rect.midY, role: .center, rect: rect),
                TargetAnchor(position: rect.maxY, role: .maximum, rect: rect)
            ]
        }
        .sorted { $0.position < $1.position }
    }

    func update(proposed: CGSize, canvasScale: CGFloat) -> CGSize {
        guard sessionID != nil else { return proposed }

        let safeScale = max(canvasScale, 0.01)
        let snapTolerance = 8 / safeScale
        let releaseTolerance = 13 / safeScale
        let previousHorizontalLatch = horizontalLatch
        let previousVerticalLatch = verticalLatch

        let horizontalDelta = resolvedDelta(
            axis: .vertical,
            proposed: proposed,
            anchors: horizontalAnchors,
            snapTolerance: snapTolerance,
            releaseTolerance: releaseTolerance,
            latch: &horizontalLatch
        )
        let verticalDelta = resolvedDelta(
            axis: .horizontal,
            proposed: proposed,
            anchors: verticalAnchors,
            snapTolerance: snapTolerance,
            releaseTolerance: releaseTolerance,
            latch: &verticalLatch
        )

        let adjusted = CGSize(
            width: proposed.width + horizontalDelta,
            height: proposed.height + verticalDelta
        )
        let renderedBounds = movingBounds.offsetBy(
            dx: adjusted.width,
            dy: adjusted.height
        )

        var nextGuides: [CanvasSmartAlignmentGuide] = []
        if let horizontalLatch {
            nextGuides.append(CanvasSmartAlignmentGuide(
                axis: .vertical,
                position: horizontalLatch.targetPosition,
                start: min(renderedBounds.minY, horizontalLatch.targetRect.minY),
                end: max(renderedBounds.maxY, horizontalLatch.targetRect.maxY)
            ))
        }
        if let verticalLatch {
            nextGuides.append(CanvasSmartAlignmentGuide(
                axis: .horizontal,
                position: verticalLatch.targetPosition,
                start: min(renderedBounds.minX, verticalLatch.targetRect.minX),
                end: max(renderedBounds.maxX, verticalLatch.targetRect.maxX)
            ))
        }
        setGuides(nextGuides)

        let enteredHorizontalSnap = horizontalLatch != nil
            && horizontalLatch != previousHorizontalLatch
        let enteredVerticalSnap = verticalLatch != nil
            && verticalLatch != previousVerticalLatch
        if enteredHorizontalSnap || enteredVerticalSnap {
            feedbackTrigger &+= 1
        }

        return adjusted
    }

    func finish() {
        reset()
    }

    func cancel() {
        reset()
    }

    private func reset() {
        sessionID = nil
        movingBounds = .zero
        horizontalAnchors.removeAll(keepingCapacity: true)
        verticalAnchors.removeAll(keepingCapacity: true)
        horizontalLatch = nil
        verticalLatch = nil
        setGuides([])
    }

    private func setGuides(_ newGuides: [CanvasSmartAlignmentGuide]) {
        if guides != newGuides {
            guides = newGuides
        }
    }

    private func resolvedDelta(
        axis: CanvasSmartAlignmentGuide.Axis,
        proposed: CGSize,
        anchors: [TargetAnchor],
        snapTolerance: CGFloat,
        releaseTolerance: CGFloat,
        latch: inout SnapLatch?
    ) -> CGFloat {
        let proposedComponent = component(of: proposed, for: axis)

        if let current = latch {
            let sourcePosition = sourceOrigin(for: axis)
                + current.sourceOffset
                + proposedComponent
            let correction = current.targetPosition - sourcePosition
            if abs(correction) <= releaseTolerance {
                return correction
            }
            latch = nil
        }

        guard let match = bestLatch(
            axis: axis,
            proposed: proposed,
            anchors: anchors,
            tolerance: snapTolerance
        ) else {
            return 0
        }

        latch = match
        let sourcePosition = sourceOrigin(for: axis)
            + match.sourceOffset
            + proposedComponent
        return match.targetPosition - sourcePosition
    }

    private func bestLatch(
        axis: CanvasSmartAlignmentGuide.Axis,
        proposed: CGSize,
        anchors: [TargetAnchor],
        tolerance: CGFloat
    ) -> SnapLatch? {
        guard !anchors.isEmpty else { return nil }

        let sourceAnchors = sourceAnchors(for: axis)
        let proposedComponent = component(of: proposed, for: axis)
        let proposedRect = movingBounds.offsetBy(dx: proposed.width, dy: proposed.height)
        var best: SnapLatch?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        var bestRolePenalty = Int.max
        var bestPerpendicularGap = CGFloat.greatestFiniteMagnitude

        for source in sourceAnchors {
            let sourcePosition = sourceOrigin(for: axis)
                + source.offset
                + proposedComponent
            let insertionIndex = lowerBound(for: sourcePosition, in: anchors)

            var index = insertionIndex - 1
            while index >= 0 {
                let target = anchors[index]
                let distance = abs(target.position - sourcePosition)
                guard distance <= tolerance else { break }
                consider(
                    source: source,
                    target: target,
                    distance: distance,
                    proposedRect: proposedRect,
                    axis: axis,
                    best: &best,
                    bestDistance: &bestDistance,
                    bestRolePenalty: &bestRolePenalty,
                    bestPerpendicularGap: &bestPerpendicularGap
                )
                index -= 1
            }

            index = insertionIndex
            while index < anchors.count {
                let target = anchors[index]
                let distance = abs(target.position - sourcePosition)
                guard distance <= tolerance else { break }
                consider(
                    source: source,
                    target: target,
                    distance: distance,
                    proposedRect: proposedRect,
                    axis: axis,
                    best: &best,
                    bestDistance: &bestDistance,
                    bestRolePenalty: &bestRolePenalty,
                    bestPerpendicularGap: &bestPerpendicularGap
                )
                index += 1
            }
        }

        return best
    }

    private func consider(
        source: (offset: CGFloat, role: AnchorRole),
        target: TargetAnchor,
        distance: CGFloat,
        proposedRect: CGRect,
        axis: CanvasSmartAlignmentGuide.Axis,
        best: inout SnapLatch?,
        bestDistance: inout CGFloat,
        bestRolePenalty: inout Int,
        bestPerpendicularGap: inout CGFloat
    ) {
        let rolePenalty = Self.rolePenalty(source.role, target.role)
        let perpendicularGap = Self.perpendicularGap(
            between: proposedRect,
            and: target.rect,
            axis: axis
        )
        let epsilon: CGFloat = 0.0001
        let isBetterDistance = distance < bestDistance - epsilon
        let isEqualDistance = abs(distance - bestDistance) <= epsilon
        let isBetterRole = isEqualDistance && rolePenalty < bestRolePenalty
        let isBetterGap = isEqualDistance
            && rolePenalty == bestRolePenalty
            && perpendicularGap < bestPerpendicularGap

        guard isBetterDistance || isBetterRole || isBetterGap else { return }

        bestDistance = distance
        bestRolePenalty = rolePenalty
        bestPerpendicularGap = perpendicularGap
        best = SnapLatch(
            sourceOffset: source.offset,
            sourceRole: source.role,
            targetPosition: target.position,
            targetRole: target.role,
            targetRect: target.rect
        )
    }

    private func sourceAnchors(
        for axis: CanvasSmartAlignmentGuide.Axis
    ) -> [(offset: CGFloat, role: AnchorRole)] {
        let length = axis == .vertical ? movingBounds.width : movingBounds.height
        return [
            (0, .minimum),
            (length / 2, .center),
            (length, .maximum)
        ]
    }

    private func sourceOrigin(for axis: CanvasSmartAlignmentGuide.Axis) -> CGFloat {
        axis == .vertical ? movingBounds.minX : movingBounds.minY
    }

    private func component(
        of proposed: CGSize,
        for axis: CanvasSmartAlignmentGuide.Axis
    ) -> CGFloat {
        axis == .vertical ? proposed.width : proposed.height
    }

    private func lowerBound(
        for position: CGFloat,
        in anchors: [TargetAnchor]
    ) -> Int {
        var lower = 0
        var upper = anchors.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if anchors[middle].position < position {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func rolePenalty(_ lhs: AnchorRole, _ rhs: AnchorRole) -> Int {
        if lhs == rhs { return 0 }
        if lhs == .center || rhs == .center { return 2 }
        return 1
    }

    private static func perpendicularGap(
        between lhs: CGRect,
        and rhs: CGRect,
        axis: CanvasSmartAlignmentGuide.Axis
    ) -> CGFloat {
        let lhsMin = axis == .vertical ? lhs.minY : lhs.minX
        let lhsMax = axis == .vertical ? lhs.maxY : lhs.maxX
        let rhsMin = axis == .vertical ? rhs.minY : rhs.minX
        let rhsMax = axis == .vertical ? rhs.maxY : rhs.maxX

        if lhsMax < rhsMin { return rhsMin - lhsMax }
        if rhsMax < lhsMin { return lhsMin - rhsMax }
        return 0
    }

    private static func isValid(rect: CGRect) -> Bool {
        !rect.isNull
            && !rect.isInfinite
            && rect.minX.isFinite
            && rect.minY.isFinite
            && rect.maxX.isFinite
            && rect.maxY.isFinite
    }
}

struct CanvasSmartAlignmentGuideOverlay: View {
    @ObservedObject var alignment: CanvasSmartAlignmentState
    let canvasOffset: CGSize
    let canvasScale: CGFloat

    var body: some View {
        SwiftUI.Canvas { context, _ in
            let color = Color(red: 1.0, green: 0.16, blue: 0.52)
            for guide in alignment.guides {
                var path = Path()
                switch guide.axis {
                case .vertical:
                    let x = guide.position * canvasScale + canvasOffset.width
                    let startY = guide.start * canvasScale + canvasOffset.height
                    let endY = guide.end * canvasScale + canvasOffset.height
                    path.move(to: CGPoint(x: x, y: startY))
                    path.addLine(to: CGPoint(x: x, y: endY))
                case .horizontal:
                    let y = guide.position * canvasScale + canvasOffset.height
                    let startX = guide.start * canvasScale + canvasOffset.width
                    let endX = guide.end * canvasScale + canvasOffset.width
                    path.move(to: CGPoint(x: startX, y: y))
                    path.addLine(to: CGPoint(x: endX, y: y))
                }
                context.stroke(path, with: .color(color), lineWidth: 1.25)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        #if os(iOS)
        .sensoryFeedback(.alignment, trigger: alignment.feedbackTrigger)
        #endif
    }
}
