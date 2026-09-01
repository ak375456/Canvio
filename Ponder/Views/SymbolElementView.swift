//
//  SymbolElementView.swift
//  Ponder
//

import SwiftUI
import SwiftData

struct SymbolElementView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var canvasHistory: CanvasUndoManager
    let element: SymbolElementModel
    let canvasScale: CGFloat
    let canvasBoundary: CGSize
    @ObservedObject var vm: SymbolElementViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect: Bool = false
    var onExternalTap: (() -> Void)? = nil
    var isCanvasGestureActive: Bool = false
    var smartDragAdjustment = CanvasSmartDragAdjustment()

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool   = false

    private var isSelected: Bool { vm.editingID == element.id }
    private let handleSize: CGFloat = 26
    private var symbolSize: CGFloat { CGFloat(element.fontSize) }

    var body: some View {
        ZStack {
            // Symbol image
            Image(systemName: element.symbolName)
                .font(.system(size: symbolSize))
                .foregroundStyle(vm.colorFromName(element.colorName))
                .frame(width: symbolSize + 24, height: symbolSize + 24)
                .background(
                    isSelected && !isMultiSelectMode
                    ? RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                        )
                    : nil
                )
                .overlay(multiSelectRing)
                .onTapGesture {
                    guard !isMultiSelectMode, !isDragging, !isCanvasGestureActive else { return }
                    if !isSelected {
                        onExternalTap?()
                        vm.editingID = element.id
                    }
                }

            // Delete handle — top left when selected
            if isSelected && !isMultiSelectMode {
                Button {
                    vm.delete(element: element, context: context, undoManager: canvasHistory)
                } label: {
                    ZStack {
                        Circle().fill(Color.red)
                            .frame(width: handleSize, height: handleSize)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .offset(x: -(symbolSize / 2 + 12), y: -(symbolSize / 2 + 12))
            }

            // Style toolbar — floats above element
            if isSelected && !isMultiSelectMode {
                styleToolbar
                    .offset(y: -(symbolSize / 2) - 50 / canvasScale)
                    .scaleEffect(1.0 / canvasScale)
                    .zIndex(500)
                    .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                    .animation(.spring(duration: 0.22), value: isSelected)
            }
        }
        .position(x: element.x + dragOffset.width,
                  y: element.y + dragOffset.height)
        .gesture(canMove ? moveDragGesture : nil)
        .onChange(of: isSelected) { _, selected in
            // nothing needed
        }
    }

    // MARK: - Style toolbar

    private var styleToolbar: some View {
        HStack(spacing: 6) {
            // Size -
            Button {
                vm.setFontSize(
                    element.fontSize - 8,
                    element: element,
                    context: context,
                    undoManager: canvasHistory
                )
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("\(Int(element.fontSize))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 30)

            // Size +
            Button {
                vm.setFontSize(
                    element.fontSize + 8,
                    element: element,
                    context: context,
                    undoManager: canvasHistory
                )
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 20)

            // Color dots
            ForEach(vm.colorOptions.prefix(8), id: \.name) { option in
                Button {
                    vm.setColor(
                        option.name,
                        element: element,
                        context: context,
                        undoManager: canvasHistory
                    )
                } label: {
                    let active = element.colorName == option.name
                    Circle()
                        .fill(option.name == "primary" ? Color.primary : option.color)
                        .frame(width: active ? 20 : 15, height: active ? 20 : 15)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(active ? 0.5 : 0), lineWidth: 1.5)
                        )
                        .animation(.easeInOut(duration: 0.15), value: element.colorName)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
        )
        .fixedSize()
    }

    // MARK: - Multi-select ring

    @ViewBuilder
    private var multiSelectRing: some View {
        if isMultiSelectMode {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelectedInMultiSelect ? Color.blue : Color.white.opacity(0.3),
                    lineWidth: isSelectedInMultiSelect ? 2.5 : 1
                )
                .overlay(alignment: .topTrailing) {
                    if isSelectedInMultiSelect {
                        ZStack {
                            Circle().fill(Color.blue).frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 8, y: -8)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isSelectedInMultiSelect)
        }
    }

    // MARK: - Move gesture

    private var moveDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard canMove else {
                    isDragging = false
                    dragOffset = .zero
                    smartDragAdjustment.cancelled()
                    return
                }
                isDragging = true
                dragOffset = smartDragAdjustment.changed(value.translation)
            }
            .onEnded { _ in
                guard canMove else {
                    dragOffset = .zero
                    isDragging = false
                    smartDragAdjustment.cancelled()
                    return
                }
                let t = smartDragAdjustment.ended(dragOffset)
                dragOffset = .zero
                vm.updatePosition(
                    element: element, translation: t,
                    scale: canvasScale, boundary: canvasBoundary,
                    context: context, undoManager: canvasHistory
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isDragging = false
                }
            }
    }

    private var canMove: Bool {
        isSelected && !isMultiSelectMode && !isCanvasGestureActive
    }
}
