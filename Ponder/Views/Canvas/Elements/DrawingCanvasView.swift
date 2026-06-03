//
//  DrawingCanvasView.swift
//  Canvio
//

import SwiftUI
import PencilKit

#if os(iOS)

struct DrawingCanvasView: View {
    let drawing: PKDrawing
    let isEditing: Bool
    let onDrawingChanged: (PKDrawing) -> Void

    var body: some View {
        if isEditing {
            LivePKCanvas(drawing: drawing, onDrawingChanged: onDrawingChanged)
        } else {
            DrawingSnapshot(drawing: drawing)
        }
    }
}

// MARK: - Static snapshot
private struct DrawingSnapshot: View {
    let drawing: PKDrawing

    var body: some View {
        GeometryReader { geo in
            if drawing.strokes.isEmpty {
                Color.clear
            } else {
                let image = drawing.image(
                    from: CGRect(origin: .zero, size: geo.size),
                    scale: UIScreen.main.scale
                )
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
    }
}

// MARK: - Live PKCanvasView (card drawing)
// anyInput = finger or pencil draws.
// Two-finger pan is handled by PKCanvasView's built-in scroll view —
// it automatically reserves two-finger for scroll when isScrollEnabled=true.
private struct LivePKCanvas: UIViewRepresentable {
    let drawing: PKDrawing
    let onDrawingChanged: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing         = drawing
        canvas.backgroundColor = .clear
        canvas.isOpaque        = false
        // anyInput: finger and pencil both draw
        canvas.drawingPolicy   = .anyInput
        canvas.delegate        = context.coordinator
        context.coordinator.canvas = canvas

        // Enable built-in two-finger pan and pinch zoom
        canvas.isScrollEnabled  = true
        canvas.bouncesZoom      = true
        canvas.minimumZoomScale = 0.5
        canvas.maximumZoomScale = 5.0

        let toolPicker = PKToolPicker()
        context.coordinator.toolPicker = toolPicker
        toolPicker.addObserver(canvas)
        toolPicker.setVisible(true, forFirstResponder: canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing.dataRepresentation() != drawing.dataRepresentation()
            && !canvas.isFirstResponder {
            canvas.drawing = drawing
        }
        context.coordinator.toolPicker?.setVisible(true, forFirstResponder: canvas)
        if !canvas.isFirstResponder {
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker?.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker?.removeObserver(canvas)
        canvas.resignFirstResponder()
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let onDrawingChanged: (PKDrawing) -> Void
        weak var canvas: PKCanvasView?
        var toolPicker: PKToolPicker?

        init(onDrawingChanged: @escaping (PKDrawing) -> Void) {
            self.onDrawingChanged = onDrawingChanged
        }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            onDrawingChanged(canvas.drawing)
        }
    }
}

#else

// MARK: - macOS
struct DrawingCanvasView: View {
    let drawing: PKDrawing
    let isEditing: Bool
    let onDrawingChanged: (PKDrawing) -> Void

    var body: some View {
        GeometryReader { geo in
            if isEditing {
                MacDrawingEditor(
                    drawing: drawing,
                    onDrawingChanged: onDrawingChanged
                )
            } else {
                if drawing.strokes.isEmpty {
                    Color.clear
                } else {
                    DrawingImage(drawing: drawing, size: geo.size)
                }
            }
        }
    }
}

struct MacDrawingToolState: Equatable {
    var ink: MacDrawingInk = .pen
    var color: MacDrawingColor = .adaptive
    var width: CGFloat = 4
    var eraserWidth: CGFloat = 24
    var isErasing = false
}

enum MacDrawingInk: String, CaseIterable, Identifiable {
    case pen
    case pencil
    case marker
    case fountainPen
    case watercolor
    case crayon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen:         return "Pen"
        case .pencil:      return "Pencil"
        case .marker:      return "Marker"
        case .fountainPen: return "Fountain Pen"
        case .watercolor:  return "Watercolor"
        case .crayon:      return "Crayon"
        }
    }

    var icon: String {
        switch self {
        case .pen:         return "pencil.tip"
        case .pencil:      return "pencil"
        case .marker:      return "highlighter"
        case .fountainPen: return "paintbrush.pointed"
        case .watercolor:  return "paintbrush"
        case .crayon:      return "scribble"
        }
    }

    var inkType: PKInkingTool.InkType {
        switch self {
        case .pen:         return .pen
        case .pencil:      return .pencil
        case .marker:      return .marker
        case .fountainPen: return .fountainPen
        case .watercolor:  return .watercolor
        case .crayon:      return .crayon
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .pen:         return 4
        case .pencil:      return 5
        case .marker:      return 12
        case .fountainPen: return 4
        case .watercolor:  return 10
        case .crayon:      return 8
        }
    }
}

enum MacDrawingColor: String, CaseIterable, Identifiable {
    case adaptive
    case black
    case white
    case gray
    case red
    case orange
    case yellow
    case green
    case blue
    case purple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adaptive: return "Auto"
        case .black:    return "Black"
        case .white:    return "White"
        case .gray:     return "Gray"
        case .red:      return "Red"
        case .orange:   return "Orange"
        case .yellow:   return "Yellow"
        case .green:    return "Green"
        case .blue:     return "Blue"
        case .purple:   return "Purple"
        }
    }

    func nsColor(colorScheme: ColorScheme) -> NSColor {
        switch self {
        case .adaptive: return colorScheme == .dark ? .white : .black
        case .black:    return .black
        case .white:    return .white
        case .gray:     return .systemGray
        case .red:      return .systemRed
        case .orange:   return .systemOrange
        case .yellow:   return .systemYellow
        case .green:    return .systemGreen
        case .blue:     return .systemBlue
        case .purple:   return .systemPurple
        }
    }

    func swatchColor(colorScheme: ColorScheme) -> Color {
        Color(nsColor: nsColor(colorScheme: colorScheme))
    }
}

struct MacDrawingEditor: View {
    let drawing: PKDrawing
    let onDrawingChanged: (PKDrawing) -> Void

    @State private var tool = MacDrawingToolState()

    var body: some View {
        ZStack {
            MacFreehandPKDrawingView(
                drawing: drawing,
                tool: tool,
                onDrawingChanged: onDrawingChanged
            )

            VStack {
                Spacer()
                MacDrawingToolControls(tool: $tool)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
            .zIndex(1)
        }
    }
}

private struct MacDrawingToolControls: View {
    @Binding var tool: MacDrawingToolState
    @Environment(\.colorScheme) private var colorScheme

    private var activeWidth: Binding<Double> {
        Binding(
            get: { Double(tool.isErasing ? tool.eraserWidth : tool.width) },
            set: { value in
                if tool.isErasing {
                    tool.eraserWidth = CGFloat(value)
                } else {
                    tool.width = CGFloat(value)
                }
            }
        )
    }

    private var widthRange: ClosedRange<Double> {
        tool.isErasing ? 8...60 : 1...28
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(MacDrawingInk.allCases) { ink in
                        toolButton(
                            icon: ink.icon,
                            isSelected: !tool.isErasing && tool.ink == ink,
                            help: ink.title
                        ) {
                            tool.isErasing = false
                            tool.ink = ink
                            tool.width = ink.defaultWidth
                        }
                    }

                    toolButton(
                        icon: "eraser",
                        isSelected: tool.isErasing,
                        help: "Eraser"
                    ) {
                        tool.isErasing = true
                    }
                }

                Divider().frame(height: 24)

                HStack(spacing: 5) {
                    ForEach(MacDrawingColor.allCases) { color in
                        colorButton(color)
                    }
                }
                .opacity(tool.isErasing ? 0.45 : 1)
                .disabled(tool.isErasing)

                Divider().frame(height: 24)

                Slider(value: activeWidth, in: widthRange)
                    .frame(width: 96)
                    .help(tool.isErasing ? "Eraser Size" : "Stroke Width")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
    }

    private func toolButton(icon: String, isSelected: Bool, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 30, height: 28)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func colorButton(_ color: MacDrawingColor) -> some View {
        Button {
            tool.isErasing = false
            tool.color = color
        } label: {
            Circle()
                .fill(color.swatchColor(colorScheme: colorScheme))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(color == .white ? 0.35 : 0.12), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .frame(width: 26, height: 26)
                        .opacity(tool.color == color && !tool.isErasing ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .help(color.title)
    }
}

private struct MacFreehandPKDrawingView: View {
    let drawing: PKDrawing
    let tool: MacDrawingToolState
    var onDrawingChanged: (PKDrawing) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var workingDrawing = PKDrawing()
    @State private var committedDrawing = PKDrawing()
    @State private var currentPoints: [CGPoint] = []
    @State private var isDrawing = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if workingDrawing.strokes.isEmpty {
                    Color.clear
                } else {
                    DrawingImage(drawing: workingDrawing, size: geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(drawingGesture)
            .onAppear { syncFromExternalDrawing(drawing) }
            .onChange(of: drawing) { _, newValue in
                guard !isDrawing else { return }
                syncFromExternalDrawing(newValue)
            }
        }
    }

    private var strokeColor: NSColor {
        tool.color.nsColor(colorScheme: colorScheme)
    }

    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !isDrawing {
                    isDrawing = true
                    committedDrawing = workingDrawing
                    currentPoints = [value.startLocation]
                }

                appendPointIfNeeded(value.location)
                workingDrawing = drawingAfterCurrentGesture()
            }
            .onEnded { value in
                appendPointIfNeeded(value.location)
                let finalDrawing = drawingAfterCurrentGesture()
                workingDrawing = finalDrawing
                committedDrawing = finalDrawing
                currentPoints = []
                isDrawing = false
                onDrawingChanged(finalDrawing)
            }
    }

    private func syncFromExternalDrawing(_ newValue: PKDrawing) {
        workingDrawing = newValue
        committedDrawing = newValue
    }

    private func appendPointIfNeeded(_ point: CGPoint) {
        guard let lastPoint = currentPoints.last else {
            currentPoints.append(point)
            return
        }

        let distance = hypot(point.x - lastPoint.x, point.y - lastPoint.y)
        if distance >= 0.75 {
            currentPoints.append(point)
        }
    }

    private func drawingAfterCurrentGesture() -> PKDrawing {
        tool.isErasing ? drawingByErasingCurrentPath() : drawingByAppendingCurrentStroke()
    }

    private func drawingByAppendingCurrentStroke() -> PKDrawing {
        guard currentPoints.count > 1 else { return committedDrawing }

        let strokePoints = currentPoints.enumerated().map { index, point in
            PKStrokePoint(
                location: point,
                timeOffset: TimeInterval(index) * 0.01,
                size: CGSize(width: tool.width, height: tool.width),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: strokePoints, creationDate: Date())
        let stroke = PKStroke(
            ink: PKInk(tool.ink.inkType, color: strokeColor),
            path: path,
            transform: .identity,
            mask: nil
        )

        return PKDrawing(strokes: committedDrawing.strokes + [stroke])
    }

    private func drawingByErasingCurrentPath() -> PKDrawing {
        guard !currentPoints.isEmpty else { return committedDrawing }

        let radius = max(tool.eraserWidth / 2, 4)
        let remainingStrokes = committedDrawing.strokes.filter { stroke in
            !strokeIntersectsEraser(stroke, radius: radius)
        }
        return PKDrawing(strokes: remainingStrokes)
    }

    private func strokeIntersectsEraser(_ stroke: PKStroke, radius: CGFloat) -> Bool {
        let expandedBounds = stroke.renderBounds.insetBy(dx: -radius, dy: -radius)
        guard currentPoints.contains(where: { expandedBounds.contains($0) }) else {
            return false
        }

        var previousPoint: CGPoint?
        for strokePoint in stroke.path {
            let location = strokePoint.location.applying(stroke.transform)

            for eraserPoint in currentPoints {
                if distance(from: eraserPoint, to: location) <= radius {
                    return true
                }

                if let previousPoint,
                   distance(from: eraserPoint, toSegmentStart: previousPoint, end: location) <= radius {
                    return true
                }
            }

            previousPoint = location
        }

        return false
    }

    private func distance(from a: CGPoint, to b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func distance(from point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(from: point, to: start) }

        let rawProjection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let projection = min(1, max(0, rawProjection))
        let closest = CGPoint(x: start.x + projection * dx, y: start.y + projection * dy)
        return distance(from: point, to: closest)
    }
}

private struct DrawingImage: View {
    let drawing: PKDrawing
    let size: CGSize

    var body: some View {
        if let nsImage = renderedImage {
            Image(nsImage: nsImage).resizable().scaledToFill()
        } else {
            Color.clear
        }
    }

    private var renderedImage: NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let rect  = CGRect(origin: .zero, size: size)
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return drawing.image(from: rect, scale: scale)
    }
}

#endif
