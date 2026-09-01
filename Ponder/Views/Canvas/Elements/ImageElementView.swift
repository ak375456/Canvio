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
    let canvasOffset: CGSize
    let canvasBoundary: CGSize
    @ObservedObject var vm: ImageElementViewModel
    let isMultiSelectMode: Bool
    let ocrTextZIndex: Int
    let undoManager: CanvasUndoManager?
    var isSelectedInMultiSelect: Bool = false
    var onExternalTap: (() -> Void)? = nil
    var isCanvasGestureActive: Bool = false
    var smartDragAdjustment = CanvasSmartDragAdjustment()

    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero
    @State private var rotationAngle: Double = 0
    @State private var rotationGestureState = CanvasElementRotationState()
    @State private var hasLoadedRotation = false
    /// Downsampled display image, generated once on a background thread.
    @State private var displayImage: PlatformImage? = nil
    @State private var lastLoadedFileName: String = ""
    @State private var showOpacityControls = false
    @State private var showCutoutEditor = false
    @State private var isExtractingText = false
    @State private var ocrAlertMessage: String?

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
                Button {
                    vm.delete(element: element, context: context, undoManager: undoManager)
                } label: { handleCircle(icon: "trash", color: .red) }
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
        .gesture(canMove ? moveDragGesture : nil)
        .onAppear {
            if !hasLoadedRotation { rotationAngle = element.rotation; hasLoadedRotation = true }
            loadDisplayImageIfNeeded()
        }
        .onChange(of: element.imageFileName) { _, _ in loadDisplayImageIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .imageFileDidBecomeAvailable)) { notification in
            guard let fileName = notification.object as? String,
                  fileName == element.imageFileName else { return }
            lastLoadedFileName = ""
            loadDisplayImageIfNeeded()
        }
        .alert("Text Extraction", isPresented: Binding(
            get: { ocrAlertMessage != nil },
            set: { if !$0 { ocrAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { ocrAlertMessage = nil }
        } message: {
            Text(ocrAlertMessage ?? "")
        }
        .sheet(isPresented: $showCutoutEditor) {
            ImageFreeformCutoutEditor(
                element: element,
                vm: vm,
                undoManager: undoManager
            )
        }
    }

    // MARK: - Thumbnail loading

    /// Loads a display-sized thumbnail on a background thread.
    /// Uses ImageIO's kCGImageSourceThumbnailMaxPixelSize so JPEG is only
    /// partially decoded — much faster than loading the full bitmap.
    private func loadDisplayImageIfNeeded() {
        let fileName = element.imageFileName
        guard fileName != lastLoadedFileName else { return }
        lastLoadedFileName = fileName

        // Render at 2× the on-canvas display size so it looks sharp when zoomed.
        let targetPixels = max(currentWidth, currentHeight) * 2

        Task.detached(priority: .userInitiated) {
            let image = ImageStorageService.thumbnail(
                fileName: fileName,
                maxPixelSize: targetPixels
            )
            await MainActor.run { displayImage = image }
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
            if let img = displayImage ?? ImageStorageService.load(fileName: element.imageFileName) {
                #if canImport(UIKit)
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
                #else
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
                #endif
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: element.cornerRadius).fill(Color.secondary.opacity(0.12))
                    Image(systemName: "photo").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: currentWidth, height: currentHeight)
        .modifier(ImageElementClipModifier(cornerRadius: element.cornerRadius))
        .opacity(element.opacity)
        .drawingGroup()   // rasterise to a GPU texture — eliminates per-frame CPU compositing
        .overlay(RoundedRectangle(cornerRadius: element.cornerRadius)
            .strokeBorder(isSelected && !isMultiSelectMode ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture {
            if !isMultiSelectMode && !isSelected && !isCanvasGestureActive {
                onExternalTap?()
                vm.editingID = element.id
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach([0.0, 4.0, 8.0, 12.0, 16.0, 24.0], id: \.self) { r in
                    Button {
                        vm.updateCornerRadius(
                            element: element,
                            cornerRadius: r,
                            context: context,
                            undoManager: undoManager
                        )
                    } label: {
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
            Button {
                showCutoutEditor = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "scissors")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Cutout")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.primary.opacity(0.75))
                .padding(.horizontal, 6)
                .frame(height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Freeform image cutout")
            Divider().frame(height: 18)
            Button {
                showOpacityControls = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "circle.lefthalf.filled").font(.system(size: 12, weight: .semibold))
                    Text("\(Int(element.opacity * 100))%").font(.caption.weight(.semibold))
                }.foregroundStyle(Color.primary.opacity(0.7)).padding(.horizontal, 6).frame(height: 26)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showOpacityControls, arrowEdge: .top) {
                opacityControls
            }
            Divider().frame(height: 18)
            Button {
                extractText()
            } label: {
                HStack(spacing: 4) {
                    if isExtractingText {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text("OCR").font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.primary.opacity(0.75))
                .padding(.horizontal, 6)
                .frame(height: 26)
            }
            .buttonStyle(.plain)
            .disabled(isExtractingText)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }

    private func extractText() {
        guard !isExtractingText else { return }
        isExtractingText = true

        Task {
            do {
                let text = try await ImageOCRService.recognizeText(fileName: element.imageFileName)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    ocrAlertMessage = "No readable text was found in this image."
                    isExtractingText = false
                    return
                }

                if let textID = vm.createTextElementFromOCR(
                    image: element,
                    text: trimmed,
                    zIndex: ocrTextZIndex,
                    context: context,
                    undoManager: undoManager
                ) {
                    onExternalTap?()
                    vm.editingID = nil
                    isExtractingText = false
                    NotificationCenter.default.post(
                        name: .ocrCreatedTextElement,
                        object: textID
                    )
                } else {
                    ocrAlertMessage = "No readable text was found in this image."
                    isExtractingText = false
                }
            } catch {
                ocrAlertMessage = "Could not read text from this image."
                isExtractingText = false
            }
        }
    }

    private var opacityControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Opacity", systemImage: "circle.lefthalf.filled")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(element.opacity * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { element.opacity },
                    set: {
                        vm.updateOpacity(
                            element: element,
                            opacity: $0,
                            context: context,
                            undoManager: undoManager
                        )
                    }
                ),
                in: 0.1...1.0,
                step: 0.05
            )

            HStack(spacing: 8) {
                ForEach([1.0, 0.75, 0.5, 0.25, 0.1], id: \.self) { value in
                    Button {
                        vm.updateOpacity(
                            element: element,
                            opacity: value,
                            context: context,
                            undoManager: undoManager
                        )
                    } label: {
                        Text("\(Int(value * 100))")
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: 34)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasViewportCoordinateSpace))
            .onChanged { value in
                rotationAngle = rotationGestureState.update(
                    pointer: value.location,
                    center: rotationCenter,
                    currentRotation: rotationAngle
                )
            }
            .onEnded { _ in
                rotationGestureState.reset()
                let oldRotation = element.rotation
                element.rotation = rotationAngle; element.updatedAt = Date(); try? context.save()
                Task { await ImageSyncService.shared.upsert(element) }
                undoManager?.recordElementChange(
                    name: "Rotate image",
                    element: element,
                    from: oldRotation,
                    to: element.rotation,
                    context: context
                ) { $0.rotation = $1 }
            }
    }

    private var rotationCenter: CGPoint {
        CGPoint(x: element.x * canvasScale + canvasOffset.width,
                y: element.y * canvasScale + canvasOffset.height)
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
                vm.updateSize(
                    element: element,
                    width: element.width + delta.width,
                    height: element.height + delta.height,
                    context: context,
                    undoManager: undoManager
                )
            }
    }

    private var moveDragGesture: some Gesture {
        DragGesture()
            .onChanged {
                guard canMove else {
                    dragOffset = .zero
                    smartDragAdjustment.cancelled()
                    return
                }
                dragOffset = smartDragAdjustment.changed($0.translation)
            }
            .onEnded { _ in
                guard canMove else {
                    dragOffset = .zero
                    smartDragAdjustment.cancelled()
                    return
                }
                let t = smartDragAdjustment.ended(dragOffset)
                dragOffset = .zero
                vm.updatePosition(
                    element: element,
                    translation: t,
                    scale: canvasScale,
                    boundary: canvasBoundary,
                    context: context,
                    undoManager: undoManager
                )
            }
    }

    private var canMove: Bool {
        isSelected && !isMultiSelectMode && !isCanvasGestureActive
    }

    private func handleCircle(icon: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color).frame(width: handleSize, height: handleSize)
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        }
    }
}

private struct ImageElementClipModifier: ViewModifier {
    let cornerRadius: Double

    func body(content: Content) -> some View {
        if cornerRadius > 0 {
            content.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content.clipped()
        }
    }
}

extension Notification.Name {
    static let ocrCreatedTextElement = Notification.Name("ocrCreatedTextElement")
    static let imageFileDidBecomeAvailable = Notification.Name("imageFileDidBecomeAvailable")
}
