//
//  PDFElementView.swift
//  Ponder
//

import SwiftUI
import SwiftData

struct PDFElementView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var canvasHistory: CanvasUndoManager
    @Bindable var element: PDFElementModel
    let canvasScale: CGFloat
    let canvasOffset: CGSize
    let canvasBoundary: CGSize
    @ObservedObject var vm: PDFElementViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect: Bool = false
    let onOpenReader: () -> Void
    var onExternalTap: (() -> Void)? = nil
    var isCanvasGestureActive: Bool = false

    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero
    @State private var rotationAngle: Double = 0
    @State private var rotationGestureState = CanvasElementRotationState()
    @State private var hasLoadedRotation = false

    private var isSelected: Bool { vm.editingID == element.id }
    private var currentWidth: CGFloat { max(120, element.width + resizeDelta.width) }
    private var currentHeight: CGFloat { max(120, element.height + resizeDelta.height) }
    private let handleSize: CGFloat = 26

    var body: some View {
        ZStack {
            cardLayer
            selectionRing
            if isSelected && !isMultiSelectMode {
                toolbarRow.offset(y: -(currentHeight / 2) - 28).rotationEffect(.degrees(-rotationAngle))
                Button {
                    vm.delete(element: element, context: context, undoManager: canvasHistory)
                } label: { handleCircle(icon: "trash", color: .red) }
                    .buttonStyle(.plain).offset(x: -(currentWidth / 2), y: -(currentHeight / 2))
                handleCircle(icon: "arrow.trianglehead.2.clockwise", color: .orange)
                    .offset(x: -(currentWidth / 2), y: currentHeight / 2).gesture(rotateGesture)
                handleCircle(icon: "arrow.up.left.and.arrow.down.right", color: .green)
                    .offset(x: currentWidth / 2, y: currentHeight / 2).gesture(resizeGesture)
            }
        }
        .frame(width: currentWidth, height: currentHeight)
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
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelectedInMultiSelect ? Color.blue : Color.white.opacity(0.3),
                    lineWidth: isSelectedInMultiSelect ? 2.5 : 1
                )
                .frame(width: currentWidth, height: currentHeight)
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

    private var cardLayer: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle().fill(Color.secondary.opacity(0.07))
                if let thumb = PDFStorageService.loadThumbnail(fileName: element.thumbnailFileName) {
                    #if canImport(UIKit)
                    Image(uiImage: thumb).resizable().scaledToFit().padding(8)
                    #else
                    Image(nsImage: thumb).resizable().scaledToFit().padding(8)
                    #endif
                } else {
                    Image(systemName: "doc.richtext").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.red.opacity(0.6))
                }
                if isSelected && !isMultiSelectMode {
                    VStack {
                        HStack {
                            Spacer()
                            Button { onOpenReader() } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                    .padding(7).background(Circle().fill(Color.black.opacity(0.55)))
                            }.buttonStyle(.plain).padding(10)
                        }
                        Spacer()
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "doc.richtext").font(.system(size: 11, weight: .medium)).foregroundStyle(.red)
                Text(element.originalName.isEmpty ? "Document" : element.originalName).font(.caption.weight(.medium)).lineLimit(1)
                Spacer()
                Text("\(element.pageCount)p").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.secondary.opacity(0.12)))
            }.padding(.horizontal, 10).padding(.vertical, 8)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
            isSelected && !isMultiSelectMode ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2),
            lineWidth: isSelected && !isMultiSelectMode ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if !isMultiSelectMode && !isCanvasGestureActive {
                if !isSelected { onExternalTap?(); vm.editingID = element.id }
                else { onOpenReader() }
            }
        }
    }

    private var toolbarRow: some View {
        Button { onOpenReader() } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.richtext").font(.system(size: 12, weight: .semibold)).foregroundStyle(.red)
                Text("Open PDF").font(.caption.weight(.semibold)).foregroundStyle(.primary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
        }.buttonStyle(.plain).fixedSize()
    }

    private var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasViewportCoordinateSpace))
            .onChanged { value in
                rotationAngle = rotationGestureState.update(
                    pointer: value.location,
                    center: rotationCenter,
                    currentRotation: rotationAngle
                )
            }
            .onEnded { _ in
                rotationGestureState.reset()
                let oldRotation = element.rotation
                element.rotation = rotationAngle; element.updatedAt = Date(); try? context.save()
                Task { await PDFSyncService.shared.upsert(element) }
                canvasHistory.recordElementChange(
                    name: "Rotate PDF",
                    element: element,
                    from: oldRotation,
                    to: element.rotation,
                    context: context
                ) { $0.rotation = $1 }
            }
    }

    private var rotationCenter: CGPoint {
        CGPoint(x: element.x * canvasScale + canvasOffset.width,
                y: element.y * canvasScale + canvasOffset.height)
    }

    private var resizeGesture: some Gesture {
        DragGesture()
            .onChanged { resizeDelta = $0.translation }
            .onEnded { value in
                let t = value.translation; resizeDelta = .zero
                vm.updateSize(
                    element: element,
                    width: element.width + t.width,
                    height: element.height + t.height,
                    context: context,
                    undoManager: canvasHistory
                )
            }
    }

    private var moveDragGesture: some Gesture {
        DragGesture()
            .onChanged {
                guard canMove else {
                    dragOffset = .zero
                    return
                }
                dragOffset = $0.translation
            }
            .onEnded { value in
                guard canMove else {
                    dragOffset = .zero
                    return
                }
                let t = value.translation; dragOffset = .zero
                vm.updatePosition(
                    element: element,
                    translation: t,
                    scale: canvasScale,
                    boundary: canvasBoundary,
                    context: context,
                    undoManager: canvasHistory
                )
            }
    }

    private var canMove: Bool {
        isSelected && !isMultiSelectMode && !isCanvasGestureActive
    }

    private func handleCircle(icon: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color).frame(width: handleSize, height: handleSize)
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        }
    }
}
