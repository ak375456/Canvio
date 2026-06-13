//
//  CanvasDrawingOverlay.swift
//  Ponder
//

import SwiftUI
import PencilKit

#if os(iOS)

// MARK: - Preference key

private struct ContentAreaSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

// MARK: - Overlay

struct CanvasDrawingOverlay: View {
    @Binding var isActive: Bool
    @Binding var isDrawingInputActive: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Canvas state captured the moment the overlay was opened.
    let startScale:  CGFloat
    let startOffset: CGSize

    /// Live canvas state — updated by the parent as the user pans / zooms.
    @Binding var liveScale:  CGFloat
    @Binding var liveOffset: CGSize

    @State private var drawing: PKDrawing
    @State private var isDrawingModeActive = true
    @State private var isPickingColor = false
    @State private var selectedColor = UIColor.systemOrange
    @State private var pickedColorRevision = 0

    /// The scale / offset that match the coordinate space of the current
    /// strokes in `drawing`.  Updated each time we return from Navigate mode.
    @State private var effectiveScale:  CGFloat
    @State private var effectiveOffset: CGSize

    /// Snapshot rendered ONCE when entering Navigate mode.
    /// Pure UIImage → SwiftUI transform with no UIKit render-cycle lag.
    @State private var navigateSnapshot: UIImage? = nil

    /// Content-area size captured from a GeometryReader (needed for snapshot).
    @State private var contentAreaSize: CGSize = .zero

    let smartShapeSnappingEnabled: Bool
    let onSave: (PKDrawing, CGFloat, CGSize) -> Void

    // MARK: Init

    init(
        isActive:    Binding<Bool>,
        isDrawingInputActive: Binding<Bool>,
        startScale:  CGFloat,
        startOffset: CGSize,
        liveScale:   Binding<CGFloat>,
        liveOffset:  Binding<CGSize>,
        initialDrawing: PKDrawing = PKDrawing(),
        smartShapeSnappingEnabled: Bool,
        onSave:      @escaping (PKDrawing, CGFloat, CGSize) -> Void
    ) {
        self._isActive       = isActive
        self._isDrawingInputActive = isDrawingInputActive
        self.startScale      = startScale
        self.startOffset     = startOffset
        self._liveScale      = liveScale
        self._liveOffset     = liveOffset
        self.smartShapeSnappingEnabled = smartShapeSnappingEnabled
        self.onSave          = onSave
        self._drawing         = State(initialValue: initialDrawing)
        self._effectiveScale  = State(initialValue: startScale)
        self._effectiveOffset = State(initialValue: startOffset)
    }

    // MARK: Visual transform (Navigate mode only)

    /// Ratio to visually scale the snapshot so it tracks the canvas zoom.
    private var visualRatio: CGFloat { liveScale / effectiveScale }
    private var usesCompactToolbar: Bool { horizontalSizeClass == .compact }
    private var modeButtonTitle: String {
        if isDrawingModeActive {
            return usesCompactToolbar ? "Draw" : "Drawing"
        }
        return usesCompactToolbar ? "Move" : "Navigate"
    }

    /// Translation to visually shift the snapshot so it tracks the canvas pan.
    private var visualTranslation: CGSize {
        let r = visualRatio
        return CGSize(
            width:  liveOffset.width  - effectiveOffset.width  * r,
            height: liveOffset.height - effectiveOffset.height * r
        )
    }

    // MARK: Body

    var body: some View {
        ZStack {

            // ── Invisible size capturer ──────────────────────────────────────
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ContentAreaSizeKey.self, value: geo.size)
                    }
                )
                .onPreferenceChange(ContentAreaSizeKey.self) { contentAreaSize = $0 }

            // ── Hit-test backdrop (draw mode only) ───────────────────────────
            // Prevents accidental taps on canvas elements while we are drawing.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .allowsHitTesting(isDrawingModeActive)

            // ── Drawing surface ──────────────────────────────────────────────
            if isDrawingModeActive {

                // Draw mode: live PKCanvasView.
                // liveScale / liveOffset are NOT passed here — PKCanvasView
                // blocks all touches while active, so they never change and
                // updateUIView is never called unnecessarily.
                FullCanvasDrawView(
                    drawing: $drawing,
                    smartShapeSnappingEnabled: smartShapeSnappingEnabled,
                    selectedColor: $selectedColor,
                    colorRevision: pickedColorRevision
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if let snap = navigateSnapshot, contentAreaSize != .zero {

                // Navigate mode: pre-computed UIImage snapshot.
                // Rendered ONCE on mode-switch; the SwiftUI transform below
                // makes it track the canvas with zero UIKit lag.
                Image(uiImage: snap)
                    .resizable()
                    .frame(width: contentAreaSize.width, height: contentAreaSize.height)
                    .scaleEffect(visualRatio, anchor: .topLeading)
                    .offset(visualTranslation)
                    .allowsHitTesting(false)
            }

            // ── Toolbar ──────────────────────────────────────────────────────
            VStack {
                overlayToolbar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                Spacer()
            }

            if isPickingColor {
                DrawingColorSamplingOverlay(
                    onColorPicked: { color in
                        selectedColor = color
                        pickedColorRevision += 1
                        isPickingColor = false
                    },
                    onCancel: {
                        isPickingColor = false
                    }
                )
                .zIndex(250)
            }
        }
    }

    // MARK: Mode toggle

    private func toggleMode() {
        isPickingColor = false

        if isDrawingModeActive {
            // Draw → Navigate ────────────────────────────────────────────────
            isDrawingInputActive = false
            // Render the drawing to a UIImage once.  During Navigate mode
            // this image is shown with a SwiftUI transform — pure GPU compositing,
            // no UIKit involvement, no per-frame updateUIView calls.
            if contentAreaSize != .zero {
                navigateSnapshot = drawing.image(
                    from:  CGRect(origin: .zero, size: contentAreaSize),
                    scale: UIScreen.main.scale
                )
            }
        } else {
            // Navigate → Draw ────────────────────────────────────────────────
            isDrawingInputActive = true
            // Bake the accumulated pan/zoom delta into PKDrawing so that new
            // strokes share the same coordinate space as the existing ones.
            let ratio = liveScale  / effectiveScale
            let tx    = liveOffset.width  - effectiveOffset.width  * ratio
            let ty    = liveOffset.height - effectiveOffset.height * ratio
            let moved = abs(ratio - 1.0) > 0.0001 || abs(tx) > 0.5 || abs(ty) > 0.5

            if moved {
                let delta = CGAffineTransform(a: ratio, b: 0, c: 0, d: ratio, tx: tx, ty: ty)
                drawing = drawing.transformed(using: delta)
            }

            effectiveScale  = liveScale
            effectiveOffset = liveOffset
            navigateSnapshot = nil   // PKCanvasView takes over rendering
        }

        // ⚠️  No withAnimation here.
        // The visual transform on the snapshot and the PKDrawing content
        // switch atomically.  An animation would create a window where the
        // transform is partially applied but the data has already changed,
        // producing a blink / ghost frame.
        isDrawingModeActive.toggle()
    }

    // MARK: Toolbar

    private var overlayToolbar: some View {
        HStack(spacing: usesCompactToolbar ? 8 : 12) {

            // Done
            Button { saveAndDismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                    Text("Done").font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, usesCompactToolbar ? 12 : 16).padding(.vertical, 9)
                .background(Color.orange, in: Capsule())
                .shadow(color: .orange.opacity(0.35), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            // Clear
            Button {
                drawing = PKDrawing()
                // Refresh snapshot if we are in Navigate mode.
                if !isDrawingModeActive, contentAreaSize != .zero {
                    navigateSnapshot = drawing.image(
                        from:  CGRect(origin: .zero, size: contentAreaSize),
                        scale: UIScreen.main.scale
                    )
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "trash").font(.system(size: 13, weight: .semibold))
                    if !usesCompactToolbar {
                        Text("Clear").font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.red)
                .padding(.horizontal, usesCompactToolbar ? 10 : 12).padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)

            DrawingColorPickerButton(
                selectedColor: $selectedColor,
                compact: usesCompactToolbar,
                isActive: isPickingColor
            ) {
                isPickingColor.toggle()
            }

            Spacer(minLength: usesCompactToolbar ? 6 : 12)

            // Draw / Navigate toggle
            Button { toggleMode() } label: {
                HStack(spacing: 5) {
                    Image(systemName: isDrawingModeActive ? "hand.draw.fill" : "hand.raised.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(modeButtonTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(isDrawingModeActive ? Color.white : Color.primary)
                .padding(.horizontal, usesCompactToolbar ? 10 : 12).padding(.vertical, 9)
                .background(
                    isDrawingModeActive
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(.regularMaterial),
                    in: Capsule()
                )
                .shadow(
                    color:  isDrawingModeActive ? Color.accentColor.opacity(0.35) : .clear,
                    radius: 6, x: 0, y: 2
                )
            }
            .buttonStyle(.plain)

            // Cancel
            Button {
                isDrawingInputActive = true
                isActive = false
            } label: {
                Text("Cancel")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, usesCompactToolbar ? 10 : 12).padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Save

    private func saveAndDismiss() {
        isPickingColor = false

        if isDrawingModeActive {
            // Already in Draw mode — strokes are in the effectiveScale/Offset space.
            onSave(drawing, effectiveScale, effectiveOffset)
        } else {
            // In Navigate mode — bake the outstanding delta before saving.
            var final = drawing
            let ratio = liveScale  / effectiveScale
            let tx    = liveOffset.width  - effectiveOffset.width  * ratio
            let ty    = liveOffset.height - effectiveOffset.height * ratio
            if abs(ratio - 1.0) > 0.0001 || abs(tx) > 0.5 || abs(ty) > 0.5 {
                let delta = CGAffineTransform(a: ratio, b: 0, c: 0, d: ratio, tx: tx, ty: ty)
                final = final.transformed(using: delta)
            }
            onSave(final, liveScale, liveOffset)
        }
        isDrawingInputActive = true
        isActive = false
    }
}

// MARK: - Live PKCanvasView (Draw mode only)

private struct FullCanvasDrawView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let smartShapeSnappingEnabled: Bool
    @Binding var selectedColor: UIColor
    let colorRevision: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(
            drawing: $drawing,
            selectedColor: $selectedColor,
            smartShapeSnappingEnabled: smartShapeSnappingEnabled
        )
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas          = PKCanvasView()
        canvas.drawing      = drawing
        canvas.backgroundColor = .clear
        canvas.isOpaque     = false
        canvas.drawingPolicy = .anyInput
        canvas.isScrollEnabled = false
        canvas.delegate     = context.coordinator
        context.coordinator.canvasView = canvas

        let picker = PKToolPicker()
        context.coordinator.toolPicker = picker
        picker.addObserver(canvas)
        picker.addObserver(context.coordinator)
        context.coordinator.rememberPickerSelection(picker)
        context.coordinator.markAppliedColorRevision(colorRevision)
        picker.setVisible(true, forFirstResponder: canvas)
        context.coordinator.syncSelectedColorFromCurrentInkingTool(canvas)
        canvas.becomeFirstResponder()
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.smartShapeSnappingEnabled = smartShapeSnappingEnabled
        // Only update drawing when it changed from outside (Clear button or
        // delta bake after Navigate mode).  Guard prevents self-triggering.
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
        context.coordinator.applyPickedColorIfNeeded(
            to: canvas,
            selectedColor: selectedColor,
            colorRevision: colorRevision
        )
        // Restore first-responder status only if lost (e.g. after clear).
        if !canvas.isFirstResponder {
            context.coordinator.toolPicker?.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
        }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker?.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker?.removeObserver(coordinator)
        coordinator.toolPicker?.removeObserver(canvas)
        canvas.resignFirstResponder()
    }

    class Coordinator: NSObject, PKCanvasViewDelegate, PKToolPickerObserver {
        @Binding var drawing: PKDrawing
        @Binding var selectedColor: UIColor
        weak var canvasView: PKCanvasView?
        var toolPicker: PKToolPicker?
        var smartShapeSnappingEnabled: Bool {
            didSet {
                shapeSnapController.isEnabled = smartShapeSnappingEnabled
            }
        }
        private var lastAppliedColorRevision = 0
        private var lastPickerToolItemIdentifier: String?
        private var lastPickerInkType: PKInkingTool.InkType?
        private var isApplyingPickedColor = false
        private let shapeSnapController = PencilShapeSnapController()

        init(drawing: Binding<PKDrawing>,
             selectedColor: Binding<UIColor>,
             smartShapeSnappingEnabled: Bool) {
            self._drawing = drawing
            self._selectedColor = selectedColor
            self.smartShapeSnappingEnabled = smartShapeSnappingEnabled
            self.shapeSnapController.isEnabled = smartShapeSnappingEnabled
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing = canvasView.drawing
            guard !shapeSnapController.isApplyingProgrammaticSnap else { return }
            shapeSnapController.scheduleSnap(on: canvasView) { [weak self] snappedDrawing in
                self?.drawing = snappedDrawing
            }
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            shapeSnapController.scheduleSnap(on: canvasView) { [weak self] snappedDrawing in
                self?.drawing = snappedDrawing
            }
        }

        func toolPickerSelectedToolDidChange(_ toolPicker: PKToolPicker) {
            handleToolPickerChange(toolPicker)
        }

        @available(iOS 18.0, *)
        func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker) {
            handleToolPickerChange(toolPicker)
        }

        func markAppliedColorRevision(_ revision: Int) {
            lastAppliedColorRevision = revision
        }

        func applyPickedColorIfNeeded(to canvas: PKCanvasView,
                                      selectedColor: UIColor,
                                      colorRevision: Int) {
            guard colorRevision != lastAppliedColorRevision else { return }
            applyColor(selectedColor, to: canvas, switchToPenIfNeeded: true)
            lastAppliedColorRevision = colorRevision
        }

        func syncSelectedColorFromCurrentInkingTool(_ canvas: PKCanvasView) {
            guard !isApplyingPickedColor,
                  let color = currentInkingTool(for: canvas)?.color.withAlphaComponent(1),
                  !selectedColor.isDrawingEquivalent(to: color) else { return }
            selectedColor = color
        }

        func rememberPickerSelection(_ toolPicker: PKToolPicker) {
            _ = updatePickerSelectionState(toolPicker)
        }

        private func handleToolPickerChange(_ toolPicker: PKToolPicker) {
            let didSwitchTool = updatePickerSelectionState(toolPicker)
            let didSwitchToInkingTool = didSwitchTool && pickerInkingTool(from: toolPicker) != nil

            DispatchQueue.main.async { [weak self] in
                guard let self, let canvas = self.canvasView else { return }

                if didSwitchToInkingTool {
                    self.applyColor(self.selectedColor, to: canvas, switchToPenIfNeeded: false)
                } else {
                    self.syncSelectedColorFromCurrentInkingTool(canvas)
                }
            }
        }

        private func applyColor(_ selectedColor: UIColor,
                                to canvas: PKCanvasView,
                                switchToPenIfNeeded: Bool) {
            guard !isApplyingPickedColor else { return }

            let color = selectedColor.withAlphaComponent(1)
            let nextTool: PKInkingTool

            if let inkingTool = canvas.tool as? PKInkingTool {
                nextTool = PKInkingTool(inkingTool.inkType, color: color, width: inkingTool.width)
            } else if let pickerTool = pickerInkingTool(from: toolPicker) {
                nextTool = PKInkingTool(pickerTool.inkType, color: color, width: pickerTool.width)
            } else if switchToPenIfNeeded {
                nextTool = PKInkingTool(.pen, color: color, width: 5)
            } else {
                return
            }

            isApplyingPickedColor = true
            canvas.tool = nextTool
            isApplyingPickedColor = false
        }

        private func currentInkingTool(for canvas: PKCanvasView) -> PKInkingTool? {
            if let inkingTool = canvas.tool as? PKInkingTool { return inkingTool }
            return pickerInkingTool(from: toolPicker)
        }

        private func pickerInkingTool(from toolPicker: PKToolPicker?) -> PKInkingTool? {
            guard let toolPicker else { return nil }
            if #available(iOS 18.0, *) {
                return (toolPicker.selectedToolItem as? PKToolPickerInkingItem)?.inkingTool
            } else {
                return toolPicker.selectedTool as? PKInkingTool
            }
        }

        private func updatePickerSelectionState(_ toolPicker: PKToolPicker) -> Bool {
            let previousIdentifier = lastPickerToolItemIdentifier
            let previousInkType = lastPickerInkType

            if #available(iOS 18.0, *) {
                lastPickerToolItemIdentifier = toolPicker.selectedToolItem.identifier
            }
            lastPickerInkType = pickerInkingTool(from: toolPicker)?.inkType

            if #available(iOS 18.0, *) {
                return previousIdentifier != nil &&
                    previousIdentifier != lastPickerToolItemIdentifier
            }
            return previousInkType != nil && previousInkType != lastPickerInkType
        }
    }
}

extension UIColor {
    fileprivate func isDrawingEquivalent(to other: UIColor) -> Bool {
        guard let lhs = drawingRGBAComponents(),
              let rhs = other.drawingRGBAComponents() else {
            return cgColor == other.cgColor
        }

        return zip(lhs, rhs).allSatisfy { abs($0 - $1) < 0.001 }
    }

    fileprivate func drawingRGBAComponents() -> [CGFloat]? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        return [red, green, blue, alpha]
    }
}

#else

// MARK: - macOS

struct CanvasDrawingOverlay: View {
    @Binding var isActive:    Bool
    @Binding var isDrawingInputActive: Bool
    let startScale:           CGFloat
    let startOffset:          CGSize
    @Binding var liveScale:   CGFloat
    @Binding var liveOffset:  CGSize
    let onSave: (PKDrawing, CGFloat, CGSize) -> Void

    @State private var drawing: PKDrawing

    init(
        isActive: Binding<Bool>,
        isDrawingInputActive: Binding<Bool>,
        startScale: CGFloat,
        startOffset: CGSize,
        liveScale: Binding<CGFloat>,
        liveOffset: Binding<CGSize>,
        initialDrawing: PKDrawing = PKDrawing(),
        onSave: @escaping (PKDrawing, CGFloat, CGSize) -> Void
    ) {
        self._isActive = isActive
        self._isDrawingInputActive = isDrawingInputActive
        self.startScale = startScale
        self.startOffset = startOffset
        self._liveScale = liveScale
        self._liveOffset = liveOffset
        self.onSave = onSave
        self._drawing = State(initialValue: initialDrawing)
    }

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()

            MacDrawingEditor(drawing: drawing) { newDrawing in
                drawing = newDrawing
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                overlayToolbar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isDrawingInputActive = true }
    }

    private var overlayToolbar: some View {
        HStack(spacing: 12) {
            Button { saveAndDismiss() } label: {
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
            .disabled(drawing.strokes.isEmpty)
            .opacity(drawing.strokes.isEmpty ? 0.55 : 1)

            Spacer(minLength: 12)

            Button {
                isDrawingInputActive = true
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private func saveAndDismiss() {
        onSave(drawing, liveScale, liveOffset)
        isDrawingInputActive = true
        isActive = false
    }
}

#endif
