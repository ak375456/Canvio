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

private struct ShapeStyleHistoryState: Equatable {
    let strokeColorName: String
    let fillColorName: String
    let hasFill: Bool
    let strokeWidth: Double

    init(_ shape: ShapeElementModel) {
        strokeColorName = shape.strokeColorName
        fillColorName = shape.fillColorName
        hasFill = shape.hasFill
        strokeWidth = shape.strokeWidth
    }

    func apply(to shape: ShapeElementModel) {
        shape.strokeColorName = strokeColorName
        shape.fillColorName = fillColorName
        shape.hasFill = hasFill
        shape.strokeWidth = strokeWidth
    }
}

private struct ShapeLineAppearanceHistoryState: Equatable {
    let encodedAppearance: String
    let legacyArrowHead: Bool

    init(_ shape: ShapeElementModel) {
        encodedAppearance = shape.triangleVariantRaw
        legacyArrowHead = shape.hasArrowHead
    }

    func apply(to shape: ShapeElementModel) {
        shape.triangleVariantRaw = encodedAppearance
        shape.hasArrowHead = legacyArrowHead
    }
}

struct ShapeElementView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var canvasHistory: CanvasUndoManager
    @Bindable var shape: ShapeElementModel
    let canvasScale: CGFloat
    let canvasOffset: CGSize
    let canvasBoundary: CGSize
    @ObservedObject var vm: ShapeElementViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect: Bool = false
    var onExternalTap: (() -> Void)? = nil
    var isCanvasGestureActive: Bool = false

    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero
    @State private var rotationAngle: Double = 0
    @State private var rotationGestureState = CanvasElementRotationState()
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
            lineEnding: shape.lineEnding,
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
                              strokeWidth: shape.strokeWidth, ending: shape.lineEnding,
                              lineStyle: shape.lineStyle)
            } else {
                Color.clear
            }
        case .rectangle:
            StyledCanvasShape(shape: RoundedRectangle(cornerRadius: 4), fillColor: fillColor,
                              strokeColor: strokeColor, hasFill: shape.hasFill,
                              hasStroke: hasVisibleStroke, strokeWidth: shape.strokeWidth)
        case .roundedRectangle:
            StyledCanvasShape(shape: RoundedRectangle(cornerRadius: 22), fillColor: fillColor,
                              strokeColor: strokeColor, hasFill: shape.hasFill,
                              hasStroke: hasVisibleStroke, strokeWidth: shape.strokeWidth)
        case .triangle:
            StyledCanvasShape(shape: TriangleShape(variant: shape.triangleVariant), fillColor: fillColor,
                              strokeColor: strokeColor, hasFill: shape.hasFill,
                              hasStroke: hasVisibleStroke, strokeWidth: shape.strokeWidth)
        case .polygon:
            StyledCanvasShape(shape: PolygonShape(sides: shape.polygonSides), fillColor: fillColor,
                              strokeColor: strokeColor, hasFill: shape.hasFill,
                              hasStroke: hasVisibleStroke, strokeWidth: shape.strokeWidth)
        case .circle:
            StyledCanvasShape(shape: Circle(), fillColor: fillColor, strokeColor: strokeColor,
                              hasFill: shape.hasFill, hasStroke: hasVisibleStroke,
                              strokeWidth: shape.strokeWidth)
        case .ellipse:
            StyledCanvasShape(shape: Ellipse(), fillColor: fillColor, strokeColor: strokeColor,
                              hasFill: shape.hasFill, hasStroke: hasVisibleStroke,
                              strokeWidth: shape.strokeWidth)
        case .diamond:
            StyledCanvasShape(shape: DiamondShape(), fillColor: fillColor, strokeColor: strokeColor,
                              hasFill: shape.hasFill, hasStroke: hasVisibleStroke,
                              strokeWidth: shape.strokeWidth)
        case .star:
            StyledCanvasShape(shape: StarShape(), fillColor: fillColor, strokeColor: strokeColor,
                              hasFill: shape.hasFill, hasStroke: hasVisibleStroke,
                              strokeWidth: shape.strokeWidth)
        case .speechBubble:
            StyledCanvasShape(shape: SpeechBubbleShape(), fillColor: fillColor, strokeColor: strokeColor,
                              hasFill: shape.hasFill, hasStroke: hasVisibleStroke,
                              strokeWidth: shape.strokeWidth)
        case .cloud:
            StyledCanvasShape(shape: CloudShape(), fillColor: fillColor, strokeColor: strokeColor,
                              hasFill: shape.hasFill, hasStroke: hasVisibleStroke,
                              strokeWidth: shape.strokeWidth)
        case .parallelogram:
            StyledCanvasShape(shape: ParallelogramShape(), fillColor: fillColor, strokeColor: strokeColor,
                              hasFill: shape.hasFill, hasStroke: hasVisibleStroke,
                              strokeWidth: shape.strokeWidth)
        case .cylinder:
            StyledCanvasShape(shape: CylinderShape(), fillColor: fillColor, strokeColor: strokeColor,
                              hasFill: shape.hasFill, hasStroke: hasVisibleStroke,
                              strokeWidth: shape.strokeWidth)
        case .document:
            StyledCanvasShape(shape: DocumentShape(), fillColor: fillColor, strokeColor: strokeColor,
                              hasFill: shape.hasFill, hasStroke: hasVisibleStroke,
                              strokeWidth: shape.strokeWidth)
        case .terminator:
            StyledCanvasShape(shape: Capsule(), fillColor: fillColor, strokeColor: strokeColor,
                              hasFill: shape.hasFill, hasStroke: hasVisibleStroke,
                              strokeWidth: shape.strokeWidth)
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
                Menu {
                    ForEach(ShapeLineEnding.allCases) { ending in
                        Button {
                            setLineEnding(ending)
                        } label: {
                            Label(ending.title, systemImage: ending.icon)
                        }
                    }
                } label: {
                    Image(systemName: shape.lineEnding.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(shape.lineEnding == .none ? Color.primary.opacity(0.6) : Color.accentColor)
                        .frame(width: 26, height: 26)
                }

                Menu {
                    ForEach(ShapeLineStyle.allCases) { style in
                        Button {
                            setLineStyle(style)
                        } label: {
                            Label(style.title, systemImage: style.icon)
                        }
                    }
                } label: {
                    Image(systemName: shape.lineStyle.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(shape.lineStyle == .solid ? Color.primary.opacity(0.6) : Color.accentColor)
                        .frame(width: 26, height: 26)
                }
            }
            if shape.shapeKind == .triangle {
                Divider().frame(height: 18)
                Menu {
                    ForEach(TriangleVariant.allCases) { v in
                        Button {
                            let oldValue = shape.triangleVariantRaw
                            shape.triangleVariant = v; shape.updatedAt = Date(); try? context.save()
                            Task { await ShapeSyncService.shared.upsert(shape) }
                            canvasHistory.recordElementChange(
                                name: "Change triangle type", element: shape,
                                from: oldValue, to: shape.triangleVariantRaw, context: context
                            ) { $0.triangleVariantRaw = $1 }
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
                            let oldValue = shape.polygonSides
                            shape.polygonSides = n; shape.updatedAt = Date(); try? context.save()
                            Task { await ShapeSyncService.shared.upsert(shape) }
                            canvasHistory.recordElementChange(
                                name: "Change polygon sides", element: shape,
                                from: oldValue, to: shape.polygonSides, context: context,
                                coalescingKey: "shape-sides-\(shape.id)"
                            ) { $0.polygonSides = $1 }
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
        let oldState = ShapeStyleHistoryState(shape)
        shape.strokeColorName = name
        if name != "none", shape.strokeWidth <= 0 {
            shape.strokeWidth = 2.5
        }
        persistShapeStyle(from: oldState)
    }

    private func setFillEnabled(_ enabled: Bool) {
        guard shape.shapeKind.supportsFill else { return }
        if !enabled && !canDisableFill { return }
        let oldState = ShapeStyleHistoryState(shape)
        shape.hasFill = enabled
        persistShapeStyle(from: oldState)
    }

    private func setFillColor(_ name: String) {
        guard shape.shapeKind.supportsFill else { return }
        let oldState = ShapeStyleHistoryState(shape)
        shape.fillColorName = name
        shape.hasFill = true
        persistShapeStyle(from: oldState)
    }

    private func setStrokeWidth(_ width: Double) {
        guard hasVisibleStroke else { return }
        let oldState = ShapeStyleHistoryState(shape)
        shape.strokeWidth = width
        persistShapeStyle(from: oldState)
    }

    private func setLineEnding(_ ending: ShapeLineEnding) {
        guard shape.shapeKind == .line, ending != shape.lineEnding else { return }
        let oldState = ShapeLineAppearanceHistoryState(shape)
        shape.lineEnding = ending
        persistLineAppearance(from: oldState)
    }

    private func setLineStyle(_ style: ShapeLineStyle) {
        guard shape.shapeKind == .line, style != shape.lineStyle else { return }
        let oldState = ShapeLineAppearanceHistoryState(shape)
        shape.lineStyle = style
        persistLineAppearance(from: oldState)
    }

    private func persistLineAppearance(from oldState: ShapeLineAppearanceHistoryState) {
        shape.updatedAt = Date()
        try? context.save()
        Task { await ShapeSyncService.shared.upsert(shape) }
        canvasHistory.recordElementChange(
            name: "Change line appearance",
            element: shape,
            from: oldState,
            to: ShapeLineAppearanceHistoryState(shape),
            context: context
        ) { target, state in
            state.apply(to: target)
        }
    }

    private func ensureVisibleStyle() {
        if shape.hasVisibleStyle { return }
        shape.strokeColorName = "primary"
        shape.strokeWidth = max(shape.strokeWidth, 2.5)
        persistShapeStyle()
    }

    private func persistShapeStyle(from oldState: ShapeStyleHistoryState? = nil) {
        shape.updatedAt = Date()
        try? context.save()
        Task { await ShapeSyncService.shared.upsert(shape) }
        if let oldState {
            canvasHistory.recordElementChange(
                name: "Change shape style",
                element: shape,
                from: oldState,
                to: ShapeStyleHistoryState(shape),
                context: context,
                coalescingKey: "shape-style-\(shape.id)"
            ) { target, state in
                state.apply(to: target)
            }
        }
    }

    private var cornerHandles: some View {
        let hw = currentSize.width / 2
        let hh = currentSize.height / 2
        return ZStack {
            tapHandle(icon: "trash", color: .red, x: -hw, y: -hh) {
                vm.delete(shape: shape, context: context, undoManager: canvasHistory)
            }
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
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasViewportCoordinateSpace))
                .onChanged { value in
                    rotationAngle = rotationGestureState.update(
                        pointer: value.location,
                        center: rotationCenter,
                        currentRotation: rotationAngle
                    )
                }
                .onEnded { _ in
                    rotationGestureState.reset()
                    let oldRotation = shape.rotation
                    shape.rotation = rotationAngle; shape.updatedAt = Date(); try? context.save()
                    Task { await ShapeSyncService.shared.upsert(shape) }
                    canvasHistory.recordElementChange(
                        name: "Rotate shape",
                        element: shape,
                        from: oldRotation,
                        to: shape.rotation,
                        context: context
                    ) { $0.rotation = $1 }
                })
    }

    private var rotationCenter: CGPoint {
        CGPoint(x: shape.x * canvasScale + canvasOffset.width,
                y: shape.y * canvasScale + canvasOffset.height)
    }

    private func resizeHandle(x: CGFloat, y: CGFloat) -> some View {
        handleCircle(icon: "arrow.up.left.and.arrow.down.right", color: .green)
            .offset(x: x, y: y)
            .gesture(DragGesture()
                .onChanged { resizeDelta = $0.translation }
                .onEnded { value in
                    let t = value.translation; resizeDelta = .zero
                    vm.updateSize(
                        shape: shape,
                        width: shape.width + t.width,
                        height: shape.height + t.height,
                        context: context,
                        undoManager: canvasHistory
                    )
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
                vm.updatePosition(
                    shape: shape,
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

    private func paletteColor(_ name: String) -> Color {
        ShapeColorPalette.color(named: name)
    }
}

private struct ShapeInteractionRegion: Shape {
    let kind: ShapeKind
    let triangleVariant: TriangleVariant
    let polygonSides: Int
    let capturesInterior: Bool
    let lineEnding: ShapeLineEnding
    let strokeWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let basePath = basePath(in: rect)
        guard !capturesInterior || kind == .line else { return basePath }

        var hitPath = basePath.strokedPath(
            StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
        )
        if kind == .line, lineEnding.includesStart {
            hitPath.addPath(arrowPath(in: rect, atStart: true))
        }
        if kind == .line, lineEnding.includesEnd {
            hitPath.addPath(arrowPath(in: rect, atStart: false))
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
        case .roundedRectangle:
            return RoundedRectangle(cornerRadius: 22).path(in: rect)
        case .triangle:
            return TriangleShape(variant: triangleVariant).path(in: rect)
        case .polygon:
            return PolygonShape(sides: polygonSides).path(in: rect)
        case .circle:
            return Circle().path(in: rect)
        case .ellipse:
            return Ellipse().path(in: rect)
        case .diamond:
            return DiamondShape().path(in: rect)
        case .star:
            return StarShape().path(in: rect)
        case .speechBubble:
            return SpeechBubbleShape().path(in: rect)
        case .cloud:
            return CloudShape().path(in: rect)
        case .parallelogram:
            return ParallelogramShape().path(in: rect)
        case .cylinder:
            return CylinderShape().path(in: rect)
        case .document:
            return DocumentShape().path(in: rect)
        case .terminator:
            return Capsule().path(in: rect)
        }
    }

    private func arrowPath(in rect: CGRect, atStart: Bool) -> Path {
        Path { path in
            let arrowLength = max(8, strokeWidth * 0.8)
            let tipX = atStart ? rect.minX : rect.maxX
            let baseX = atStart ? tipX + arrowLength : tipX - arrowLength
            path.move(to: CGPoint(x: tipX, y: rect.midY))
            path.addLine(to: CGPoint(x: baseX, y: rect.midY - arrowLength * 0.7))
            path.addLine(to: CGPoint(x: baseX, y: rect.midY + arrowLength * 0.7))
            path.closeSubpath()
        }
    }
}

struct LineShapeView: View {
    let width: CGFloat
    let strokeColor: Color
    let strokeWidth: Double
    let ending: ShapeLineEnding
    let lineStyle: ShapeLineStyle

    var body: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            let arrowSize = max(9, CGFloat(strokeWidth) * 4)
            let startX = ending.includesStart ? arrowSize * 0.8 : 0
            let endX = geo.size.width - (ending.includesEnd ? arrowSize * 0.8 : 0)
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: startX, y: midY))
                    p.addLine(to: CGPoint(x: endX, y: midY))
                }.stroke(
                    strokeColor,
                    style: StrokeStyle(
                        lineWidth: strokeWidth,
                        lineCap: .round,
                        dash: lineStyle.dashPattern(for: CGFloat(strokeWidth))
                    )
                )
                if ending.includesStart { arrowHead(at: 0, midY: midY, size: arrowSize, pointsRight: false) }
                if ending.includesEnd { arrowHead(at: geo.size.width, midY: midY, size: arrowSize, pointsRight: true) }
            }
        }
    }

    private func arrowHead(at x: CGFloat, midY: CGFloat, size: CGFloat, pointsRight: Bool) -> some View {
        Path { path in
            let baseX = pointsRight ? x - size : x + size
            path.move(to: CGPoint(x: x, y: midY))
            path.addLine(to: CGPoint(x: baseX, y: midY - size * 0.62))
            path.addLine(to: CGPoint(x: baseX, y: midY + size * 0.62))
            path.closeSubpath()
        }
        .fill(strokeColor)
    }
}

struct StyledCanvasShape<S: Shape>: View {
    let shape: S
    let fillColor: Color
    let strokeColor: Color
    let hasFill: Bool
    let hasStroke: Bool
    let strokeWidth: Double

    var body: some View {
        ZStack {
            if hasFill { shape.fill(fillColor) }
            if hasStroke {
                shape.stroke(
                    strokeColor,
                    style: StrokeStyle(lineWidth: strokeWidth, lineJoin: .round)
                )
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

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}

struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.44

        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

struct SpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(18, min(rect.width, rect.height) * 0.16)
        let bubbleBottom = rect.maxY - rect.height * 0.18
        let tailStart = rect.minX + rect.width * 0.28
        let tailEnd = rect.minX + rect.width * 0.14

        return Path { path in
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                              control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: bubbleBottom - radius))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: bubbleBottom),
                              control: CGPoint(x: rect.maxX, y: bubbleBottom))
            path.addLine(to: CGPoint(x: tailStart, y: bubbleBottom))
            path.addLine(to: CGPoint(x: tailEnd, y: rect.maxY))
            path.addLine(to: CGPoint(x: tailEnd + rect.width * 0.02, y: bubbleBottom))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: bubbleBottom))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: bubbleBottom - radius),
                              control: CGPoint(x: rect.minX, y: bubbleBottom))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                              control: CGPoint(x: rect.minX, y: rect.minY))
            path.closeSubpath()
        }
    }
}

struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.maxY * 0.78 + rect.minY * 0.22))
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.43),
                control1: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY + rect.height * 0.78),
                control2: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.minY + rect.height * 0.44)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.51, y: rect.minY + rect.height * 0.24),
                control1: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.16),
                control2: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.minY + rect.height * 0.12)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.42),
                control1: CGPoint(x: rect.minX + rect.width * 0.63, y: rect.minY + rect.height * 0.16),
                control2: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.25)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.80, y: rect.minY + rect.height * 0.80),
                control1: CGPoint(x: rect.minX + rect.width * 0.98, y: rect.minY + rect.height * 0.35),
                control2: CGPoint(x: rect.minX + rect.width * 1.00, y: rect.minY + rect.height * 0.74)
            )
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.80))
            path.closeSubpath()
        }
    }
}

struct ParallelogramShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = min(rect.width * 0.16, rect.height * 0.34)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct CylinderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let capHeight = min(max(rect.height * 0.16, 14), 30)
        let radiusX = rect.width / 2
        let radiusY = capHeight / 2
        let topCenterY = rect.minY + radiusY
        let bottomCenterY = rect.maxY - radiusY
        let kappa: CGFloat = 0.552_284_75
        var path = Path()

        // One continuous outer silhouette: straight sides, one clean bottom
        // ellipse, and an upper arc that exactly matches the top ellipse.
        path.move(to: CGPoint(x: rect.minX, y: topCenterY))
        path.addLine(to: CGPoint(x: rect.minX, y: bottomCenterY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: bottomCenterY + radiusY * kappa),
            control2: CGPoint(x: rect.midX - radiusX * kappa, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: bottomCenterY),
            control1: CGPoint(x: rect.midX + radiusX * kappa, y: rect.maxY),
            control2: CGPoint(x: rect.maxX, y: bottomCenterY + radiusY * kappa)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: topCenterY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.maxX, y: topCenterY - radiusY * kappa),
            control2: CGPoint(x: rect.midX + radiusX * kappa, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: topCenterY),
            control1: CGPoint(x: rect.midX - radiusX * kappa, y: rect.minY),
            control2: CGPoint(x: rect.minX, y: topCenterY - radiusY * kappa)
        )
        path.closeSubpath()

        // The top ellipse adds only the visible front seam; its upper half
        // sits exactly on the silhouette instead of floating above it.
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.minY,
                                   width: rect.width, height: capHeight))
        return path
    }
}

struct DocumentShape: Shape {
    func path(in rect: CGRect) -> Path {
        let wave = min(rect.height * 0.12, 22)
        let baseline = rect.maxY - wave
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: baseline))
            path.addCurve(
                to: CGPoint(x: rect.minX, y: baseline),
                control1: CGPoint(x: rect.maxX - rect.width * 0.27, y: baseline - wave),
                control2: CGPoint(x: rect.minX + rect.width * 0.27, y: baseline + wave)
            )
            path.closeSubpath()
        }
    }
}
