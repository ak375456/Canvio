//
//  ShapeElementView.swift
//  Ponder
//

import SwiftUI
import SwiftData

struct ShapeElementView: View {
    @Environment(\.modelContext) private var context
    @Bindable var shape: ShapeElementModel
    let canvasScale: CGFloat
    let canvasBoundary: CGSize
    @ObservedObject var vm: ShapeElementViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect: Bool = false
    var onExternalTap: (() -> Void)? = nil

    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero
    @State private var rotationAngle: Double = 0
    @State private var hasLoadedRotation = false

    private var isSelected: Bool { vm.editingID == shape.id }
    private var currentSize: CGSize {
        CGSize(width: max(40, shape.width + resizeDelta.width),
               height: max(2, shape.height + resizeDelta.height))
    }
    private var strokeColor: Color { paletteColor(shape.strokeColorName) }
    private var fillColor: Color { paletteColor(shape.fillColorName) }
    private let handleSize: CGFloat = 26

    var body: some View {
        ZStack {
            shapeLayer
            selectionRing
            if isSelected && !isMultiSelectMode { cornerHandles }
        }
        .rotationEffect(.degrees(rotationAngle), anchor: .center)
        .position(x: shape.x + dragOffset.width, y: shape.y + dragOffset.height)
        .gesture(isMultiSelectMode ? nil : moveDragGesture)
        .onAppear {
            if !hasLoadedRotation { rotationAngle = shape.rotation; hasLoadedRotation = true }
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
                .frame(width: currentSize.width, height: currentSize.height)
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

    private var shapeLayer: some View {
        shapeRenderer
            .frame(width: currentSize.width, height: currentSize.height)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isSelected && !isMultiSelectMode ? Color.accentColor.opacity(0.5) : Color.clear,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
            .background(toolbarOverlay)
            .onTapGesture {
                if !isMultiSelectMode && !isSelected {
                    onExternalTap?()
                    vm.editingID = shape.id
                }
            }
    }

    private var toolbarOverlay: some View {
        Group {
            if isSelected && !isMultiSelectMode {
                toolbar.rotationEffect(.degrees(-rotationAngle))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(y: -36)
            }
        }
    }

    @ViewBuilder
    private var shapeRenderer: some View {
        switch shape.shapeKind {
        case .line:
            LineShapeView(width: currentSize.width, strokeColor: strokeColor,
                          strokeWidth: shape.strokeWidth, hasArrow: shape.hasArrowHead)
        case .rectangle:
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(strokeColor, lineWidth: shape.strokeWidth)
                .background(shape.hasFill ? RoundedRectangle(cornerRadius: 4).fill(fillColor) : nil)
        case .triangle:
            TriangleShape(variant: shape.triangleVariant)
                .stroke(strokeColor, lineWidth: shape.strokeWidth)
                .background(shape.hasFill ? TriangleShape(variant: shape.triangleVariant).fill(fillColor) : nil)
        case .polygon:
            PolygonShape(sides: shape.polygonSides)
                .stroke(strokeColor, lineWidth: shape.strokeWidth)
                .background(shape.hasFill ? PolygonShape(sides: shape.polygonSides).fill(fillColor) : nil)
        case .circle:
            Circle()
                .strokeBorder(strokeColor, lineWidth: shape.strokeWidth)
                .background(shape.hasFill ? Circle().fill(fillColor) : nil)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            colorMenu(label: "S", selected: shape.strokeColorName) { n in
                shape.strokeColorName = n; shape.updatedAt = Date(); try? context.save()
                Task { await ShapeSyncService.shared.upsert(shape) }
            }
            if shape.shapeKind.supportsFill {
                Button {
                    shape.hasFill.toggle(); shape.updatedAt = Date(); try? context.save()
                    Task { await ShapeSyncService.shared.upsert(shape) }
                } label: {
                    Image(systemName: shape.hasFill ? "drop.fill" : "drop")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(shape.hasFill ? Color.accentColor : Color.primary.opacity(0.6))
                        .frame(width: 26, height: 26)
                }.buttonStyle(.plain)
                if shape.hasFill {
                    colorMenu(label: "F", selected: shape.fillColorName) { n in
                        shape.fillColorName = n; shape.updatedAt = Date(); try? context.save()
                        Task { await ShapeSyncService.shared.upsert(shape) }
                    }
                }
            }
            Divider().frame(height: 18)
            Menu {
                ForEach([1.0, 2.0, 3.0, 4.0, 6.0, 9.0], id: \.self) { w in
                    Button {
                        shape.strokeWidth = w; shape.updatedAt = Date(); try? context.save()
                        Task { await ShapeSyncService.shared.upsert(shape) }
                    } label: { Text("\(Int(w))pt") }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "lineweight").font(.system(size: 12, weight: .semibold))
                    Text("\(Int(shape.strokeWidth))").font(.caption.weight(.semibold))
                }.foregroundStyle(Color.primary.opacity(0.7)).frame(width: 36, height: 26)
            }
            if shape.shapeKind == .line {
                Divider().frame(height: 18)
                Button {
                    shape.hasArrowHead.toggle(); shape.updatedAt = Date(); try? context.save()
                    Task { await ShapeSyncService.shared.upsert(shape) }
                } label: {
                    Image(systemName: shape.hasArrowHead ? "arrow.right" : "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(shape.hasArrowHead ? Color.accentColor : Color.primary.opacity(0.6))
                        .frame(width: 26, height: 26)
                }.buttonStyle(.plain)
            }
            if shape.shapeKind == .triangle {
                Divider().frame(height: 18)
                Menu {
                    ForEach(TriangleVariant.allCases) { v in
                        Button {
                            shape.triangleVariant = v; shape.updatedAt = Date(); try? context.save()
                            Task { await ShapeSyncService.shared.upsert(shape) }
                        } label: { Text(v.title) }
                    }
                } label: {
                    Image(systemName: "triangle").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.7)).frame(width: 26, height: 26)
                }
            }
            if shape.shapeKind == .polygon {
                Divider().frame(height: 18)
                Menu {
                    ForEach(3...12, id: \.self) { n in
                        Button {
                            shape.polygonSides = n; shape.updatedAt = Date(); try? context.save()
                            Task { await ShapeSyncService.shared.upsert(shape) }
                        } label: { Text("\(n) sides") }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "hexagon").font(.system(size: 12))
                        Text("\(shape.polygonSides)").font(.caption.weight(.semibold))
                    }.foregroundStyle(Color.primary.opacity(0.7)).frame(width: 32, height: 26)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
    }

    private func colorMenu(label: String, selected: String, onPick: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(["primary","blue","red","green","orange","purple","pink","yellow","teal","gray"], id: \.self) { name in
                Button { onPick(name) } label: {
                    HStack { Circle().fill(paletteColor(name)).frame(width: 12, height: 12); Text(name.capitalized) }
                }
            }
        } label: {
            ZStack {
                Circle().fill(paletteColor(selected)).frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1))
                Text(label).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 1)
            }
        }
    }

    private var cornerHandles: some View {
        let hw = currentSize.width / 2
        let hh = currentSize.height / 2
        return ZStack {
            tapHandle(icon: "trash", color: .red, x: -hw, y: -hh) { vm.delete(shape: shape, context: context) }
            rotateHandle(x: -hw, y: hh)
            resizeHandle(x: hw, y: hh)
        }
    }

    private func tapHandle(icon: String, color: Color, x: CGFloat, y: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) { handleCircle(icon: icon, color: color) }.buttonStyle(.plain).offset(x: x, y: y)
    }

    private func rotateHandle(x: CGFloat, y: CGFloat) -> some View {
        handleCircle(icon: "arrow.trianglehead.2.clockwise", color: .orange)
            .offset(x: x, y: y)
            .gesture(DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    let sx = shape.x * canvasScale; let sy = shape.y * canvasScale
                    rotationAngle = atan2(value.location.y - sy, value.location.x - sx) * 180 / .pi + 45
                }
                .onEnded { value in
                    let sx = shape.x * canvasScale; let sy = shape.y * canvasScale
                    rotationAngle = atan2(value.location.y - sy, value.location.x - sx) * 180 / .pi + 45
                    shape.rotation = rotationAngle; shape.updatedAt = Date(); try? context.save()
                    Task { await ShapeSyncService.shared.upsert(shape) }
                })
    }

    private func resizeHandle(x: CGFloat, y: CGFloat) -> some View {
        handleCircle(icon: "arrow.up.left.and.arrow.down.right", color: .green)
            .offset(x: x, y: y)
            .gesture(DragGesture()
                .onChanged { resizeDelta = $0.translation }
                .onEnded { value in
                    let t = value.translation; resizeDelta = .zero
                    vm.updateSize(shape: shape, width: shape.width + t.width, height: shape.height + t.height, context: context)
                })
    }

    private func handleCircle(icon: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color).frame(width: handleSize, height: handleSize)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        }
    }

    private var moveDragGesture: some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                let t = value.translation; dragOffset = .zero
                vm.updatePosition(shape: shape, translation: t, scale: canvasScale, boundary: canvasBoundary, context: context)
            }
    }

    private func paletteColor(_ name: String) -> Color {
        switch name {
        case "blue": return .blue; case "red": return .red; case "green": return .green
        case "orange": return .orange; case "purple": return .purple; case "pink": return .pink
        case "yellow": return .yellow; case "teal": return .teal; case "gray": return .gray
        default: return .primary
        }
    }
}

private struct LineShapeView: View {
    let width: CGFloat; let strokeColor: Color; let strokeWidth: Double; let hasArrow: Bool
    var body: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: midY))
                    p.addLine(to: CGPoint(x: geo.size.width - (hasArrow ? CGFloat(strokeWidth * 3) : 0), y: midY))
                }.stroke(strokeColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                if hasArrow {
                    Path { p in
                        let h = CGFloat(strokeWidth * 3); let endX = geo.size.width
                        p.move(to: CGPoint(x: endX, y: midY))
                        p.addLine(to: CGPoint(x: endX - h, y: midY - h * 0.7))
                        p.addLine(to: CGPoint(x: endX - h, y: midY + h * 0.7))
                        p.closeSubpath()
                    }.fill(strokeColor)
                }
            }
        }
    }
}

struct TriangleShape: Shape {
    let variant: TriangleVariant
    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch variant {
        case .equilateral:
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .rightAngled:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .isosceles:
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.15, y: rect.maxY))
        }
        p.closeSubpath(); return p
    }
}

struct PolygonShape: Shape {
    let sides: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let step = (2 * Double.pi) / Double(sides)
        for i in 0..<sides {
            let angle = -Double.pi / 2 + step * Double(i)
            let pt = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath(); return p
    }
}
