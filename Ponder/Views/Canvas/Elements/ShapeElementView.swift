//
//  ShapeElementView.swift
//  Ponder
//

import SwiftUI
import SwiftData

private enum ShapeCustomColorTarget: String, Identifiable {
    case stroke
    case fill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stroke: return "Custom Stroke"
        case .fill:   return "Custom Fill"
        }
    }
}

struct ShapeElementView: View {
    @Environment(\.modelContext) private var context
    @Bindable var shape: ShapeElementModel
    let canvasScale: CGFloat
    let canvasBoundary: CGSize
    @ObservedObject var vm: ShapeElementViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect: Bool = false
    var onExternalTap: (() -> Void)? = nil
    var isCanvasGestureActive: Bool = false

    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero
    @State private var rotationAngle: Double = 0
    @State private var hasLoadedRotation = false
    @State private var customColorTarget: ShapeCustomColorTarget?
    @State private var customColorDraft: Color = .primary

    private var isSelected: Bool { vm.editingID == shape.id }
    private var currentSize: CGSize {
        CGSize(width: max(40, shape.width + resizeDelta.width),
               height: max(2, shape.height + resizeDelta.height))
    }
    private var strokeColor: Color { paletteColor(shape.strokeColorName) }
    private var fillColor: Color { paletteColor(shape.fillColorName) }
    private var hasVisibleStroke: Bool { shape.hasVisibleStroke }
    private var canDisableStroke: Bool { shape.shapeKind.supportsFill && shape.hasFill }
    private var canDisableFill: Bool { hasVisibleStroke }
    private let handleSize: CGFloat = 26

    var body: some View {
        ZStack {
            shapeLayer
            selectionRing
            if isSelected && !isMultiSelectMode { cornerHandles }
        }
        .rotationEffect(.degrees(rotationAngle), anchor: .center)
        .position(x: shape.x + dragOffset.width, y: shape.y + dragOffset.height)
        .gesture(canMove ? moveDragGesture : nil)
        .popover(item: $customColorTarget) { target in
            customColorPanel(for: target)
        }
        .onAppear {
            if !hasLoadedRotation { rotationAngle = shape.rotation; hasLoadedRotation = true }
            ensureVisibleStyle()
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
            .contentShape(shapeInteractionRegion)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isSelected && !isMultiSelectMode ? Color.accentColor.opacity(0.5) : Color.clear,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
            .background(toolbarOverlay)
            .onTapGesture {
                if !isMultiSelectMode && !isSelected && !isCanvasGestureActive {
                    onExternalTap?()
                    vm.editingID = shape.id
                }
            }
    }

    private var shapeInteractionRegion: ShapeInteractionRegion {
        ShapeInteractionRegion(
            kind: shape.shapeKind,
            triangleVariant: shape.triangleVariant,
            polygonSides: shape.polygonSides,
            capturesInterior: (shape.shapeKind.supportsFill && shape.hasFill)
                || (isSelected && !isMultiSelectMode),
            hasArrow: shape.hasArrowHead,
            strokeWidth: max(CGFloat(shape.strokeWidth), 28 / max(canvasScale, 0.1))
        )
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
            if hasVisibleStroke {
                LineShapeView(width: currentSize.width, strokeColor: strokeColor,
                              strokeWidth: shape.strokeWidth, hasArrow: shape.hasArrowHead)
            } else {
                Color.clear
            }
        case .rectangle:
            ZStack {
                if shape.hasFill { RoundedRectangle(cornerRadius: 4).fill(fillColor) }
                if hasVisibleStroke {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(strokeColor, lineWidth: shape.strokeWidth)
                }
            }
        case .triangle:
            ZStack {
                if shape.hasFill { TriangleShape(variant: shape.triangleVariant).fill(fillColor) }
                if hasVisibleStroke {
                    TriangleShape(variant: shape.triangleVariant)
                        .stroke(strokeColor, lineWidth: shape.strokeWidth)
                }
            }
        case .polygon:
            ZStack {
                if shape.hasFill { PolygonShape(sides: shape.polygonSides).fill(fillColor) }
                if hasVisibleStroke {
                    PolygonShape(sides: shape.polygonSides)
                        .stroke(strokeColor, lineWidth: shape.strokeWidth)
                }
            }
        case .circle:
            ZStack {
                if shape.hasFill { Circle().fill(fillColor) }
                if hasVisibleStroke {
                    Circle().strokeBorder(strokeColor, lineWidth: shape.strokeWidth)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            strokeStyleMenu
            if shape.shapeKind.supportsFill {
                fillStyleMenu
            }
            Divider().frame(height: 18)
            strokeWidthMenu
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
    }

    private var strokeStyleMenu: some View {
        Menu {
            if shape.shapeKind.supportsFill {
                Button {
                    setStrokeColor("none")
                } label: {
                    Label("No Stroke", systemImage: "slash.circle")
                }
                .disabled(!canDisableStroke)
                Divider()
            }

            Button {
                openCustomColorPanel(for: .stroke)
            } label: {
                Label("More Colors...", systemImage: "paintpalette")
            }
            Divider()

            ForEach(ShapeColorPalette.options) { option in
                colorOptionButton(
                    option: option,
                    selected: shape.strokeColorName == option.name,
                    onPick: { setStrokeColor(option.name) }
                )
            }
        } label: {
            styleControlLabel(
                title: "Stroke",
                icon: "pencil.tip",
                color: strokeColor,
                isActive: hasVisibleStroke
            )
        }
    }

    private var fillStyleMenu: some View {
        Menu {
            Button {
                setFillEnabled(!shape.hasFill)
            } label: {
                Label(shape.hasFill ? "No Fill" : "Enable Fill",
                      systemImage: shape.hasFill ? "slash.circle" : "paintpalette.fill")
            }
            .disabled(shape.hasFill && !canDisableFill)

            Divider()
            Button {
                openCustomColorPanel(for: .fill)
            } label: {
                Label("More Colors...", systemImage: "paintpalette")
            }
            Divider()

            ForEach(ShapeColorPalette.options) { option in
                colorOptionButton(
                    option: option,
                    selected: shape.hasFill && shape.fillColorName == option.name,
                    onPick: { setFillColor(option.name) }
                )
            }
        } label: {
            styleControlLabel(
                title: "Fill",
                icon: "paintpalette.fill",
                color: fillColor,
                isActive: shape.hasFill
            )
        }
    }

    private func customColorPanel(for target: ShapeCustomColorTarget) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(target.title)
                .font(.headline)

            ColorPicker("Color", selection: $customColorDraft, supportsOpacity: false)

            HStack {
                Button("Cancel") {
                    customColorTarget = nil
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Apply") {
                    applyCustomColor(to: target)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private var strokeWidthMenu: some View {
        Menu {
            ForEach([1.0, 2.0, 3.0, 4.0, 6.0, 9.0], id: \.self) { width in
                Button {
                    setStrokeWidth(width)
                } label: {
                    HStack {
                        Text("\(Int(width))pt")
                        if Int(shape.strokeWidth) == Int(width) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "lineweight").font(.system(size: 12, weight: .semibold))
                Text(hasVisibleStroke ? "\(Int(shape.strokeWidth))" : "Off")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(hasVisibleStroke ? Color.primary.opacity(0.75) : Color.primary.opacity(0.4))
            .frame(width: 42, height: 26)
        }
        .disabled(!hasVisibleStroke)
    }

    private func openCustomColorPanel(for target: ShapeCustomColorTarget) {
        switch target {
        case .stroke:
            customColorDraft = hasVisibleStroke ? strokeColor : ShapeColorPalette.color(named: "primary")
        case .fill:
            customColorDraft = fillColor
        }
        customColorTarget = target
    }

    private func applyCustomColor(to target: ShapeCustomColorTarget) {
        let colorName = ShapeColorPalette.storageName(for: customColorDraft)
        switch target {
        case .stroke:
            setStrokeColor(colorName)
        case .fill:
            setFillColor(colorName)
        }
        customColorTarget = nil
    }

    private func colorOptionButton(option: ShapeColorOption,
                                   selected: Bool,
                                   onPick: @escaping () -> Void) -> some View {
        Button(action: onPick) {
            HStack {
                Circle()
                    .fill(option.color)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                Text(option.title)
                if selected {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func styleControlLabel(title: String,
                                   icon: String,
                                   color: Color,
                                   isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.caption.weight(.semibold))
            ZStack {
                Circle()
                    .fill(isActive ? color : Color.clear)
                    .frame(width: 15, height: 15)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1))
                if !isActive {
                    Image(systemName: "slash")
                        .font(.system(size: 8, weight: .bold))
                }
            }
        }
        .foregroundStyle(isActive ? Color.primary.opacity(0.82) : Color.primary.opacity(0.48))
        .frame(height: 26)
    }

    private func setStrokeColor(_ name: String) {
        guard name != "none" || canDisableStroke else { return }
        if shape.shapeKind == .line && name == "none" { return }
        shape.strokeColorName = name
        if name != "none", shape.strokeWidth <= 0 {
            shape.strokeWidth = 2.5
        }
        persistShapeStyle()
    }

    private func setFillEnabled(_ enabled: Bool) {
        guard shape.shapeKind.supportsFill else { return }
        if !enabled && !canDisableFill { return }
        shape.hasFill = enabled
        persistShapeStyle()
    }

    private func setFillColor(_ name: String) {
        guard shape.shapeKind.supportsFill else { return }
        shape.fillColorName = name
        shape.hasFill = true
        persistShapeStyle()
    }

    private func setStrokeWidth(_ width: Double) {
        guard hasVisibleStroke else { return }
        shape.strokeWidth = width
        persistShapeStyle()
    }

    private func ensureVisibleStyle() {
        if shape.hasVisibleStyle { return }
        shape.strokeColorName = "primary"
        shape.strokeWidth = max(shape.strokeWidth, 2.5)
        persistShapeStyle()
    }

    private func persistShapeStyle() {
        shape.updatedAt = Date()
        try? context.save()
        Task { await ShapeSyncService.shared.upsert(shape) }
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
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
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
                vm.updatePosition(shape: shape, translation: t, scale: canvasScale, boundary: canvasBoundary, context: context)
            }
    }

    private var canMove: Bool {
        isSelected && !isMultiSelectMode && !isCanvasGestureActive
    }

    private func paletteColor(_ name: String) -> Color {
        ShapeColorPalette.color(named: name)
    }
}

private struct ShapeInteractionRegion: Shape {
    let kind: ShapeKind
    let triangleVariant: TriangleVariant
    let polygonSides: Int
    let capturesInterior: Bool
    let hasArrow: Bool
    let strokeWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let basePath = basePath(in: rect)
        guard !capturesInterior || kind == .line else { return basePath }

        var hitPath = basePath.strokedPath(
            StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
        )
        if kind == .line, hasArrow {
            hitPath.addPath(arrowPath(in: rect))
        }
        return hitPath
    }

    private func basePath(in rect: CGRect) -> Path {
        switch kind {
        case .line:
            return Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        case .rectangle:
            return RoundedRectangle(cornerRadius: 4).path(in: rect)
        case .triangle:
            return TriangleShape(variant: triangleVariant).path(in: rect)
        case .polygon:
            return PolygonShape(sides: polygonSides).path(in: rect)
        case .circle:
            return Circle().path(in: rect)
        }
    }

    private func arrowPath(in rect: CGRect) -> Path {
        Path { path in
            let arrowLength = max(8, strokeWidth * 0.8)
            path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - arrowLength, y: rect.midY - arrowLength * 0.7))
            path.addLine(to: CGPoint(x: rect.maxX - arrowLength, y: rect.midY + arrowLength * 0.7))
            path.closeSubpath()
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
