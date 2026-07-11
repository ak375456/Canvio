import SwiftUI
import SwiftData
import PencilKit

struct PDFPageElementView: View {
    @Environment(\.modelContext) private var context
    @Bindable var element: PDFPageElementModel
    let source: PDFElementModel?
    let highlights: [PDFHighlightModel]
    let inkLayer: PDFInkLayerModel?
    let canvasScale: CGFloat
    let canvasOffset: CGSize
    let canvasBoundary: CGSize
    @ObservedObject var vm: PDFPageElementViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect = false
    var onOpenReader: (() -> Void)?
    var onRecrop: (() -> Void)?
    var onExternalTap: (() -> Void)?
    var isCanvasGestureActive = false

    @State private var image: PlatformImage?
    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero
    @State private var rotationAngle = 0.0
    @State private var rotationGestureState = CanvasElementRotationState()

    private var isSelected: Bool { vm.editingID == element.id }
    private var currentWidth: CGFloat { max(120, element.width + resizeDelta.width) }
    private var currentHeight: CGFloat { max(90, element.height + resizeDelta.height) }

    var body: some View {
        ZStack {
            pageBody
            selectionRing
            if isSelected && !isMultiSelectMode {
                toolbar
                    .offset(y: -(currentHeight / 2) - 30)
                    .rotationEffect(.degrees(-rotationAngle))
                handle(icon: "trash", color: .red)
                    .offset(x: -currentWidth / 2, y: -currentHeight / 2)
                    .onTapGesture { vm.delete(element: element, context: context) }
                handle(icon: "arrow.trianglehead.2.clockwise", color: .orange)
                    .offset(x: -currentWidth / 2, y: currentHeight / 2)
                    .gesture(rotateGesture)
                handle(icon: "arrow.up.left.and.arrow.down.right", color: .green)
                    .offset(x: currentWidth / 2, y: currentHeight / 2)
                    .gesture(resizeGesture)
            }
        }
        .frame(width: currentWidth, height: currentHeight)
        .rotationEffect(.degrees(rotationAngle))
        .position(x: element.x + dragOffset.width, y: element.y + dragOffset.height)
        .gesture(canMove ? moveGesture : nil)
        .onAppear {
            rotationAngle = element.rotation
            loadPage()
        }
        .onChange(of: element.pageIndex) { _, _ in loadPage() }
        .onChange(of: element.cropX) { _, _ in loadPage() }
        .onChange(of: element.cropY) { _, _ in loadPage() }
        .onChange(of: element.cropWidth) { _, _ in loadPage() }
        .onChange(of: element.cropHeight) { _, _ in loadPage() }
        .onReceive(NotificationCenter.default.publisher(for: .pdfFileDidBecomeAvailable)) { note in
            guard let fileName = note.object as? String,
                  fileName == element.pdfFileName else { return }
            loadPage()
        }
    }

    private var pageBody: some View {
        ZStack {
            Color.white
            if let image {
                #if canImport(UIKit)
                Image(uiImage: image).resizable().scaledToFill()
                #else
                Image(nsImage: image).resizable().scaledToFill()
                #endif
            } else {
                ProgressView().tint(.gray)
            }
            if element.showsAnnotations {
                highlightOverlay
                inkOverlay
            }
        }
        .frame(width: currentWidth, height: currentHeight)
        .clipped()
        .background(.white)
        .overlay(Rectangle().strokeBorder(
            isSelected && !isMultiSelectMode ? Color.accentColor : Color.black.opacity(0.14),
            lineWidth: isSelected && !isMultiSelectMode ? 2 : 1
        ))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isMultiSelectMode, !isCanvasGestureActive else { return }
            if isSelected { onOpenReader?() }
            else { onExternalTap?(); vm.editingID = element.id }
        }
    }

    private var highlightOverlay: some View {
        GeometryReader { geo in
            ForEach(highlights) { highlight in
                ForEach(highlight.rects) { rect in
                    if let visible = intersection(rect, with: element.cropRect) {
                        Rectangle()
                            .fill(Color(pdfHex: highlight.colorHex).opacity(highlight.opacity))
                            .frame(
                                width: visible.width / element.cropWidth * geo.size.width,
                                height: visible.height / element.cropHeight * geo.size.height
                            )
                            .position(
                                x: (visible.x - element.cropX + visible.width / 2) / element.cropWidth * geo.size.width,
                                y: (element.cropY + element.cropHeight - visible.y - visible.height / 2)
                                    / element.cropHeight * geo.size.height
                            )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var inkOverlay: some View {
        if let inkLayer, !inkLayer.drawingData.isEmpty {
            let width = max(1, inkLayer.coordinateWidth)
            let height = max(1, inkLayer.coordinateHeight)
            let crop = CGRect(
                x: element.cropX * width,
                y: (1 - element.cropY - element.cropHeight) * height,
                width: element.cropWidth * width,
                height: element.cropHeight * height
            )
            let rendered = inkLayer.pkDrawing.image(from: crop, scale: 2)
            #if canImport(UIKit)
            Image(uiImage: rendered).resizable().scaledToFill().allowsHitTesting(false)
            #else
            Image(nsImage: rendered).resizable().scaledToFill().allowsHitTesting(false)
            #endif
        }
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isMultiSelectMode {
            Rectangle().strokeBorder(isSelectedInMultiSelect ? Color.blue : Color.white.opacity(0.4),
                                     lineWidth: isSelectedInMultiSelect ? 3 : 1)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Button { onOpenReader?() } label: { Label("Read", systemImage: "book") }
            Divider().frame(height: 18)
            Button { onRecrop?() } label: { Label("Crop", systemImage: "crop") }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }

    private var canMove: Bool { isSelected && !isMultiSelectMode && !isCanvasGestureActive }

    private var moveGesture: some Gesture {
        DragGesture().onChanged { dragOffset = $0.translation }.onEnded { value in
            dragOffset = .zero
            vm.updatePosition(element: element, translation: value.translation,
                              boundary: canvasBoundary, context: context)
        }
    }

    private var resizeGesture: some Gesture {
        DragGesture().onChanged { resizeDelta = $0.translation }.onEnded { value in
            resizeDelta = .zero
            vm.updateSize(element: element,
                          width: element.width + value.translation.width,
                          height: element.height + value.translation.height,
                          context: context)
        }
    }

    private var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasViewportCoordinateSpace)).onChanged { value in
            rotationAngle = rotationGestureState.update(
                pointer: value.location,
                center: rotationCenter,
                currentRotation: rotationAngle
            )
        }.onEnded { _ in
            rotationGestureState.reset()
            vm.updateRotation(element: element, rotation: rotationAngle, context: context)
        }
    }

    private var rotationCenter: CGPoint {
        CGPoint(x: element.x * canvasScale + canvasOffset.width,
                y: element.y * canvasScale + canvasOffset.height)
    }

    private func handle(icon: String, color: Color) -> some View {
        Circle().fill(color).frame(width: 28, height: 28)
            .overlay(Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
    }

    private func loadPage() {
        let file = source?.pdfFileName ?? element.pdfFileName
        guard !file.isEmpty else { image = nil; return }
        let page = element.pageIndex
        let crop = element.cropRect
        Task {
            image = PDFPageRenderingService.render(
                fileName: file,
                pageIndex: page,
                crop: crop
            )
        }
    }

    private func intersection(_ lhs: PDFNormalizedRect,
                              with rhs: PDFNormalizedRect) -> PDFNormalizedRect? {
        let rect = lhs.cgRect.intersection(rhs.cgRect)
        guard !rect.isNull, !rect.isEmpty else { return nil }
        return PDFNormalizedRect(rect)
    }
}

extension Notification.Name {
    static let pdfFileDidBecomeAvailable = Notification.Name("pdfFileDidBecomeAvailable")
}

private extension Color {
    init(pdfHex: String) {
        let value = pdfHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)
        let red = Double((number >> 16) & 0xff) / 255
        let green = Double((number >> 8) & 0xff) / 255
        let blue = Double(number & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
