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

// MARK: - macOS (view-only)
struct DrawingCanvasView: View {
    let drawing: PKDrawing
    let isEditing: Bool
    let onDrawingChanged: (PKDrawing) -> Void

    var body: some View {
        GeometryReader { geo in
            if drawing.strokes.isEmpty {
                Color.clear
            } else {
                DrawingImage(drawing: drawing, size: geo.size)
            }
        }
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
