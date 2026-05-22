//
//  ImageElementView.swift
//  Ponder
//

import SwiftUI
import SwiftData

struct ImageElementView: View {
    @Environment(\.modelContext) private var context
    @Bindable var element: ImageElementModel
    let canvasScale: CGFloat
    let canvasBoundary: CGSize
    @ObservedObject var vm: ImageElementViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect: Bool = false
    var onExternalTap: (() -> Void)? = nil

    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero
    @State private var rotationAngle: Double = 0
    @State private var hasLoadedRotation = false

    private var isSelected: Bool { vm.editingID == element.id }
    private var currentWidth: CGFloat { max(40, element.width + resizeDelta.width) }
    private var currentHeight: CGFloat { max(40, element.height + resizeDelta.height) }
    private let handleSize: CGFloat = 26

    var body: some View {
        ZStack {
            imageLayer
            selectionRing
            if isSelected && !isMultiSelectMode {
                toolbar.offset(y: -(currentHeight / 2) - 28).rotationEffect(.degrees(-rotationAngle))
                Button { vm.delete(element: element, context: context) } label: { handleCircle(icon: "trash", color: .red) }
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
        .gesture(isMultiSelectMode ? nil : moveDragGesture)
        .onAppear {
            if !hasLoadedRotation { rotationAngle = element.rotation; hasLoadedRotation = true }
        }
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isMultiSelectMode {
            RoundedRectangle(cornerRadius: 8)
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

    private var imageLayer: some View {
        Group {
            if let img = ImageStorageService.load(fileName: element.imageFileName) {
                #if canImport(UIKit)
                Image(uiImage: img).resizable().scaledToFill()
                #else
                Image(nsImage: img).resizable().scaledToFill()
                #endif
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: element.cornerRadius).fill(Color.secondary.opacity(0.12))
                    Image(systemName: "photo").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: currentWidth, height: currentHeight)
        .clipShape(RoundedRectangle(cornerRadius: element.cornerRadius))
        .opacity(element.opacity)
        .overlay(RoundedRectangle(cornerRadius: element.cornerRadius)
            .strokeBorder(isSelected && !isMultiSelectMode ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 2))
        .shadow(color: .black.opacity(isSelected ? 0.18 : 0.08), radius: 6, x: 0, y: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isMultiSelectMode { onExternalTap?(); vm.editingID = isSelected ? nil : element.id }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach([0.0, 4.0, 8.0, 12.0, 16.0, 24.0], id: \.self) { r in
                    Button { element.cornerRadius = r; element.updatedAt = Date(); try? context.save() } label: {
                        HStack { Image(systemName: r == 0 ? "rectangle" : "rectangle.roundedtop"); Text(r == 0 ? "Sharp" : "\(Int(r))pt") }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "rectangle.roundedtop").font(.system(size: 12, weight: .semibold))
                    Text("\(Int(element.cornerRadius))").font(.caption.weight(.semibold))
                }.foregroundStyle(Color.primary.opacity(0.7)).padding(.horizontal, 6).frame(height: 26)
            }
            Divider().frame(height: 18)
            Menu {
                ForEach([1.0, 0.9, 0.75, 0.5, 0.25], id: \.self) { o in
                    Button { element.opacity = o; element.updatedAt = Date(); try? context.save() } label: { Text("\(Int(o * 100))%") }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "circle.lefthalf.filled").font(.system(size: 12, weight: .semibold))
                    Text("\(Int(element.opacity * 100))%").font(.caption.weight(.semibold))
                }.foregroundStyle(Color.primary.opacity(0.7)).padding(.horizontal, 6).frame(height: 26)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2).fixedSize()
    }

    private var rotateGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                let sx = element.x * canvasScale; let sy = element.y * canvasScale
                rotationAngle = atan2(value.location.y - sy, value.location.x - sx) * 180 / .pi + 45
            }
            .onEnded { value in
                let sx = element.x * canvasScale; let sy = element.y * canvasScale
                rotationAngle = atan2(value.location.y - sy, value.location.x - sx) * 180 / .pi + 45
                element.rotation = rotationAngle; element.updatedAt = Date(); try? context.save()
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let aspect = element.width / max(1, element.height)
                let dw = value.translation.width, dh = value.translation.height
                resizeDelta = abs(dw) > abs(dh) ? CGSize(width: dw, height: dw / aspect) : CGSize(width: dh * aspect, height: dh)
            }
            .onEnded { value in
                let aspect = element.width / max(1, element.height)
                let dw = value.translation.width, dh = value.translation.height
                let delta = abs(dw) > abs(dh) ? CGSize(width: dw, height: dw / aspect) : CGSize(width: dh * aspect, height: dh)
                resizeDelta = .zero
                vm.updateSize(element: element, width: element.width + delta.width, height: element.height + delta.height, context: context)
            }
    }

    private var moveDragGesture: some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                let t = value.translation; dragOffset = .zero
                vm.updatePosition(element: element, translation: t, scale: canvasScale, boundary: canvasBoundary, context: context)
            }
    }

    private func handleCircle(icon: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color).frame(width: handleSize, height: handleSize)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        }
    }
}
