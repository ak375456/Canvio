//
//  DrawingElementView.swift
//  Ponder
//

import SwiftUI
import SwiftData
import PencilKit

struct DrawingElementView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @Bindable var element: DrawingElementModel
    let canvasScale: CGFloat
    let canvasBoundary: CGSize
    @ObservedObject var vm: DrawingElementViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect: Bool = false
    var onExternalTap: (() -> Void)? = nil
    var onContinueCanvasDrawing: ((DrawingElementModel) -> Void)? = nil
    var isCanvasGestureActive: Bool = false

    @State private var dragOffset: CGSize = .zero
    @State private var resizeStartWidth: Double = 0
    @State private var resizeStartHeight: Double = 0
    @State private var rotationAngle: Double = 0
    @State private var hasLoadedRotation = false

    private var isSelected: Bool { vm.editingID == element.id }
    private var isEditing: Bool { isSelected && vm.isDrawingModeActive }
    private let handleVisualSize: CGFloat = 28
    private let handleHitSize: CGFloat = 54


    private var cardBackground: Color {
        if element.isCanvasDrawing { return .clear }
        return colorScheme == .dark ? Color(white: 0.12) : Color.white
    }

    private var hasStrokes: Bool { !element.pkDrawing.strokes.isEmpty }

    var body: some View {
        ZStack {
            drawingCard
            selectionRing

            if isSelected && !isEditing && !isMultiSelectMode {
                selectionToolbar
                    .offset(y: -(CGFloat(element.height) / 2) - 30)

                deleteHandle
                    .offset(x: -(CGFloat(element.width) / 2),
                            y: -(CGFloat(element.height) / 2))
                rotateHandle
                    .offset(x: -(CGFloat(element.width) / 2),
                            y:  CGFloat(element.height) / 2)
                resizeHandle
                    .offset(x:  CGFloat(element.width) / 2,
                            y:  CGFloat(element.height) / 2)
            }

            if isEditing {
                doneButton.offset(y: -(CGFloat(element.height) / 2) - 30)
            }
        }
        .frame(width: CGFloat(element.width), height: CGFloat(element.height))
        .rotationEffect(.degrees(rotationAngle), anchor: .center)
        .position(x: element.x + dragOffset.width, y: element.y + dragOffset.height)
        .gesture(canMove ? moveDragGesture : nil)
        .onAppear {
            if !hasLoadedRotation { rotationAngle = element.rotation; hasLoadedRotation = true }
        }
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isMultiSelectMode {
            RoundedRectangle(cornerRadius: element.isCanvasDrawing ? 4 : 12)
                .strokeBorder(
                    isSelectedInMultiSelect ? Color.blue : Color.white.opacity(0.3),
                    lineWidth: isSelectedInMultiSelect ? 2.5 : 1
                )
                .frame(width: CGFloat(element.width), height: CGFloat(element.height))
                .overlay(alignment: .topTrailing) {
                    if isSelectedInMultiSelect {
                        ZStack {
                            Circle().fill(Color.blue).frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        }.offset(x: 8, y: -8)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isSelectedInMultiSelect)
        }
    }

    private var drawingCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: element.isCanvasDrawing ? 0 : 12)
                .fill(cardBackground)

            DrawingCanvasView(
                drawing: element.pkDrawing,
                isEditing: isEditing,
                canvasScale: canvasScale,
                smartShapeSnappingEnabled: settings.smartShapeSnappingEnabled,
                onDrawingChanged: { vm.saveDrawing(element: element, drawing: $0, context: context) }
            )
            .clipShape(RoundedRectangle(cornerRadius: element.isCanvasDrawing ? 0 : 12))

            if !element.isCanvasDrawing {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isEditing ? Color.orange.opacity(0.8)
                            : isSelected && !isMultiSelectMode ? Color.accentColor.opacity(0.6)
                            : Color.secondary.opacity(0.2),
                        lineWidth: isEditing ? 2.5 : isSelected ? 2 : 1
                    )
            } else if isSelected && !isMultiSelectMode {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(Color.orange.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }

            if !element.isCanvasDrawing && !hasStrokes && !isEditing {
                VStack(spacing: 8) {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text(isSelected ? "Tap 'Draw' to start" : "Tap to select")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(drawingInteractionRegion)
        .onTapGesture {
            if !isMultiSelectMode && !isSelected && !isCanvasGestureActive {
                onExternalTap?(); vm.editingID = element.id; vm.isDrawingModeActive = false
            }
        }
    }

    private var drawingInteractionRegion: DrawingInteractionRegion {
        DrawingInteractionRegion(
            drawing: element.pkDrawing,
            capturesBounds: isSelected || !element.isCanvasDrawing,
            cornerRadius: element.isCanvasDrawing ? 0 : 12,
            minimumStrokeWidth: 28 / max(canvasScale, 0.1)
        )
    }

    private var deleteHandle: some View {
        Button { vm.delete(element: element, context: context) } label: {
            ZStack {
                Color.clear.frame(width: handleHitSize, height: handleHitSize).contentShape(Rectangle())
                handleCircle(icon: "trash", color: .red)
            }
        }.buttonStyle(.plain)
    }

    private var rotateHandle: some View {
        ZStack {
            Color.clear.frame(width: handleHitSize, height: handleHitSize).contentShape(Rectangle())
            handleCircle(icon: "arrow.trianglehead.2.clockwise", color: .orange)
        }.gesture(rotateGesture)
    }

    private var resizeHandle: some View {
        ZStack {
            Color.clear.frame(width: handleHitSize, height: handleHitSize).contentShape(Rectangle())
            handleCircle(icon: "arrow.up.left.and.arrow.down.right", color: .green)
        }.gesture(resizeGesture)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var selectionToolbar: some View {
        HStack(spacing: 4) {
            Button {
                if element.isCanvasDrawing {
                    onContinueCanvasDrawing?(element)
                } else {
                    vm.isDrawingModeActive = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "pencil.tip").font(.system(size: 13, weight: .semibold))
                    Text("Draw").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.orange, in: Capsule())
            }.buttonStyle(.plain)

            if hasStrokes {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, 2)
                clearDrawingButton
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }

    private var clearDrawingButton: some View {
        Button {
            vm.saveDrawing(element: element, drawing: PKDrawing(), context: context)
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red.opacity(0.8))
                .frame(width: 30, height: 28)
        }.buttonStyle(.plain)
    }

    private var doneButton: some View {
        Button { vm.isDrawingModeActive = false } label: {
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                Text("Done").font(.caption.weight(.bold))
            }
            .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.orange, in: Capsule())
        }.buttonStyle(.plain).fixedSize()
    }

    private var moveDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard canMove else {
                    dragOffset = .zero
                    return
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard canMove else {
                    dragOffset = .zero
                    return
                }
                let t = value.translation
                dragOffset = .zero
                vm.updatePosition(element: element, translation: t,
                                  scale: canvasScale, boundary: canvasBoundary, context: context)
            }
    }

    private var canMove: Bool {
        isSelected && !isEditing && !isMultiSelectMode && !isCanvasGestureActive
    }

    private var rotateGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                let sx = element.x * canvasScale
                let sy = element.y * canvasScale
                rotationAngle = atan2(value.location.y - sy, value.location.x - sx) * 180 / .pi + 45
            }
            .onEnded { value in
                let sx = element.x * canvasScale
                let sy = element.y * canvasScale
                rotationAngle = atan2(value.location.y - sy, value.location.x - sx) * 180 / .pi + 45
                element.rotation = rotationAngle; element.updatedAt = Date(); try? context.save()
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if resizeStartWidth == 0 {
                    resizeStartWidth  = element.width
                    resizeStartHeight = element.height
                }
                element.width  = max(100, min(1200, resizeStartWidth  + Double(value.translation.width)))
                element.height = max(80,  min(1200, resizeStartHeight + Double(value.translation.height)))
            }
            .onEnded { _ in
                element.updatedAt = Date(); try? context.save()
                resizeStartWidth = 0; resizeStartHeight = 0
            }
    }

    private func handleCircle(icon: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color).frame(width: handleVisualSize, height: handleVisualSize)
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
        }
    }
}

private struct DrawingInteractionRegion: Shape {
    let drawing: PKDrawing
    let capturesBounds: Bool
    let cornerRadius: CGFloat
    let minimumStrokeWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        if capturesBounds {
            return RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)
        }

        var interactionPath = Path()
        for stroke in drawing.strokes {
            let transformScale = max(
                hypot(stroke.transform.a, stroke.transform.b),
                hypot(stroke.transform.c, stroke.transform.d)
            )

            for range in stroke.maskedPathRanges {
                let samples = Array(
                    stroke.path.interpolatedPoints(in: range, by: .distance(4))
                )
                guard let first = samples.first else { continue }

                let renderedWidth = samples.reduce(CGFloat(0)) { current, point in
                    max(current, max(point.size.width, point.size.height))
                } * max(transformScale, 0.01)
                let hitWidth = max(minimumStrokeWidth, renderedWidth)
                let firstLocation = first.location.applying(stroke.transform)

                if samples.count == 1 {
                    interactionPath.addEllipse(in: CGRect(
                        x: firstLocation.x - hitWidth / 2,
                        y: firstLocation.y - hitWidth / 2,
                        width: hitWidth,
                        height: hitWidth
                    ))
                    continue
                }

                var centerline = Path()
                centerline.move(to: firstLocation)
                for sample in samples.dropFirst() {
                    centerline.addLine(to: sample.location.applying(stroke.transform))
                }
                interactionPath.addPath(
                    centerline.strokedPath(
                        StrokeStyle(lineWidth: hitWidth, lineCap: .round, lineJoin: .round)
                    )
                )
            }
        }
        return interactionPath
    }
}
