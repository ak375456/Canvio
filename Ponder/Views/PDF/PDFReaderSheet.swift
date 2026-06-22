import SwiftUI
import SwiftData
import PDFKit
import PencilKit

enum PDFReaderDisplayMode: String, CaseIterable, Identifiable {
    case paged
    case continuous
    case book

    var id: String { rawValue }
    var title: String {
        switch self {
        case .paged: "Page"
        case .continuous: "Scroll"
        case .book: "Book"
        }
    }
    var icon: String {
        switch self {
        case .paged: "rectangle.portrait"
        case .continuous: "rectangle.split.1x2"
        case .book: "book.pages"
        }
    }
}

private enum PDFWorkspaceTool: String {
    case read
    case ink
    case crop
}

struct PDFWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var element: PDFElementModel
    let canvasID: UUID
    var initialPageIndex: Int = 0
    let onExtract: (PDFSelectionPayload) -> Void
    let onPlacePages: ([PDFPagePlacementRequest]) -> Void

    @Query private var allHighlights: [PDFHighlightModel]
    @Query private var allInkLayers: [PDFInkLayerModel]
    @Query private var allReadingStates: [PDFReadingStateModel]

    @State private var document: PDFDocument?
    @State private var currentPageIndex = 0
    @State private var displayMode: PDFReaderDisplayMode = .paged
    @State private var tool: PDFWorkspaceTool = .read
    @State private var selection: PDFSelectionPayload?
    @State private var selectedPages = Set<Int>()
    @State private var sidebarVisible = true
    @State private var toastMessage: String?
    @State private var inkSyncTask: Task<Void, Never>?

    private var highlights: [PDFHighlightModel] {
        allHighlights.filter {
            $0.documentID == element.resolvedDocumentID && $0.canvasID == canvasID
        }
    }

    private var inkLayers: [PDFInkLayerModel] {
        allInkLayers.filter {
            $0.documentID == element.resolvedDocumentID && $0.canvasID == canvasID
        }
    }

    var body: some View {
        ZStack {
            Color(pdfWorkspaceBackground: true).ignoresSafeArea()
            if let document {
                workspace(document)
            } else {
                unavailableState
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls }
        .overlay(alignment: .top) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear { prepareWorkspace() }
        .onChange(of: currentPageIndex) { _, _ in persistReadingState() }
        .onChange(of: displayMode) { _, _ in persistReadingState() }
        .onChange(of: sidebarVisible) { _, _ in persistReadingState() }
        .onDisappear {
            inkSyncTask?.cancel()
            persistReadingState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pdfFileDidBecomeAvailable)) { note in
            guard let fileName = note.object as? String,
                  fileName == element.pdfFileName else { return }
            document = PDFStorageService.loadPDF(fileName: fileName)
        }
    }

    private func workspace(_ document: PDFDocument) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if sidebarVisible && geo.size.width >= 700 {
                    pageSidebar(document)
                        .frame(width: min(220, geo.size.width * 0.24))
                    Divider()
                }
                Group {
                    switch tool {
                    case .read:
                        InteractivePDFView(
                            document: document,
                            displayMode: displayMode,
                            currentPageIndex: $currentPageIndex,
                            selection: $selection,
                            highlights: highlights,
                            inkLayers: inkLayers
                        )
                    case .ink:
                        PDFInkEditor(
                            document: document,
                            pageIndex: $currentPageIndex,
                            drawing: inkLayer(for: currentPageIndex)?.pkDrawing ?? PKDrawing(),
                            onChange: saveInk
                        )
                    case .crop:
                        PDFCropEditor(
                            document: document,
                            pageIndex: $currentPageIndex,
                            initialCrop: .fullPage
                        ) { crop in
                            onPlacePages([PDFPagePlacementRequest(
                                pageIndex: currentPageIndex,
                                cropRect: crop
                            )])
                            showToast("Crop placed on canvas")
                            tool = .read
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(element.originalName.isEmpty ? "Document" : element.originalName)
                    .font(.headline).lineLimit(1)
                Text("Page \(currentPageIndex + 1) of \(max(1, element.pageCount))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button { withAnimation(.snappy) { sidebarVisible.toggle() } } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Toggle page thumbnails")

            Menu {
                Picker("Reading layout", selection: $displayMode) {
                    ForEach(PDFReaderDisplayMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon).tag(mode)
                    }
                }
            } label: {
                Label(displayMode.title, systemImage: displayMode.icon)
            }
            .buttonStyle(.bordered)
            .disabled(tool != .read)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 8) {
            if let selection, tool == .read {
                HStack(spacing: 8) {
                    Button {
                        onExtract(selection)
                        self.selection = nil
                        showToast("Text card added to canvas")
                    } label: {
                        Label("Extract", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        createHighlights(from: selection)
                        self.selection = nil
                        showToast("Highlight saved")
                    } label: {
                        Label("Highlight", systemImage: "highlighter")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(8)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
            }

            HStack(spacing: 6) {
                toolButton(.read, title: "Read", icon: "book")
                toolButton(.ink, title: "Pencil", icon: "pencil.tip.crop.circle")
                toolButton(.crop, title: "Crop", icon: "crop")

                Divider().frame(height: 24).padding(.horizontal, 3)

                Button {
                    onPlacePages([PDFPagePlacementRequest(pageIndex: currentPageIndex)])
                    showToast("Page \(currentPageIndex + 1) placed on canvas")
                } label: {
                    Label("Place Page", systemImage: "rectangle.on.rectangle.angled")
                }
                .buttonStyle(.bordered)

                if !selectedPages.isEmpty {
                    Button {
                        let requests = selectedPages.sorted().map {
                            PDFPagePlacementRequest(pageIndex: $0)
                        }
                        onPlacePages(requests)
                        showToast("\(requests.count) pages placed on canvas")
                        selectedPages.removeAll()
                    } label: {
                        Label("Place \(selectedPages.count)", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func toolButton(_ value: PDFWorkspaceTool, title: String, icon: String) -> some View {
        Button {
            selection = nil
            withAnimation(.snappy) { tool = value }
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .tint(value == tool ? Color.accentColor : Color.secondary)
    }

    private func pageSidebar(_ document: PDFDocument) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("PAGES").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
                if !selectedPages.isEmpty {
                    Button("Clear") { selectedPages.removeAll() }.font(.caption)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(0..<document.pageCount, id: \.self) { index in
                            HStack(alignment: .top, spacing: 8) {
                                PDFPageThumbnail(fileName: element.pdfFileName, pageIndex: index)
                                    .frame(width: 120, height: 156)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .strokeBorder(index == currentPageIndex ? Color.accentColor : .clear,
                                                          lineWidth: 3)
                                    )
                                    .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                                    .onTapGesture { tool = .read; currentPageIndex = index }

                                Button {
                                    if selectedPages.contains(index) { selectedPages.remove(index) }
                                    else { selectedPages.insert(index) }
                                } label: {
                                    Image(systemName: selectedPages.contains(index)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedPages.contains(index) ? .blue : .secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Select page \(index + 1) for canvas")
                            }
                            .id(index)
                            .overlay(alignment: .bottomLeading) {
                                Text("\(index + 1)")
                                    .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                                    .offset(y: 13)
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.bottom, 28)
                }
                .onChange(of: currentPageIndex) { _, page in
                    withAnimation { proxy.scrollTo(page, anchor: .center) }
                }
            }
        }
        .background(Color.primary.opacity(0.035))
    }

    private var unavailableState: some View {
        ContentUnavailableView(
            "PDF not available",
            systemImage: "doc.richtext.fill",
            description: Text("The source file may still be downloading.")
        )
    }

    private func prepareWorkspace() {
        document = PDFStorageService.loadPDF(fileName: element.pdfFileName)
        currentPageIndex = min(max(0, initialPageIndex), max(0, element.pageCount - 1))
        #if os(iOS)
        sidebarVisible = UIDevice.current.userInterfaceIdiom == .pad
        displayMode = UIDevice.current.userInterfaceIdiom == .pad ? .book : .paged
        #else
        sidebarVisible = true
        displayMode = .continuous
        #endif

        if let state = allReadingStates.first(where: { $0.documentID == element.resolvedDocumentID }) {
            currentPageIndex = min(max(0, state.currentPageIndex), max(0, element.pageCount - 1))
            displayMode = PDFReaderDisplayMode(rawValue: state.displayModeRaw) ?? displayMode
            sidebarVisible = state.sidebarVisible
        }
    }

    private func persistReadingState() {
        let state: PDFReadingStateModel
        if let existing = allReadingStates.first(where: { $0.documentID == element.resolvedDocumentID }) {
            state = existing
        } else {
            state = PDFReadingStateModel(documentID: element.resolvedDocumentID)
            context.insert(state)
        }
        state.currentPageIndex = currentPageIndex
        state.displayModeRaw = displayMode.rawValue
        state.sidebarVisible = sidebarVisible
        state.lastOpenedAt = Date()
        state.updatedAt = Date()
        try? context.save()
        Task { await PDFWorkspaceSyncService.shared.upsert(state) }
    }

    private func createHighlights(from payload: PDFSelectionPayload) {
        for page in payload.pages where !page.rects.isEmpty {
            let highlight = PDFHighlightModel(
                documentID: element.resolvedDocumentID,
                canvasID: canvasID,
                pageIndex: page.pageIndex,
                selectedText: payload.text,
                rects: page.rects
            )
            context.insert(highlight)
            Task { await PDFWorkspaceSyncService.shared.upsert(highlight) }
        }
        try? context.save()
    }

    private func inkLayer(for pageIndex: Int) -> PDFInkLayerModel? {
        inkLayers.first { $0.pageIndex == pageIndex }
    }

    private func saveInk(_ drawing: PKDrawing, coordinateSize: CGSize) {
        let layer: PDFInkLayerModel
        if let existing = inkLayer(for: currentPageIndex) {
            layer = existing
            layer.pkDrawing = drawing
            layer.coordinateWidth = max(1, coordinateSize.width)
            layer.coordinateHeight = max(1, coordinateSize.height)
            layer.updatedAt = Date()
        } else {
            layer = PDFInkLayerModel(
                documentID: element.resolvedDocumentID,
                canvasID: canvasID,
                pageIndex: currentPageIndex,
                drawing: drawing,
                coordinateSize: coordinateSize
            )
            context.insert(layer)
        }
        try? context.save()
        inkSyncTask?.cancel()
        inkSyncTask = Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            await PDFWorkspaceSyncService.shared.upsert(layer)
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.snappy) { toastMessage = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) { if toastMessage == text { toastMessage = nil } }
        }
    }
}

// MARK: - PDFKit reader and text selection

#if canImport(UIKit)
private struct InteractivePDFView: UIViewRepresentable {
    let document: PDFDocument
    let displayMode: PDFReaderDisplayMode
    @Binding var currentPageIndex: Int
    @Binding var selection: PDFSelectionPayload?
    let highlights: [PDFHighlightModel]
    let inkLayers: [PDFInkLayerModel]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.pageBreakMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        view.backgroundColor = UIColor.secondarySystemBackground
        context.coordinator.observe(view)
        context.coordinator.configure(view, mode: displayMode)
        context.coordinator.applyAnnotations(highlights: highlights, inkLayers: inkLayers,
                                             to: document)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configure(view, mode: displayMode)
        context.coordinator.applyAnnotations(highlights: highlights, inkLayers: inkLayers,
                                             to: document)
        if let page = document.page(at: currentPageIndex), view.currentPage !== page {
            view.go(to: page)
        }
    }

    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class Coordinator: NSObject {
        var parent: InteractivePDFView
        private var selectionObserver: NSObjectProtocol?
        private var pageObserver: NSObjectProtocol?
        private var configuredMode: PDFReaderDisplayMode?
        private var annotationSignature = ""

        init(_ parent: InteractivePDFView) { self.parent = parent }

        func observe(_ view: PDFView) {
            selectionObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewSelectionChanged, object: view, queue: .main
            ) { [weak self, weak view] _ in
                guard let self, let view else { return }
                self.parent.selection = self.payload(from: view.currentSelection,
                                                     document: self.parent.document)
            }
            pageObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged, object: view, queue: .main
            ) { [weak self, weak view] _ in
                guard let self, let view, let page = view.currentPage else { return }
                self.parent.currentPageIndex = self.parent.document.index(for: page)
            }
        }

        func stopObserving() {
            if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
            if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) }
        }

        func configure(_ view: PDFView, mode: PDFReaderDisplayMode) {
            guard configuredMode != mode else { return }
            configuredMode = mode
            switch mode {
            case .paged:
                view.usePageViewController(true, withViewOptions: [
                    UIPageViewController.OptionsKey.interPageSpacing: 18
                ])
                view.displayMode = .singlePage
                view.displayDirection = .horizontal
                view.displaysAsBook = false
            case .continuous:
                view.usePageViewController(false, withViewOptions: nil)
                view.displayMode = .singlePageContinuous
                view.displayDirection = .vertical
                view.displaysAsBook = false
            case .book:
                view.usePageViewController(true, withViewOptions: [
                    UIPageViewController.OptionsKey.interPageSpacing: 18
                ])
                view.displayMode = .twoUp
                view.displayDirection = .horizontal
                view.displaysAsBook = true
            }
            view.autoScales = true
        }

        func applyAnnotations(highlights: [PDFHighlightModel],
                              inkLayers: [PDFInkLayerModel],
                              to document: PDFDocument) {
            let signature = highlights.map { "h\($0.id)-\($0.updatedAt.timeIntervalSince1970)" }.joined()
                + inkLayers.map { "i\($0.id)-\($0.updatedAt.timeIntervalSince1970)" }.joined()
            guard signature != annotationSignature else { return }
            annotationSignature = signature
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                for annotation in page.annotations where
                    annotation.userName == "CanvioOverlay"
                    || annotation.userName == "CanvioInkOverlay" {
                    page.removeAnnotation(annotation)
                }
            }
            for highlight in highlights {
                guard let page = document.page(at: highlight.pageIndex) else { continue }
                let bounds = page.bounds(for: .cropBox)
                for rect in highlight.rects {
                    let pageRect = CGRect(
                        x: bounds.minX + bounds.width * rect.cgRect.minX,
                        y: bounds.minY + bounds.height * rect.cgRect.minY,
                        width: bounds.width * rect.cgRect.width,
                        height: bounds.height * rect.cgRect.height
                    )
                    let annotation = PDFAnnotation(bounds: pageRect, forType: .highlight,
                                                   withProperties: nil)
                    annotation.color = UIColor(pdfHex: highlight.colorHex)
                        .withAlphaComponent(highlight.opacity)
                    annotation.userName = "CanvioOverlay"
                    page.addAnnotation(annotation)
                }
            }

            for layer in inkLayers where !layer.drawingData.isEmpty {
                guard let page = document.page(at: layer.pageIndex) else { continue }
                let pageBounds = page.bounds(for: .cropBox)
                let coordinateWidth = max(1, layer.coordinateWidth)
                let coordinateHeight = max(1, layer.coordinateHeight)
                for stroke in layer.pkDrawing.strokes {
                    let path = UIBezierPath()
                    for (index, point) in stroke.path.enumerated() {
                        let location = point.location
                        let converted = CGPoint(
                            x: (Double(location.x) / coordinateWidth) * pageBounds.width,
                            y: (1 - Double(location.y) / coordinateHeight) * pageBounds.height
                        )
                        if index == 0 { path.move(to: converted) }
                        else { path.addLine(to: converted) }
                    }
                    guard !path.isEmpty else { continue }
                    let annotation = PDFAnnotation(bounds: pageBounds, forType: .ink,
                                                   withProperties: nil)
                    annotation.add(path)
                    annotation.color = stroke.ink.color
                    let border = PDFBorder()
                    let sourceWidth = stroke.path.first?.size.width ?? 2
                    border.lineWidth = max(1,
                        sourceWidth / coordinateWidth * Double(pageBounds.width))
                    annotation.border = border
                    annotation.userName = "CanvioInkOverlay"
                    page.addAnnotation(annotation)
                }
            }
        }

        private func payload(from selection: PDFSelection?,
                             document: PDFDocument) -> PDFSelectionPayload? {
            guard let selection,
                  let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            var grouped: [Int: [PDFNormalizedRect]] = [:]
            for line in selection.selectionsByLine() {
                guard let page = line.pages.first else { continue }
                let pageIndex = document.index(for: page)
                guard pageIndex >= 0 else { continue }
                let pageBounds = page.bounds(for: .cropBox)
                let rect = line.bounds(for: page)
                guard pageBounds.width > 0, pageBounds.height > 0, !rect.isEmpty else { continue }
                grouped[pageIndex, default: []].append(PDFNormalizedRect(
                    x: Double((rect.minX - pageBounds.minX) / pageBounds.width),
                    y: Double((rect.minY - pageBounds.minY) / pageBounds.height),
                    width: Double(rect.width / pageBounds.width),
                    height: Double(rect.height / pageBounds.height)
                ))
            }
            return PDFSelectionPayload(
                text: text,
                pages: grouped.keys.sorted().map {
                    PDFSelectionPagePayload(pageIndex: $0, rects: grouped[$0] ?? [])
                }
            )
        }
    }
}
#else
private struct InteractivePDFView: NSViewRepresentable {
    let document: PDFDocument
    let displayMode: PDFReaderDisplayMode
    @Binding var currentPageIndex: Int
    @Binding var selection: PDFSelectionPayload?
    let highlights: [PDFHighlightModel]
    let inkLayers: [PDFInkLayerModel]

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = displayMode == .continuous ? .singlePageContinuous
            : (displayMode == .book ? .twoUp : .singlePage)
        view.displayDirection = displayMode == .continuous ? .vertical : .horizontal
        view.displaysAsBook = displayMode == .book
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        view.displayMode = displayMode == .continuous ? .singlePageContinuous
            : (displayMode == .book ? .twoUp : .singlePage)
        view.displaysAsBook = displayMode == .book
        if let page = document.page(at: currentPageIndex) { view.go(to: page) }
    }
}
#endif

// MARK: - PencilKit page editor

private struct PDFInkEditor: View {
    let document: PDFDocument
    @Binding var pageIndex: Int
    let drawing: PKDrawing
    let onChange: (PKDrawing, CGSize) -> Void

    var body: some View {
        GeometryReader { geo in
            if let page = document.page(at: pageIndex) {
                let bounds = page.bounds(for: .cropBox)
                let size = fittedSize(aspect: bounds.width / max(1, bounds.height), in: geo.size)
                ZStack {
                    PDFPageThumbnail(fileName: document.documentURL?.lastPathComponent ?? "",
                                     pageIndex: pageIndex, directDocument: document)
                    #if canImport(UIKit)
                    PDFPencilCanvas(drawing: drawing, onChange: { onChange($0, size) })
                        .id(pageIndex)
                    #endif
                }
                .frame(width: size.width, height: size.height)
                .background(.white)
                .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .overlay(alignment: .bottom) { pageStepper }
    }

    private var pageStepper: some View {
        HStack {
            Button { pageIndex = max(0, pageIndex - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(pageIndex == 0)
            Text("Page \(pageIndex + 1)").font(.caption.weight(.bold)).frame(minWidth: 70)
            Button { pageIndex = min(document.pageCount - 1, pageIndex + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(pageIndex >= document.pageCount - 1)
        }
        .padding(8).background(.regularMaterial, in: Capsule()).padding(.bottom, 8)
    }
}

#if canImport(UIKit)
private struct PDFPencilCanvas: UIViewRepresentable {
    let drawing: PKDrawing
    let onChange: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawing = drawing
        canvas.drawingPolicy = .pencilOnly
        canvas.isScrollEnabled = false
        canvas.delegate = context.coordinator
        let picker = PKToolPicker()
        context.coordinator.picker = picker
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }
    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.onChange = onChange
        if canvas.drawing.dataRepresentation() != drawing.dataRepresentation(), !canvas.isFirstResponder {
            canvas.drawing = drawing
        }
        context.coordinator.picker?.setVisible(true, forFirstResponder: canvas)
    }
    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.picker?.setVisible(false, forFirstResponder: canvas)
        canvas.resignFirstResponder()
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onChange: (PKDrawing) -> Void
        var picker: PKToolPicker?
        init(onChange: @escaping (PKDrawing) -> Void) { self.onChange = onChange }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { onChange(canvasView.drawing) }
    }
}
#endif

// MARK: - Non-destructive crop editor

private struct PDFCropEditor: View {
    let document: PDFDocument
    @Binding var pageIndex: Int
    let initialCrop: PDFNormalizedRect
    let onPlace: (PDFNormalizedRect) -> Void
    @State private var crop = PDFNormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @State private var moveStart: PDFNormalizedRect?
    @State private var resizeStart: PDFNormalizedRect?

    var body: some View {
        GeometryReader { geo in
            if let page = document.page(at: pageIndex) {
                let bounds = page.bounds(for: .cropBox)
                let size = fittedSize(aspect: bounds.width / max(1, bounds.height), in: geo.size)
                ZStack {
                    PDFPageThumbnail(fileName: document.documentURL?.lastPathComponent ?? "",
                                     pageIndex: pageIndex, directDocument: document)
                    cropOverlay(size: size)
                }
                .frame(width: size.width, height: size.height)
                .background(.white)
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Reset") { crop = .fullPage }
                Spacer()
                Button { onPlace(crop) } label: { Label("Place Crop", systemImage: "crop") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .onAppear { crop = initialCrop == .fullPage
            ? PDFNormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8) : initialCrop }
    }

    private func cropOverlay(size: CGSize) -> some View {
        let rect = CGRect(
            x: crop.x * size.width,
            y: (1 - crop.y - crop.height) * size.height,
            width: crop.width * size.width,
            height: crop.height * size.height
        )
        return ZStack {
            Color.black.opacity(0.42)
                .mask(Rectangle().overlay(Rectangle().frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY).blendMode(.destinationOut)).compositingGroup())
            Rectangle().stroke(Color.accentColor, lineWidth: 3)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .gesture(DragGesture().onChanged { value in
                    let start = moveStart ?? crop
                    if moveStart == nil { moveStart = start }
                    let nextX = min(1 - start.width, max(0,
                        start.x + Double(value.translation.width / size.width)))
                    let nextTop = min(1 - start.height, max(0,
                        (1 - start.y - start.height) + Double(value.translation.height / size.height)))
                    crop.x = nextX
                    crop.y = 1 - nextTop - start.height
                }.onEnded { _ in moveStart = nil })
            Circle().fill(Color.accentColor).frame(width: 30, height: 30)
                .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                .position(x: rect.maxX, y: rect.maxY)
                .gesture(DragGesture().onChanged { value in
                    let start = resizeStart ?? crop
                    if resizeStart == nil { resizeStart = start }
                    let top = 1 - start.y - start.height
                    crop.width = min(1 - start.x, max(0.08,
                        start.width + Double(value.translation.width / size.width)))
                    crop.height = min(1 - top, max(0.08,
                        start.height + Double(value.translation.height / size.height)))
                    crop.y = 1 - top - crop.height
                }.onEnded { _ in resizeStart = nil })
        }
    }
}

private struct PDFPageThumbnail: View {
    let fileName: String
    let pageIndex: Int
    var directDocument: PDFDocument? = nil
    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            Color.white
            if let image {
                #if canImport(UIKit)
                Image(uiImage: image).resizable().scaledToFit()
                #else
                Image(nsImage: image).resizable().scaledToFit()
                #endif
            } else { ProgressView().controlSize(.small) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: pageIndex) {
            if let page = directDocument?.page(at: pageIndex) {
                image = page.thumbnail(of: CGSize(width: 1000, height: 1400), for: .cropBox)
            } else {
                image = PDFPageRenderingService.render(
                    fileName: fileName,
                    pageIndex: pageIndex,
                    maxPixels: 1000
                )
            }
        }
    }
}

private func fittedSize(aspect: CGFloat, in container: CGSize) -> CGSize {
    let available = CGSize(width: max(120, container.width - 48),
                           height: max(160, container.height - 48))
    if available.width / available.height > aspect {
        return CGSize(width: available.height * aspect, height: available.height)
    }
    return CGSize(width: available.width, height: available.width / max(0.05, aspect))
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(pdfHex: String) {
        let value = pdfHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)
        self.init(red: CGFloat((number >> 16) & 0xff) / 255,
                  green: CGFloat((number >> 8) & 0xff) / 255,
                  blue: CGFloat(number & 0xff) / 255, alpha: 1)
    }
}
#endif

private extension Color {
    init(pdfWorkspaceBackground: Bool) {
        #if canImport(UIKit)
        self.init(uiColor: .secondarySystemBackground)
        #else
        self.init(nsColor: .windowBackgroundColor)
        #endif
    }
}
