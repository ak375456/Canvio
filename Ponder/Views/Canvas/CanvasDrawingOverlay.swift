//
//  CanvasDrawingOverlay.swift
//  Ponder
//

import SwiftUI
import PencilKit

#if os(iOS)
struct CanvasDrawingOverlay: View {
    @Binding var isActive: Bool
    let canvasScale: CGFloat
    let canvasOffset: CGSize

    @State private var drawing = PKDrawing()
    let onSave: (PKDrawing) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.01)
                .ignoresSafeArea()

            FullCanvasDrawView(
                drawing: $drawing,
                canvasScale: canvasScale,
                canvasOffset: canvasOffset
            )
            .ignoresSafeArea()

            VStack {
                overlayToolbar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                Spacer()
            }
        }
    }

    private var overlayToolbar: some View {
        HStack(spacing: 12) {
            Button {
                onSave(drawing)
                isActive = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                    Text("Done")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color.orange, in: Capsule())
                .shadow(color: .orange.opacity(0.35), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            Button {
                drawing = PKDrawing()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Clear")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                isActive = false
            } label: {
                Text("Cancel")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Full canvas PKCanvasView

private struct FullCanvasDrawView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let canvasScale: CGFloat
    let canvasOffset: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.delegate = context.coordinator
        context.coordinator.canvasView = canvas

        canvas.isScrollEnabled = false

        let toolPicker = PKToolPicker()
        context.coordinator.toolPicker = toolPicker
        toolPicker.addObserver(canvas)
        toolPicker.setVisible(true, forFirstResponder: canvas)
        canvas.becomeFirstResponder()

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
        context.coordinator.toolPicker?.setVisible(true, forFirstResponder: canvas)
        if !canvas.isFirstResponder { canvas.becomeFirstResponder() }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker?.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker?.removeObserver(canvas)
        canvas.resignFirstResponder()
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing
        weak var canvasView: PKCanvasView?
        var toolPicker: PKToolPicker?

        init(drawing: Binding<PKDrawing>) {
            self._drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing = canvasView.drawing
        }
    }
}

#else

struct CanvasDrawingOverlay: View {
    @Binding var isActive: Bool
    let canvasScale: CGFloat
    let canvasOffset: CGSize
    let onSave: (PKDrawing) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "applepencil")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text("Canvas drawing is available on iPad & iPhone")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Close") { isActive = false }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

#endif
