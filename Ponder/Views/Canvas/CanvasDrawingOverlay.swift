//
//  CanvasDrawingOverlay.swift
//  Ponder
//

import SwiftUI
import PencilKit

#if os(iOS)

// MARK: - Overlay

struct CanvasDrawingOverlay: View {
    @Binding var isActive: Bool
    @Binding var isDrawingInputActive: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var settings: AppSettings

    /// Canvas state captured the moment the overlay was opened.
    let startScale:  CGFloat
    let startOffset: CGSize

    /// Live canvas state — updated by the parent as the user pans / zooms.
    @Binding var liveScale:  CGFloat
    @Binding var liveOffset: CGSize

    @State private var drawing: PKDrawing
    @State private var isPickingColor = false
    @State private var selectedColor = UIColor.systemOrange
    @State private var pickedColorRevision = 0
    @State private var effectiveScale:  CGFloat
    @State private var effectiveOffset: CGSize
    @State private var navigationSnapshot: DrawingNavigationSnapshot?
    @State private var redrawShield: RedrawShield?

    let smartShapeSnappingEnabled: Bool
    let showsHandwritingTextGrouping: Bool
    let savesAutomatically: Bool
    @Binding var handwritingTextGrouping: HandwritingTextGrouping
    @Binding var isHighlighterToolSelected: Bool
    let isCanvasNavigationGestureActive: Bool
    let onSave: (PKDrawing, CGFloat, CGSize) -> Void
    let onExit: () -> Void

    // MARK: Init

    init(
        isActive:    Binding<Bool>,
        isDrawingInputActive: Binding<Bool>,
        startScale:  CGFloat,
        startOffset: CGSize,
        liveScale:   Binding<CGFloat>,
        liveOffset:  Binding<CGSize>,
        initialDrawing: PKDrawing = PKDrawing(),
        isCanvasNavigationGestureActive: Bool = false,
        smartShapeSnappingEnabled: Bool,
        showsHandwritingTextGrouping: Bool = false,
        savesAutomatically: Bool = true,
        handwritingTextGrouping: Binding<HandwritingTextGrouping>,
        isHighlighterToolSelected: Binding<Bool>,
        onSave:      @escaping (PKDrawing, CGFloat, CGSize) -> Void,
        onExit:      @escaping () -> Void = {}
    ) {
        self._isActive       = isActive
        self._isDrawingInputActive = isDrawingInputActive
        self.startScale      = startScale
        self.startOffset     = startOffset
        self._liveScale      = liveScale
        self._liveOffset     = liveOffset
        self.isCanvasNavigationGestureActive = isCanvasNavigationGestureActive
        self.smartShapeSnappingEnabled = smartShapeSnappingEnabled
        self.showsHandwritingTextGrouping = showsHandwritingTextGrouping
        self.savesAutomatically = savesAutomatically
        self._handwritingTextGrouping = handwritingTextGrouping
        self._isHighlighterToolSelected = isHighlighterToolSelected
        self.onSave          = onSave
        self.onExit          = onExit
        self._drawing         = State(initialValue: initialDrawing)
        self._effectiveScale  = State(initialValue: startScale)
        self._effectiveOffset = State(initialValue: startOffset)
    }

    // MARK: Visual transform

    /// Ratio to visually scale the live drawing surface so it tracks canvas zoom.
    private var visualRatio: CGFloat { liveScale / max(effectiveScale, 0.0001) }
    private var usesCompactToolbar: Bool { horizontalSizeClass == .compact }

    /// Translation to visually shift the live drawing surface so it tracks canvas pan.
    private var visualTranslation: CGSize {
        let r = visualRatio
        return CGSize(
            width:  liveOffset.width  - effectiveOffset.width  * r,
            height: liveOffset.height - effectiveOffset.height * r
        )
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            ZStack {

                // ── Hit-test backdrop (draw mode only) ───────────────────────────
                // Prevents accidental taps on canvas elements while we are drawing.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .allowsHitTesting(true)

                // ── Drawing surface ──────────────────────────────────────────────
                FullCanvasDrawView(
                    drawing: $drawing,
                    smartShapeSnappingEnabled: smartShapeSnappingEnabled
                        && navigationSnapshot == nil
                        && redrawShield == nil,
                    selectedColor: $selectedColor,
                    colorRevision: pickedColorRevision,
                    penConfiguration: settings.drawingPenConfiguration,
                    isHighlighterToolSelected: $isHighlighterToolSelected,
                    isDrawingInputActive: $isDrawingInputActive
                ) { committedDrawing in
                    saveAutomatically(committedDrawing)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(visualRatio, anchor: .topLeading)
                .offset(visualTranslation)
                .opacity(navigationSnapshot == nil && redrawShield == nil ? 1 : 0)
                .transaction { transaction in
                    transaction.disablesAnimations = true
                }

                if let navigationSnapshot {
                    Image(uiImage: navigationSnapshot.image)
                        .resizable()
                        .frame(
                            width: navigationSnapshot.sourceRect.width,
                            height: navigationSnapshot.sourceRect.height
                        )
                        .offset(
                            x: navigationSnapshot.sourceRect.minX,
                            y: navigationSnapshot.sourceRect.minY
                        )
                        .scaleEffect(visualRatio, anchor: .topLeading)
                        .offset(visualTranslation)
                        .allowsHitTesting(false)
                        .zIndex(20)
                        .transaction { transaction in
                            transaction.disablesAnimations = true
                        }
                }

                if let redrawShield {
                    Image(uiImage: redrawShield.image)
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                        .zIndex(30)
                }

                // ── Toolbar ──────────────────────────────────────────────────────
                VStack {
                    overlayToolbar
                        .padding(.top, 12)
                        .padding(.horizontal, 16)
                    Spacer()
                }
                .zIndex(100)

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
            .onChange(of: isCanvasNavigationGestureActive) { _, isActive in
                if isActive {
                    navigationSnapshot = makeNavigationSnapshot(viewportSize: geo.size)
                    redrawShield = nil
                    isPickingColor = false
                } else {
                    bakeLiveCanvasTransformIntoDrawing(viewportSize: geo.size)
                }
            }
        }
    }

    // MARK: Toolbar

    private var overlayToolbar: some View {
        HStack(spacing: usesCompactToolbar ? 8 : 12) {

            if savesAutomatically {
                Button { finishAutomaticDrawing() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .bold))
                        Text("Select")
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, usesCompactToolbar ? 12 : 16)
                    .padding(.vertical, 9)
                    .background(Color.orange, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Return to selecting and moving canvas items.")

                Button {
                    isDrawingInputActive.toggle()
                    isPickingColor = false
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isDrawingInputActive ? "hand.draw" : "pencil.tip")
                            .font(.system(size: 13, weight: .semibold))
                        if !usesCompactToolbar {
                            Text(isDrawingInputActive ? "Hand" : "Draw")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .foregroundStyle(isDrawingInputActive ? Color.primary : Color.orange)
                    .padding(.horizontal, usesCompactToolbar ? 10 : 12)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isDrawingInputActive ? "Hand tool" : "Resume drawing")
                .accessibilityHint(
                    isDrawingInputActive
                        ? "Use one finger to move the canvas."
                        : "Resume drawing with the selected Apple drawing tool."
                )
            } else {
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
                }
                .buttonStyle(.plain)
            }

            // Clear
            Button {
                drawing = PKDrawing()
                saveAutomatically(PKDrawing())
            } label: {
                HStack(spacing: 6) {
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
            .disabled(drawing.strokes.isEmpty)
            .opacity(drawing.strokes.isEmpty ? 0.55 : 1)

            DrawingColorPickerButton(
                selectedColor: $selectedColor,
                compact: usesCompactToolbar,
                isActive: isPickingColor
            ) {
                isPickingColor.toggle()
            }

            DrawingAssistanceButton(compact: usesCompactToolbar)

            if showsHandwritingTextGrouping {
                Menu {
                    Picker("Text grouping", selection: $handwritingTextGrouping) {
                        ForEach(HandwritingTextGrouping.allCases) { grouping in
                            Label(grouping.title, systemImage: grouping.icon)
                                .tag(grouping)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: handwritingTextGrouping.icon)
                            .font(.system(size: 13, weight: .semibold))
                        if !usesCompactToolbar {
                            Text(handwritingTextGrouping.shortTitle)
                                .font(.caption.weight(.semibold))
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, usesCompactToolbar ? 10 : 12)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Text grouping: \(handwritingTextGrouping.title)")
            }

            Spacer(minLength: usesCompactToolbar ? 6 : 12)

            if !savesAutomatically {
                Button {
                    isDrawingInputActive = true
                    isActive = false
                    onExit()
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
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Save

    private func saveAndDismiss() {
        isPickingColor = false

        onSave(drawingBakedToLiveCanvas(), liveScale, liveOffset)
        isDrawingInputActive = true
        isActive = false
        onExit()
    }

    private func saveAutomatically(_ sourceDrawing: PKDrawing) {
        guard savesAutomatically else { return }
        onSave(
            drawingBakedToLiveCanvas(sourceDrawing),
            liveScale,
            liveOffset
        )
    }

    private func finishAutomaticDrawing() {
        isPickingColor = false
        saveAutomatically(drawing)
        isDrawingInputActive = true
        isActive = false
        onExit()
    }

    private func bakeLiveCanvasTransformIntoDrawing(viewportSize: CGSize) {
        guard hasLiveCanvasTransformDelta else {
            navigationSnapshot = nil
            return
        }

        redrawShield = makeRedrawShield(viewportSize: viewportSize)
        let bakedDrawing = drawingBakedToLiveCanvas()

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            navigationSnapshot = nil
            drawing = bakedDrawing
            effectiveScale = liveScale
            effectiveOffset = liveOffset
        }

        let shieldID = redrawShield?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard redrawShield?.id == shieldID else { return }
            redrawShield = nil
        }
    }

    private var hasLiveCanvasTransformDelta: Bool {
        abs(visualRatio - 1.0) > 0.0001
        || abs(visualTranslation.width) > 0.5
        || abs(visualTranslation.height) > 0.5
    }

    private func makeNavigationSnapshot(viewportSize: CGSize) -> DrawingNavigationSnapshot? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let ratio = max(visualRatio, 0.0001)
        let visibleSourceRect = CGRect(
            x: -visualTranslation.width / ratio,
            y: -visualTranslation.height / ratio,
            width: viewportSize.width / ratio,
            height: viewportSize.height / ratio
        )
        let sourceRect = visibleSourceRect.insetBy(
            dx: -visibleSourceRect.width * 0.5,
            dy: -visibleSourceRect.height * 0.5
        )
        let image = drawing.image(
            from: sourceRect,
            scale: UIScreen.main.scale * ratio
        )
        return DrawingNavigationSnapshot(image: image, sourceRect: sourceRect)
    }

    private func makeRedrawShield(viewportSize: CGSize) -> RedrawShield? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let ratio = max(visualRatio, 0.0001)
        let sourceRect = CGRect(
            x: -visualTranslation.width / ratio,
            y: -visualTranslation.height / ratio,
            width: viewportSize.width / ratio,
            height: viewportSize.height / ratio
        )
        let image = drawing.image(
            from: sourceRect,
            scale: UIScreen.main.scale * ratio
        )
        return RedrawShield(image: image)
    }

    private func drawingBakedToLiveCanvas(_ sourceDrawing: PKDrawing? = nil) -> PKDrawing {
        let sourceDrawing = sourceDrawing ?? drawing
        let ratio = visualRatio
        let tx = visualTranslation.width
        let ty = visualTranslation.height
        guard hasLiveCanvasTransformDelta else { return sourceDrawing }

        let delta = CGAffineTransform(a: ratio, b: 0, c: 0, d: ratio, tx: tx, ty: ty)
        return sourceDrawing.transformed(using: delta)
    }
}

private struct DrawingNavigationSnapshot: Identifiable {
    let id = UUID()
    let image: UIImage
    let sourceRect: CGRect
}

private struct RedrawShield: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Live PKCanvasView (Draw mode only)

private struct FullCanvasDrawView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let smartShapeSnappingEnabled: Bool
    @Binding var selectedColor: UIColor
    let colorRevision: Int
    let penConfiguration: DrawingPenConfiguration
    @Binding var isHighlighterToolSelected: Bool
    @Binding var isDrawingInputActive: Bool
    let onDrawingCommitted: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            drawing: $drawing,
            selectedColor: $selectedColor,
            penConfiguration: penConfiguration,
            smartShapeSnappingEnabled: smartShapeSnappingEnabled,
            isHighlighterToolSelected: $isHighlighterToolSelected,
            isDrawingInputActive: $isDrawingInputActive,
            onDrawingCommitted: onDrawingCommitted
        )
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas          = PKCanvasView()
        canvas.drawing      = drawing
        canvas.backgroundColor = .clear
        canvas.isOpaque     = false
        // Follow the system Pencil preference shown in PKToolPicker.
        // `.anyInput` overrides "Draw with Finger" and must not be used here.
        canvas.drawingPolicy = .default
        canvas.isScrollEnabled = false
        setDrawingInput(isDrawingInputActive, on: canvas)
        canvas.delegate     = context.coordinator
        context.coordinator.canvasView = canvas
        context.coordinator.rememberCanvasDrawing(drawing)

        let picker = PKToolPicker()
        context.coordinator.toolPicker = picker
        picker.addObserver(canvas)
        picker.addObserver(context.coordinator)
        context.coordinator.rememberPickerSelection(picker)
        context.coordinator.markAppliedColorRevision(colorRevision)
        picker.setVisible(true, forFirstResponder: canvas)
        context.coordinator.syncSelectedColorFromCurrentInkingTool(canvas)
        context.coordinator.updatePenConfiguration(penConfiguration, on: canvas)
        context.coordinator.attachPatternGesture(to: canvas)
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak canvas] in
            guard let canvas else { return }
            coordinator.syncHighlighterToolSelection(from: canvas)
        }
        canvas.becomeFirstResponder()
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.drawingPolicy = .default
        setDrawingInput(isDrawingInputActive, on: canvas)
        context.coordinator.smartShapeSnappingEnabled = smartShapeSnappingEnabled
        context.coordinator.applyExternalDrawingIfNeeded(drawing, to: canvas)
        context.coordinator.applyPickedColorIfNeeded(
            to: canvas,
            selectedColor: selectedColor,
            colorRevision: colorRevision
        )
        context.coordinator.updatePenConfiguration(penConfiguration, on: canvas)
        context.coordinator.onDrawingCommitted = onDrawingCommitted
        // Restore first-responder status only if lost (e.g. after clear).
        if !canvas.isFirstResponder {
            context.coordinator.toolPicker?.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
        }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.cancelPendingCommit()
        coordinator.detachPatternPreview(from: canvas)
        coordinator.toolPicker?.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker?.removeObserver(coordinator)
        coordinator.toolPicker?.removeObserver(canvas)
        canvas.resignFirstResponder()
    }

    private func setDrawingInput(_ isEnabled: Bool, on canvas: PKCanvasView) {
        if #available(iOS 18.0, *) {
            canvas.isDrawingEnabled = isEnabled
        } else {
            canvas.drawingGestureRecognizer.isEnabled = isEnabled
        }
    }

    class Coordinator: NSObject, PKCanvasViewDelegate, PKToolPickerObserver {
        @Binding var drawing: PKDrawing
        @Binding var selectedColor: UIColor
        var penConfiguration: DrawingPenConfiguration
        @Binding var isHighlighterToolSelected: Bool
        @Binding var isDrawingInputActive: Bool
        var onDrawingCommitted: (PKDrawing) -> Void
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
        private var isApplyingExternalDrawing = false
        private var isApplyingStrokeProcessing = false
        private var strokeBaseline: DrawingStrokeBaseline?
        private var currentCanvasDrawingData = Data()
        private var lastCommittedDrawingData = Data()
        private var pendingCommit: DispatchWorkItem?
        private let shapeSnapController = PencilShapeSnapController()
        private let patternPreview = LivePatternStrokePreview()

        init(drawing: Binding<PKDrawing>,
             selectedColor: Binding<UIColor>,
             penConfiguration: DrawingPenConfiguration,
             smartShapeSnappingEnabled: Bool,
             isHighlighterToolSelected: Binding<Bool>,
             isDrawingInputActive: Binding<Bool>,
             onDrawingCommitted: @escaping (PKDrawing) -> Void) {
            self._drawing = drawing
            self._selectedColor = selectedColor
            self.penConfiguration = penConfiguration
            self._isHighlighterToolSelected = isHighlighterToolSelected
            self._isDrawingInputActive = isDrawingInputActive
            self.onDrawingCommitted = onDrawingCommitted
            self.smartShapeSnappingEnabled = smartShapeSnappingEnabled
            self.shapeSnapController.isEnabled = smartShapeSnappingEnabled
        }

        func rememberCanvasDrawing(_ drawing: PKDrawing) {
            currentCanvasDrawingData = drawing.dataRepresentation()
        }

        func applyExternalDrawingIfNeeded(_ drawing: PKDrawing, to canvas: PKCanvasView) {
            let nextData = drawing.dataRepresentation()
            guard nextData != currentCanvasDrawingData else { return }
            isApplyingExternalDrawing = true
            canvas.drawing = drawing
            currentCanvasDrawingData = nextData
            isApplyingExternalDrawing = false
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingExternalDrawing, !isApplyingStrokeProcessing else { return }
            if penConfiguration.usesPattern, patternPreview.isActive {
                cancelPendingCommit()
                shapeSnapController.cancelPendingSnap()
                patternPreview.update(with: canvasView.drawing, on: canvasView)
                return
            }
            let nextData = canvasView.drawing.dataRepresentation()
            guard nextData != currentCanvasDrawingData else { return }
            currentCanvasDrawingData = nextData
            drawing = canvasView.drawing
            scheduleCommit(canvasView.drawing)
            guard !shapeSnapController.isApplyingProgrammaticSnap else { return }
            guard !penConfiguration.usesPattern else {
                shapeSnapController.cancelPendingSnap()
                return
            }
            shapeSnapController.scheduleSnap(on: canvasView) { [weak self] snappedDrawing in
                self?.rememberCanvasDrawing(snappedDrawing)
                self?.drawing = snappedDrawing
            }
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            cancelPendingCommit()
            strokeBaseline = canvasView.tool is PKInkingTool
                ? DrawingStrokeBaseline(drawing: canvasView.drawing)
                : nil
            patternPreview.beginGestureStroke(
                at: canvasView.drawingGestureRecognizer.location(in: canvasView),
                on: canvasView
            )
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            let baseline = strokeBaseline
            strokeBaseline = nil
            if penConfiguration.usesPattern {
                shapeSnapController.cancelPendingSnap()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self, weak canvasView] in
                guard let self, let canvasView else { return }
                let drawingBeforeProcessing = canvasView.drawing
                let drawingForProcessing: PKDrawing
                if self.penConfiguration.usesPattern,
                   let snappedDrawing = self.shapeSnapController
                    .drawingBySnappingLatestStroke(in: drawingBeforeProcessing) {
                    drawingForProcessing = snappedDrawing
                } else {
                    drawingForProcessing = drawingBeforeProcessing
                }

                var finalDrawing = drawingForProcessing
                if let baseline,
                   let processed = DrawingStrokeProcessor.processingLatestStroke(
                       in: drawingForProcessing,
                       since: baseline,
                       configuration: self.penConfiguration,
                       replacementInk: self.patternPreview.replacementInk
                   ) {
                    finalDrawing = processed
                }

                if finalDrawing.dataRepresentation() != drawingBeforeProcessing.dataRepresentation() {
                    self.isApplyingStrokeProcessing = true
                    canvasView.drawing = finalDrawing
                    self.rememberCanvasDrawing(finalDrawing)
                    self.drawing = finalDrawing
                    self.isApplyingStrokeProcessing = false
                }

                DispatchQueue.main.async { [weak self] in
                    self?.patternPreview.clear()
                }
                self.commitDrawing(finalDrawing)
                guard !self.penConfiguration.usesPattern else { return }
                self.shapeSnapController.scheduleSnap(on: canvasView) { [weak self] snappedDrawing in
                    self?.rememberCanvasDrawing(snappedDrawing)
                    self?.drawing = snappedDrawing
                    self?.commitDrawing(snappedDrawing)
                }
            }
        }

        func cancelPendingCommit() {
            pendingCommit?.cancel()
            pendingCommit = nil
        }

        func cancelPendingShapeSnap() {
            shapeSnapController.cancelPendingSnap()
        }

        func updatePenConfiguration(
            _ configuration: DrawingPenConfiguration,
            on canvas: PKCanvasView
        ) {
            penConfiguration = configuration
            patternPreview.synchronize(configuration: configuration, on: canvas)
            if configuration.usesPattern {
                cancelPendingShapeSnap()
            }
        }

        func attachPatternGesture(to canvas: PKCanvasView) {
            canvas.drawingGestureRecognizer.addTarget(
                self,
                action: #selector(handlePatternDrawingGesture(_:))
            )
        }

        func detachPatternPreview(from canvas: PKCanvasView) {
            canvas.drawingGestureRecognizer.removeTarget(
                self,
                action: #selector(handlePatternDrawingGesture(_:))
            )
            patternPreview.detach()
        }

        @objc private func handlePatternDrawingGesture(_ recognizer: UIGestureRecognizer) {
            guard let canvasView else { return }
            let location = recognizer.location(in: canvasView)
            switch recognizer.state {
            case .began:
                patternPreview.beginGestureStroke(at: location, on: canvasView)
            case .changed:
                patternPreview.continueGestureStroke(at: location, on: canvasView)
            case .ended:
                patternPreview.endGestureStroke(cancelled: false)
            case .cancelled, .failed:
                patternPreview.endGestureStroke(cancelled: true)
            case .possible:
                break
            @unknown default:
                patternPreview.endGestureStroke(cancelled: true)
            }
        }

        private func scheduleCommit(_ drawing: PKDrawing) {
            pendingCommit?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.commitDrawing(drawing)
            }
            pendingCommit = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        private func commitDrawing(_ drawing: PKDrawing) {
            cancelPendingCommit()
            let data = drawing.dataRepresentation()
            guard data != lastCommittedDrawingData else { return }
            lastCommittedDrawingData = data
            onDrawingCommitted(drawing)
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

        func syncHighlighterToolSelection(from canvas: PKCanvasView) {
            if currentInkingTool(for: canvas)?.inkType == .marker {
                isHighlighterToolSelected = true
            }
        }

        func rememberPickerSelection(_ toolPicker: PKToolPicker) {
            _ = updatePickerSelectionState(toolPicker)
        }

        private func handleToolPickerChange(_ toolPicker: PKToolPicker) {
            _ = updatePickerSelectionState(toolPicker)
            isDrawingInputActive = true
            let selectedInkingTool = pickerInkingTool(from: toolPicker)
            if selectedInkingTool == nil {
                shapeSnapController.cancelPendingSnap()
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, let canvas = self.canvasView else { return }

                if let selectedInkingTool {
                    let toolColor = selectedInkingTool.color.withAlphaComponent(1)
                    if !self.selectedColor.isDrawingEquivalent(to: toolColor) {
                        self.selectedColor = toolColor
                    }
                } else {
                    self.syncSelectedColorFromCurrentInkingTool(canvas)
                }
                if let selectedInkingTool {
                    self.isHighlighterToolSelected = selectedInkingTool.inkType == .marker
                }
                self.patternPreview.selectedInkingToolDidChange(
                    selectedInkingTool,
                    on: canvas
                )
            }
        }

        private func applyColor(_ selectedColor: UIColor,
                                to canvas: PKCanvasView,
                                switchToPenIfNeeded: Bool) {
            guard !isApplyingPickedColor else { return }

            let color = selectedColor.withAlphaComponent(1)
            let nextTool: PKInkingTool

            if let inkingTool = canvas.tool as? PKInkingTool {
                let alpha = patternPreview.visibleInkAlpha
                    ?? inkingTool.color.cgColor.alpha
                nextTool = PKInkingTool(
                    inkingTool.inkType,
                    color: color.withAlphaComponent(alpha),
                    width: inkingTool.width
                )
            } else if let pickerTool = pickerInkingTool(from: toolPicker) {
                nextTool = PKInkingTool(
                    pickerTool.inkType,
                    color: color.withAlphaComponent(pickerTool.color.cgColor.alpha),
                    width: pickerTool.width
                )
            } else if switchToPenIfNeeded {
                nextTool = PKInkingTool(.pen, color: color, width: 5)
            } else {
                return
            }

            isApplyingPickedColor = true
            canvas.tool = nextTool
            isApplyingPickedColor = false
            patternPreview.selectedInkingToolDidChange(nextTool, on: canvas)
            if nextTool.inkType == .marker {
                isHighlighterToolSelected = true
            }
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

            MacDrawingEditor(drawing: drawing, canvasScale: 1) { newDrawing in
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
