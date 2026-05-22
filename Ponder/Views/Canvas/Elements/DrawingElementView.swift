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
    @Bindable var element: DrawingElementModel
    let canvasScale: CGFloat
    let canvasBoundary: CGSize
    @ObservedObject var vm: DrawingElementViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect: Bool = false
    var onExternalTap: (() -> Void)? = nil

    @State private var dragOffset: CGSize = .zero
    @State private var resizeStartWidth: Double = 0
    @State private var resizeStartHeight: Double = 0
    @State private var rotationAngle: Double = 0
    @State private var hasLoadedRotation = false

    private var isSelected: Bool { vm.editingID == element.id }
    private var isEditing: Bool { isSelected && vm.isDrawingModeActive }
    private var isPassiveCanvasInk: Bool {
        element.isCanvasDrawing && !isSelected && !isMultiSelectMode
    }
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
                // Toolbar — macOS shows simplified version (no Draw button)
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

            // Done button — iOS only (editing only possible on iOS)
            #if os(iOS)
            if isEditing {
                doneButton.offset(y: -(CGFloat(element.height) / 2) - 30)
            }
            #endif
        }
        .frame(width: CGFloat(element.width), height: CGFloat(element.height))
        .rotationEffect(.degrees(rotationAngle), anchor: .center)
        .position(x: element.x + dragOffset.width, y: element.y + dragOffset.height)
        .gesture(isEditing || isMultiSelectMode || isPassiveCanvasInk ? nil : moveDragGesture)
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
                .shadow(color: element.isCanvasDrawing ? .clear : .black.opacity(isSelected ? 0.15 : 0.07),
                        radius: isSelected ? 10 : 5, x: 0, y: 3)

            DrawingCanvasView(
                drawing: element.pkDrawing,
                isEditing: isEditing,
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

            // Empty state placeholder — only on iOS (macOS is view-only)
            #if os(iOS)
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
            #else
            // macOS: show placeholder only when empty AND not selected
            if !element.isCanvasDrawing && !hasStrokes && !isSelected {
                VStack(spacing: 8) {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("Drawing from iPhone/iPad")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            #endif
        }
        .contentShape(RoundedRectangle(cornerRadius: element.isCanvasDrawing ? 0 : 12))
        .onTapGesture {
            if !isMultiSelectMode && !isSelected {
                onExternalTap?(); vm.editingID = element.id; vm.isDrawingModeActive = false
            }
        }
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
    // macOS: only shows clear-drawing trash (when strokes exist) — no Draw button
    // iOS: shows Draw button + clear trash

    @ViewBuilder
    private var selectionToolbar: some View {
        #if os(iOS)
        HStack(spacing: 4) {
            Button { vm.isDrawingModeActive = true } label: {
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
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2).fixedSize()

        #else
        // macOS — only show clear button if drawing has strokes
        if hasStrokes {
            HStack(spacing: 4) {
                clearDrawingButton
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2).fixedSize()
        }
        #endif
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

    #if os(iOS)
    private var doneButton: some View {
        Button { vm.isDrawingModeActive = false } label: {
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                Text("Done").font(.caption.weight(.bold))
            }
            .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.orange, in: Capsule())
            .shadow(color: .orange.opacity(0.4), radius: 6, x: 0, y: 2)
        }.buttonStyle(.plain).fixedSize()
    }
    #endif

    private var moveDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let t = value.translation
                dragOffset = .zero
                vm.updatePosition(element: element, translation: t,
                                  scale: canvasScale, boundary: canvasBoundary, context: context)
            }
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
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
        }
    }
}
