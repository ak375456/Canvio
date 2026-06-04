import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import PencilKit
#if os(iOS)
import VisionKit
#endif

private let canvasViewportCoordinateSpace = "CanvasViewport"

private struct CanvasStackPickerItem: Identifiable {
    let id: UUID
    let title: String
    let icon: String
    let tint: Color
    let zIndex: Int
}

private struct CanvasStackPickerState: Identifiable {
    let id = UUID()
    let position: CGPoint
    let width: CGFloat
    let maxHeight: CGFloat
    let items: [CanvasStackPickerItem]
}

struct CanvasView: View {
    let canvas: CanvasModel
    var onDelete: () -> Void
    var onRename: (String) -> Void

    @EnvironmentObject private var settings: AppSettings
    @StateObject private var vm = CanvasViewModel()
    @ObservedObject private var selection: SelectionViewModel = SelectionViewModel()
    @StateObject private var layersVM = LayersViewModel()
    @Environment(\.modelContext) private var context
    @Query private var allTextElements: [TextElementModel]
    @Query private var allStickyNotes: [StickyNoteModel]
    @Query private var allTodoLists: [TodoListModel]
    @Query private var allTodoTasks: [TodoTaskModel]
    @Query private var allShapes: [ShapeElementModel]
    @Query private var allImages: [ImageElementModel]
    @Query private var allPDFs: [PDFElementModel]
    @Query private var allTables: [TableElementModel]
    @Query private var allTableCells: [TableCellModel]
    @Query private var allAudio: [AudioElementModel]
    @Query private var allYouTube: [YouTubeElementModel]
    @Query private var allDrawings: [DrawingElementModel]
    @Query private var allConnectors: [ConnectorModel]
    @Query private var allSymbols: [SymbolElementModel]     // ← NEW

    @State private var showDeleteAlert = false
    @State private var showRenameAlert = false
    @State private var showSettings = false
    @State private var showLayers = false
    @State private var showPDFReader = false
    @State private var showTableSizePicker = false
    @State private var showCSVExporter = false
    @State private var csvExportString = ""
    @State private var csvExportFilename = "table"
    @State private var stackPicker: CanvasStackPickerState?
    @State private var newName: String = ""
    @State private var lastMenuLocation: CGPoint? = nil
    @State private var openPDFElement: PDFElementModel? = nil
    @State private var showPDFImporter = false
    @State private var drawingStartScale:  CGFloat = 1.0
    @State private var drawingStartOffset: CGSize  = .zero
    @State private var isCanvasDrawingInputActive = true
    @State private var isCanvasGestureActive = false
    @State private var canvasGestureSuppressionID = UUID()
    @State private var isProcessingOCRScan = false
    @State private var isProcessingDocumentScan = false
    @State private var ocrScanAlertMessage: String?
    #if os(iOS)
    @State private var keyboardAvoidanceOffset: CGFloat = 0
    #endif

    @Environment(\.dismiss) private var dismiss

    private var textElements: [TextElementModel]   { allTextElements.filter { $0.canvasID == canvas.id } }
    private var stickyNotes: [StickyNoteModel]     { allStickyNotes.filter  { $0.canvasID == canvas.id } }
    private var todoLists: [TodoListModel]          { allTodoLists.filter    { $0.canvasID == canvas.id } }
    private var todoTasks: [TodoTaskModel] {
        let ids = Set(todoLists.map { $0.id })
        return allTodoTasks.filter { ids.contains($0.listID) }
    }
    private var shapes: [ShapeElementModel]         { allShapes.filter       { $0.canvasID == canvas.id } }
    private var images: [ImageElementModel]         { allImages.filter       { $0.canvasID == canvas.id } }
    private var pdfs: [PDFElementModel]             { allPDFs.filter         { $0.canvasID == canvas.id } }
    private var tables: [TableElementModel]         { allTables.filter       { $0.canvasID == canvas.id } }
    private var tableCells: [TableCellModel] {
        let ids = Set(tables.map { $0.id })
        return allTableCells.filter { ids.contains($0.tableID) }
    }
    private var audioElements: [AudioElementModel] { allAudio.filter        { $0.canvasID == canvas.id } }
    private var youtubeElements: [YouTubeElementModel] { allYouTube.filter  { $0.canvasID == canvas.id } }
    private var drawings: [DrawingElementModel]    { allDrawings.filter     { $0.canvasID == canvas.id } }
    private var connectors: [ConnectorModel]       { allConnectors.filter   { $0.canvasID == canvas.id } }
    private var symbols: [SymbolElementModel]      { allSymbols.filter      { $0.canvasID == canvas.id } }  // ← NEW

    private var allLayerableElements: [any LayerableElement] {
        var arr: [any LayerableElement] = []
        arr += textElements    as [any LayerableElement]
        arr += stickyNotes     as [any LayerableElement]
        arr += todoLists       as [any LayerableElement]
        arr += shapes          as [any LayerableElement]
        arr += images          as [any LayerableElement]
        arr += pdfs            as [any LayerableElement]
        arr += tables          as [any LayerableElement]
        arr += audioElements   as [any LayerableElement]
        arr += youtubeElements as [any LayerableElement]
        arr += drawings        as [any LayerableElement]
        arr += symbols         as [any LayerableElement]
        return arr
    }

    private var sortedElements: [any LayerableElement] {
        allLayerableElements.sorted { $0.zIndex < $1.zIndex }
    }

    private var boundsMap: [UUID: ElementBounds] {
        var map: [UUID: ElementBounds] = [:]
        for el in textElements   { map[el.id] = ElementBounds(id: el.id, cx: el.x, cy: el.y, width: 160,           height: 40)            }
        for el in stickyNotes    { map[el.id] = ElementBounds(id: el.id, cx: el.x, cy: el.y, width: el.width,      height: el.height)      }
        for el in todoLists      { map[el.id] = ElementBounds(id: el.id, cx: el.x, cy: el.y, width: el.width,      height: el.height)      }
        for el in shapes         { map[el.id] = ElementBounds(id: el.id, cx: el.x, cy: el.y, width: el.width,      height: el.height)      }
        for el in images         { map[el.id] = ElementBounds(id: el.id, cx: el.x, cy: el.y, width: el.width,      height: el.height)      }
        for el in pdfs           { map[el.id] = ElementBounds(id: el.id, cx: el.x, cy: el.y, width: el.width,      height: el.height)      }
        for el in tables         { map[el.id] = ElementBounds(id: el.id, cx: el.x, cy: el.y, width: el.totalWidth, height: el.totalHeight) }
        for el in audioElements  { map[el.id] = ElementBounds(id: el.id, cx: el.x, cy: el.y, width: el.width,      height: el.height)      }
        for el in youtubeElements { map[el.id] = ElementBounds(id: el.id, cx: el.x, cy: el.y, width: el.width,     height: el.height)      }
        for el in drawings       { map[el.id] = ElementBounds(id: el.id, cx: el.x, cy: el.y, width: el.width,      height: el.height)      }
        for el in symbols        { map[el.id] = ElementBounds(id: el.id, cx: el.x, cy: el.y, width: el.fontSize,   height: el.fontSize)    }  // ← NEW
        return map
    }

    private var activeSelectedElementID: UUID? {
        if let id = vm.textVM.editingID { return id }
        if let id = vm.stickyVM.editingID { return id }
        if let id = vm.todoVM.editingID { return id }
        if let id = vm.shapeVM.editingID { return id }
        if let id = vm.imageVM.editingID { return id }
        if let id = vm.pdfVM.editingID { return id }
        if let id = vm.tableVM.selectedTableID { return id }
        if let id = vm.audioVM.editingID { return id }
        if let id = vm.youtubeVM.editingID { return id }
        if let id = vm.drawingVM.editingID { return id }
        if let id = vm.symbolVM.editingID { return id }
        return nil
    }

    private var selectedElementGestureFrame: CGRect? {
        guard let id = activeSelectedElementID,
              let bounds = boundsMap[id] else { return nil }

        let width  = CGFloat(bounds.width) * vm.scale
        let height = CGFloat(bounds.height) * vm.scale
        let x = CGFloat(bounds.cx) * vm.scale + vm.offset.width - width / 2
        let y = CGFloat(bounds.cy) * vm.scale + vm.offset.height - height / 2

        return CGRect(x: x, y: y, width: width, height: height)
            .insetBy(dx: -44, dy: -80)
    }

    init(canvas: CanvasModel, onDelete: @escaping () -> Void, onRename: @escaping (String) -> Void) {
        self.canvas   = canvas
        self.onDelete = onDelete
        self.onRename = onRename
        self._selection = ObservedObject(wrappedValue: SelectionViewModel())
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {

                CanvasGridView(
                    offset: vm.offset,
                    scale: vm.scale,
                    style: settings.effectiveGridStyle,
                    backgroundMode: settings.canvasBackgroundMode,
                    backgroundPalette: settings.canvasBackgroundPalette
                )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        stackPicker = nil
                        guard !isCanvasGestureActive else { return }
                        if selection.isMultiSelectActive || vm.connectorVM.isConnectModeActive {
                        } else {
                            dismissEverything()
                        }
                    }
                    .simultaneousGesture(
                        SpatialTapGesture(count: 2)
                            .onEnded { tap in
                                guard !selection.isMultiSelectActive,
                                      !vm.showCanvasDrawingOverlay,
                                      !vm.connectorVM.isConnectModeActive,
                                      !isCanvasGestureActive else { return }
                                dismissEverything()
                                let pt = tap.location
                                let canvasX = (pt.x - vm.offset.width)  / vm.scale
                                let canvasY = (pt.y - vm.offset.height) / vm.scale
                                let _ = vm.textVM.addInlineText(
                                    canvasID: canvas.id,
                                    canvasPoint: CGPoint(x: canvasX, y: canvasY),
                                    zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                                    context: context,
                                    undoManager: vm.undoManager
                                )
                            }
                    )
                    .onLongPressGesture(minimumDuration: 0.5) {
                        guard !vm.connectorVM.isConnectModeActive,
                              !isCanvasGestureActive else { return }
                        if !selection.isMultiSelectActive {
                            dismissEverything()
                            withAnimation(.spring(duration: 0.3)) { selection.enterMultiSelect() }
                        }
                    }
                    #if os(macOS)
                    .gesture(
                        SimultaneousGesture(
                            canvasPanGesture(geo: geo),
                            canvasMagnifyGesture(geo: geo)
                        )
                    )
                    #endif

                if !canvas.isInfinite { pageBoundaryOverlay(geo: geo) }

                ZStack {
                    ConnectorOverlayView(
                        connectors: connectors,
                        boundsMap: boundsMap,
                        vm: vm.connectorVM,
                        undoManager: vm.undoManager,
                        canvasID: canvas.id,
                        canvasScale: vm.scale
                    )
                    .zIndex(-1)

                    ConnectorAnchorDotsView(
                        boundsMap:   boundsMap,
                        vm:          vm.connectorVM,
                        undoManager: vm.undoManager,
                        canvasID:    canvas.id,
                        canvasScale: vm.scale,
                        connectors:  connectors
                    )
                    .zIndex(9999)

                    ForEach(sortedElements, id: \.id) { element in
                        renderElement(element)
                    }
                }
                .opacity(vm.showCanvasDrawingOverlay ? 0.82 : 1.0)
                .animation(.easeInOut(duration: 0.25), value: vm.showCanvasDrawingOverlay)
                .scaleEffect(vm.scale, anchor: .topLeading)
                .offset(vm.offset)
                .simultaneousGesture(
                    SpatialTapGesture(count: 1, coordinateSpace: .named(canvasViewportCoordinateSpace))
                        .onEnded { tap in
                            handleElementStackTap(at: tap.location, viewportSize: geo.size)
                        }
                )
                #if os(macOS)
                .gesture(canvasPanGesture(geo: geo))
                .simultaneousGesture(canvasMagnifyGesture(geo: geo))
                #endif

                #if os(iOS)
                CanvasGestureBridge(
                    isEnabled: !vm.showCanvasDrawingOverlay || !isCanvasDrawingInputActive,
                    selectedElementFrame: selectedElementGestureFrame,
                    onPanChanged: { translation in
                        vm.offset = CGSize(
                            width: vm.lastOffset.width + translation.width,
                            height: vm.lastOffset.height + translation.height
                        )
                    },
                    onPanEnded: {
                        vm.handleDragEnd()
                        if !canvas.isInfinite {
                            vm.clampOffset(to: canvas.boundarySize, viewportSize: geo.size, scale: vm.scale)
                        }
                    },
                    onPinchBegan: {
                        beginCanvasGestureSuppression()
                        vm.lastScale = vm.scale
                        vm.lastOffset = vm.offset
                    },
                    onPinchChanged: { magnification, focal in
                        beginCanvasGestureSuppression()
                        vm.handleMagnification(magnification, focalPoint: focal)
                    },
                    onPinchEnded: {
                        vm.handleMagnificationEnd()
                        if !canvas.isInfinite {
                            vm.clampOffset(to: canvas.boundarySize, viewportSize: geo.size, scale: vm.scale)
                        }
                        endCanvasGestureSuppression()
                    }
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)
                #endif

                if !vm.showCanvasDrawingOverlay && !selection.isMultiSelectActive {
                    toolbarLayer(geo: geo)
                }

                if vm.connectorVM.isConnectModeActive {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: connectModeIcon)
                                .font(.system(size: 13, weight: .medium))
                            Text(connectModeHint)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button("Done") { vm.connectorVM.exitConnectMode() }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .accentColor.opacity(0.4), radius: 8, x: 0, y: 3)
                        .padding(.horizontal, 16).padding(.top, 16)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .zIndex(90)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(duration: 0.3), value: vm.connectorVM.isConnectModeActive)
                }

                if selection.isMultiSelectActive {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.tap").font(.system(size: 13, weight: .medium))
                            Text(selection.count == 0 ? "Tap elements to select" : "\(selection.count) selected")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.blue, in: Capsule())
                        .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 3)
                        .padding(.top, 16)
                        Spacer()
                        MultiSelectBar(
                            count: selection.count,
                            onDuplicate: { duplicateSelected() },
                            onDelete: { deleteSelected() },
                            onDone: {
                                withAnimation(.spring(duration: 0.3)) { selection.exit() }
                                dismissEverything()
                            }
                        )
                        .padding(.bottom, 24)
                    }
                    .frame(maxWidth: .infinity).zIndex(90).transition(.opacity)
                    .animation(.spring(duration: 0.3), value: selection.isMultiSelectActive)
                }

                if let picker = stackPicker {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { stackPicker = nil }
                        .zIndex(118)

                    stackPickerView(picker)
                        .zIndex(119)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }

                if isProcessingOCRScan || isProcessingDocumentScan {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(isProcessingOCRScan ? "Extracting text..." : "Preparing scan...")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 16)
                    .zIndex(95)
                }

                if let pos = vm.addMenuPosition {
                    Color.black.opacity(0.001).ignoresSafeArea().contentShape(Rectangle())
                        .onTapGesture { vm.hideAddMenu() }
                    AddElementMenu(position: pos) { tool in
                        handleToolSelection(tool, at: pos, geo: geo)
                    } onDismiss: { vm.hideAddMenu() }
                    .zIndex(100)
                }

                if vm.showCanvasDrawingOverlay {
                    CanvasDrawingOverlay(
                        isActive:     $vm.showCanvasDrawingOverlay,
                        isDrawingInputActive: $isCanvasDrawingInputActive,
                        startScale:   drawingStartScale,
                        startOffset:  drawingStartOffset,
                        liveScale:    $vm.scale,
                        liveOffset:   $vm.offset
                    ) { pkDrawing, effectiveScale, effectiveOffset in
                        let strokeBounds = pkDrawing.bounds
                        guard !pkDrawing.strokes.isEmpty,
                              strokeBounds.width > 0, strokeBounds.height > 0 else { return }
                        let padding: CGFloat = 20
                        let paddedBounds = strokeBounds.insetBy(dx: -padding, dy: -padding)
                        let canvasX = (paddedBounds.midX - effectiveOffset.width) / effectiveScale
                        let canvasY = (paddedBounds.midY - effectiveOffset.height) / effectiveScale
                        let elemW = paddedBounds.width  / effectiveScale
                        let elemH = paddedBounds.height / effectiveScale
                        let s  = 1.0 / effectiveScale
                        let tx = -paddedBounds.minX * s
                        let ty = -paddedBounds.minY * s
                        let transform = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: tx, ty: ty)
                        let element = DrawingElementModel(
                            canvasID: canvas.id, x: canvasX, y: canvasY,
                            width: Double(elemW), height: Double(elemH), isCanvasDrawing: true
                        )
                        element.pkDrawing = pkDrawing.transformed(using: transform)
                        element.zIndex = LayersViewModel.nextZ(among: allLayerableElements)
                        context.insert(element); try? context.save()
                        Task { await DrawingSyncService.shared.upsert(element) }
                    }
                    .zIndex(200).transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(name: canvasViewportCoordinateSpace)
            .clipped()
            #if os(macOS)
            .overlay(
                MacScrollInterceptor { deltaX, deltaY, phase, isZoom in
                    if isZoom {
                        let screenPt = NSEvent.mouseLocation
                        let windowPt = NSApp.keyWindow?.convertPoint(fromScreen: screenPt)
                        let focal: CGPoint
                        if let wp = windowPt {
                            let windowH = NSApp.keyWindow?.frame.height ?? geo.size.height
                            focal = CGPoint(x: wp.x, y: windowH - wp.y)
                        } else {
                            focal = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                        let zoomSensitivity: CGFloat = 0.008
                        let delta    = -deltaY * zoomSensitivity
                        let newScale = max(0.15, min(vm.scale * (1.0 + delta), 8.0))
                        let scaleDelta = newScale / vm.scale
                        let newW = focal.x - (focal.x - vm.offset.width)  * scaleDelta
                        let newH = focal.y - (focal.y - vm.offset.height) * scaleDelta
                        vm.offset = CGSize(width: newW, height: newH)
                        vm.scale = newScale; vm.lastScale = newScale; vm.lastOffset = vm.offset
                        if !canvas.isInfinite {
                            vm.clampOffset(to: canvas.boundarySize, viewportSize: geo.size, scale: vm.scale)
                        }
                    } else {
                        vm.offset = CGSize(width: vm.offset.width + deltaX, height: vm.offset.height + deltaY)
                        vm.lastOffset = vm.offset
                        if !canvas.isInfinite {
                            vm.clampOffset(to: canvas.boundarySize, viewportSize: geo.size, scale: vm.scale)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            )
            #endif
            .onAppear {
                if !canvas.isInfinite {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        vm.centerPage(boundary: canvas.boundarySize, viewportSize: geo.size)
                    }
                }
                pullFromCloud()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let ghosts = textElements.filter {
                        $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    for el in ghosts {
                        Task { await TextSyncService.shared.delete(el) }
                        context.delete(el)
                    }
                    if !ghosts.isEmpty { try? context.save() }
                }
            }
            .onDisappear { generateThumbnail() }
            .onChange(of: settings.overlapStackPickerEnabled) { _, isEnabled in
                if !isEnabled { stackPicker = nil }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ocrCreatedTextElement)) { notification in
                guard let textID = notification.object as? UUID else { return }
                dismissEverything()
                vm.textVM.editingID = textID
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification)) { notif in
                guard vm.textVM.inlineEditingID != nil else { return }
                guard let kbFrame = notif.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                      let duration = notif.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
                else { return }
                let kbHeight = kbFrame.height
                let safeBottom = geo.safeAreaInsets.bottom
                let availableHeight = geo.size.height - kbHeight + safeBottom
                if let editID = vm.textVM.inlineEditingID,
                   let el = textElements.first(where: { $0.id == editID }) {
                    let elementScreenY = CGFloat(el.y) * vm.scale + vm.offset.height
                    let targetY = availableHeight - 80
                    if elementScreenY > targetY {
                        let delta = elementScreenY - targetY
                        keyboardAvoidanceOffset = delta
                        withAnimation(.easeOut(duration: duration)) {
                            vm.offset.height -= delta
                            vm.lastOffset = vm.offset
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification)) { notif in
                guard keyboardAvoidanceOffset != 0 else { return }
                let duration = (notif.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
                withAnimation(.easeOut(duration: duration)) {
                    vm.offset.height += keyboardAvoidanceOffset
                    vm.lastOffset = vm.offset
                }
                keyboardAvoidanceOffset = 0
            }
            #endif
            .overlay(alignment: .topTrailing) {
                if !vm.showCanvasDrawingOverlay && !selection.isMultiSelectActive
                    && !vm.connectorVM.isConnectModeActive {
                    Minimap(
                        textElements: textElements, stickyNotes: stickyNotes,
                        todoLists: todoLists, shapes: shapes, images: images,
                        pdfs: pdfs, tables: tables, audioElements: audioElements,
                        youtubeElements: youtubeElements, drawings: drawings,
                        symbols: symbols, viewportSize: geo.size,
                        canvasOffset: vm.offset, canvasScale: vm.scale,
                        onTapElement: { vm.centerOn(canvasPoint: $0, viewportSize: geo.size) },
                        isExpanded: $vm.isMinimapExpanded
                    )
                    .padding(.trailing, 12).padding(.top, 12)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                youtubePlaybackControl
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
            }
            .sheet(isPresented: $vm.showTextSheet) {
                AddTextSheet(isPresented: $vm.showTextSheet) { style in
                    vm.textVM.addText(
                        canvasID: canvas.id, style: style,
                        center: lastMenuLocation ?? CGPoint(x: geo.size.width/2, y: geo.size.height/2),
                        offset: vm.offset, scale: vm.scale,
                        zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                        context: context, undoManager: vm.undoManager
                    )
                }
                .presentationDetents([.height(480)]).presentationDragIndicator(.visible).presentationCornerRadius(24)
            }
            .sheet(isPresented: $vm.showShapePicker) {
                ShapePickerSheet { kind in
                    let point = vm.pendingShapeLocation ?? CGPoint(x: geo.size.width/2, y: geo.size.height/2)
                    vm.shapeVM.addShape(canvasID: canvas.id, kind: kind, center: point,
                                       offset: vm.offset, scale: vm.scale,
                                       zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                                       context: context, undoManager: vm.undoManager)
                    vm.pendingShapeLocation = nil
                }
                .presentationDetents([.height(380)]).presentationDragIndicator(.visible).presentationCornerRadius(24)
            }
            // ── Symbol picker ────────────────────────────────────────────────── NEW
            .sheet(isPresented: $vm.showSymbolPicker) {
                SymbolPickerSheet { symbolName, colorName, fontSize in
                    let center = vm.pendingSymbolLocation ?? CGPoint(x: geo.size.width/2, y: geo.size.height/2)
                    vm.symbolVM.addSymbol(
                        canvasID: canvas.id, symbolName: symbolName,
                        colorName: colorName, fontSize: fontSize,
                        center: center, offset: vm.offset, scale: vm.scale,
                        zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                        context: context, undoManager: vm.undoManager
                    )
                    vm.pendingSymbolLocation = nil
                }
                .presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(24)
            }
            .sheet(isPresented: $showTableSizePicker) {
                TableSizePickerSheet { rows, cols in
                    let point = vm.pendingTableLocation ?? CGPoint(x: geo.size.width/2, y: geo.size.height/2)
                    vm.tableVM.addTable(canvasID: canvas.id, rows: rows, cols: cols, center: point,
                                       offset: vm.offset, scale: vm.scale,
                                       zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                                       context: context, undoManager: vm.undoManager)
                    vm.pendingTableLocation = nil
                }
                .presentationDetents([.height(600)]).presentationDragIndicator(.visible).presentationCornerRadius(24)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(settings: settings, exportButton: AnyView(
                    CanvasExportButton(
                        canvas:        canvas,
                        textElements:  textElements,
                        stickyNotes:   stickyNotes,
                        todoLists:     todoLists,
                        todoTasks:     todoTasks,
                        shapes:        shapes,
                        images:        images,
                        pdfs:          pdfs,
                        tables:        tables,
                        tableCells:    tableCells,
                        audioElements: audioElements,
                        drawings:      drawings,
                        connectors:    connectors
                    )
                ))
                    .presentationDetents([.height(680), .large]).presentationDragIndicator(.visible).presentationCornerRadius(24)
            }
            .sheet(isPresented: $showLayers) {
                LayersSheet(allElements: allLayerableElements, vm: layersVM) { id in
                    layersVM.highlight(id); selectElement(id: id)
                }
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).presentationCornerRadius(24)
            }
            .sheet(isPresented: $vm.showAudioPicker) {
                AudioPickerSheet(showRecorder: $vm.showAudioRecorder, showImporter: $vm.showAudioImporter)
                    .presentationDetents([.height(260)]).presentationDragIndicator(.visible).presentationCornerRadius(24)
            }
            .sheet(isPresented: $vm.showAudioRecorder) {
                AudioRecorderSheet { tempURL in
                    do {
                        let result = try AudioStorageService.saveRecording(from: tempURL)
                        let center = vm.pendingAudioLocation ?? CGPoint(x: geo.size.width/2, y: geo.size.height/2)
                        vm.audioVM.addAudio(
                            canvasID: canvas.id,
                            audioFileName: result.fileName,
                            originalName: "Recording \(Date().formatted(.dateTime.hour().minute()))",
                            duration: result.duration, center: center,
                            offset: vm.offset, scale: vm.scale,
                            zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                            context: context, undoManager: vm.undoManager)
                        vm.pendingAudioLocation = nil
                    } catch { print("⚠️ Save recording error: \(error)") }
                }
                .presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(24)
            }
            .sheet(isPresented: $vm.showYouTubeLinkSheet) {
                AddYouTubeLinkSheet(isPresented: $vm.showYouTubeLinkSheet) { urlString, title in
                    let center = vm.pendingYouTubeLocation ?? CGPoint(x: geo.size.width/2, y: geo.size.height/2)
                    let added = vm.youtubeVM.addVideo(
                        canvasID: canvas.id,
                        urlString: urlString,
                        title: title,
                        center: center,
                        offset: vm.offset,
                        scale: vm.scale,
                        zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                        context: context,
                        undoManager: vm.undoManager
                    )
                    if added { vm.pendingYouTubeLocation = nil }
                    return added
                }
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
            #if os(iOS)
            .sheet(isPresented: $vm.showImageSourcePicker) {
                ImageSourcePickerSheet(
                    onCamera: { vm.showCameraPicker = true },
                    onPhotos: { vm.showImagePicker  = true }
                )
                .presentationDetents([.height(220)]).presentationDragIndicator(.visible).presentationCornerRadius(24)
            }
            .fullScreenCover(isPresented: $vm.showCameraPicker) {
                CameraPickerView { imageData in
                    let center = vm.pendingImageLocation ?? CGPoint(x: geo.size.width/2, y: geo.size.height/2)
                    vm.imageVM.addImage(
                        canvasID: canvas.id, imageData: imageData, center: center,
                        offset: vm.offset, scale: vm.scale,
                        zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                        context: context, undoManager: vm.undoManager
                    )
                    vm.pendingImageLocation = nil
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $vm.showOCRScanner) {
                OCRDocumentScannerView(
                    onComplete: { images in
                        vm.showOCRScanner = false
                        createOCRTextFromScan(images: images, geo: geo)
                    },
                    onCancel: {
                        vm.showOCRScanner = false
                        vm.pendingOCRLocation = nil
                    },
                    onError: { _ in
                        vm.showOCRScanner = false
                        vm.pendingOCRLocation = nil
                        ocrScanAlertMessage = "Could not scan this document."
                    }
                )
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $vm.showDocumentScanner) {
                OCRDocumentScannerView(
                    onComplete: { images in
                        vm.showDocumentScanner = false
                        createDocumentFromScan(images: images, geo: geo)
                    },
                    onCancel: {
                        vm.showDocumentScanner = false
                        vm.pendingDocumentScanLocation = nil
                    },
                    onError: { _ in
                        vm.showDocumentScanner = false
                        vm.pendingDocumentScanLocation = nil
                        ocrScanAlertMessage = "Could not scan this document."
                    }
                )
                .ignoresSafeArea()
            }
            #endif
            .photosPicker(isPresented: $vm.showImagePicker, selection: $vm.selectedPhotoItem, matching: .images)
            .onChange(of: vm.selectedPhotoItem) { _, newItem in
                guard let item = newItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let center = vm.pendingImageLocation ?? CGPoint(x: geo.size.width/2, y: geo.size.height/2)
                        vm.imageVM.addImage(canvasID: canvas.id, imageData: data, center: center,
                                           offset: vm.offset, scale: vm.scale,
                                           zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                                           context: context, undoManager: vm.undoManager)
                        vm.pendingImageLocation = nil
                    }
                    vm.selectedPhotoItem = nil
                }
            }
            .fileImporter(isPresented: $vm.showTableCSVImporter,
                         allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
                         allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    if let csv = try? String(contentsOf: url, encoding: .utf8),
                       let tableID = vm.pendingCSVTableID,
                       let table = tables.first(where: { $0.id == tableID }) {
                        vm.tableVM.importCSV(csv, into: table, cells: tableCells, context: context)
                    }
                    vm.pendingCSVTableID = nil
                }
            }
            .fileImporter(isPresented: $vm.showAudioImporter,
                         allowedContentTypes: [UTType.mp3, UTType.mpeg4Audio, UTType.aiff, UTType.wav],
                         allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let imported = try AudioStorageService.importAudio(from: url)
                        let center = vm.pendingAudioLocation ?? CGPoint(x: 300, y: 400)
                        vm.audioVM.addAudio(canvasID: canvas.id, audioFileName: imported.fileName,
                                           originalName: imported.originalName, duration: imported.duration,
                                           center: center, offset: vm.offset, scale: vm.scale,
                                           zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                                           context: context, undoManager: vm.undoManager)
                        vm.pendingAudioLocation = nil
                    } catch { print("⚠️ Audio import error: \(error)") }
                case .failure(let error): print("⚠️ Audio file error: \(error)")
                }
            }
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureDisabler(isDisabled: true))
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            #endif

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button { vm.undoManager.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!vm.undoManager.canUndo)
                    Button { vm.undoManager.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!vm.undoManager.canRedo)
                    Button {
                        if selection.isMultiSelectActive {
                            withAnimation(.spring(duration: 0.3)) { selection.exit() }
                            dismissEverything()
                        } else {
                            dismissEverything()
                            withAnimation(.spring(duration: 0.3)) { selection.enterMultiSelect() }
                        }
                    } label: {
                        Image(systemName: selection.isMultiSelectActive
                              ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundStyle(selection.isMultiSelectActive ? .blue : .primary)
                    }
                    Button { showLayers = true } label: { Image(systemName: "square.3.layers.3d") }
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                    Menu {
                        Button { newName = canvas.name; showRenameAlert = true } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) { showDeleteAlert = true } label: {
                            Label("Delete Canvas", systemImage: "trash")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showPDFReader, onDismiss: { openPDFElement = nil }) {
            if let pdf = openPDFElement {
                PDFReaderSheet(pdfFileName: pdf.pdfFileName, originalName: pdf.originalName, pageCount: pdf.pageCount)
            }
        }
        .sheet(isPresented: $showPDFImporter) {
            #if canImport(UIKit)
            PDFDocumentPicker { url in
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let center = vm.pendingPDFLocation ?? CGPoint(x: 300, y: 400)
                vm.pdfVM.addPDF(canvasID: canvas.id, sourceURL: url, center: center,
                               offset: vm.offset, scale: vm.scale,
                               zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                               context: context, undoManager: vm.undoManager)
                vm.pendingPDFLocation = nil; showPDFImporter = false
            }
            #endif
        }
        .sheet(isPresented: $showCSVExporter) {
            CSVShareSheet(csvString: csvExportString, filename: csvExportFilename)
                .presentationDetents([.medium]).presentationDragIndicator(.visible).presentationCornerRadius(24)
        }
        .alert("Delete Canvas", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { onDelete(); dismiss() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("\(canvas.name) will be permanently deleted.") }
        .alert("Rename Canvas", isPresented: $showRenameAlert) {
            TextField("Canvas name", text: $newName).autocorrectionDisabled()
            Button("Rename") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { onRename(trimmed) }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("OCR Scan", isPresented: Binding(
            get: { ocrScanAlertMessage != nil },
            set: { if !$0 { ocrScanAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { ocrScanAlertMessage = nil }
        } message: {
            Text(ocrScanAlertMessage ?? "")
        }
    }

    @ViewBuilder
    private func stackPickerView(_ picker: CanvasStackPickerState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(picker.items.count) items here")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Button {
                    withAnimation(.spring(duration: 0.2)) { stackPicker = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(picker.items.enumerated()), id: \.element.id) { index, item in
                        stackPickerRow(
                            item,
                            isFront: index == 0,
                            isSelected: item.id == activeSelectedElementID
                        )
                    }
                }
            }
            .frame(maxHeight: max(44, picker.maxHeight - 45))
        }
        .frame(width: picker.width)
        .frame(maxHeight: picker.maxHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 6)
        .position(picker.position)
    }

    private func stackPickerRow(_ item: CanvasStackPickerItem,
                                isFront: Bool,
                                isSelected: Bool) -> some View {
        Button {
            selectStackItem(item.id)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(item.tint.opacity(0.16))
                    Image(systemName: item.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(item.tint)
                }
                .frame(width: 30, height: 30)

                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isFront {
                    Text("Front")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleElementStackTap(at screenPoint: CGPoint, viewportSize: CGSize) {
        guard settings.overlapStackPickerEnabled else {
            stackPicker = nil
            return
        }

        guard !selection.isMultiSelectActive,
              !vm.showCanvasDrawingOverlay,
              !vm.connectorVM.isConnectModeActive,
              !isCanvasGestureActive else {
            stackPicker = nil
            return
        }

        let items = stackItems(at: screenPoint)
        DispatchQueue.main.async {
            guard items.count > 1 else {
                stackPicker = nil
                return
            }

            withAnimation(.spring(duration: 0.22)) {
                stackPicker = makeStackPicker(
                    items: items,
                    near: screenPoint,
                    viewportSize: viewportSize
                )
            }
        }
    }

    private func stackItems(at screenPoint: CGPoint) -> [CanvasStackPickerItem] {
        let canvasPoint = CGPoint(
            x: (screenPoint.x - vm.offset.width) / vm.scale,
            y: (screenPoint.y - vm.offset.height) / vm.scale
        )
        let hitSlop = max(2, 8 / max(vm.scale, 0.01))
        var items: [CanvasStackPickerItem] = []

        appendStackItems((try? context.fetch(FetchDescriptor<TextElementModel>())) ?? [],
                         canvasPoint: canvasPoint, hitSlop: hitSlop, into: &items) {
            ElementBounds(id: $0.id, cx: $0.x, cy: $0.y, width: 160, height: 40)
        }
        appendStackItems((try? context.fetch(FetchDescriptor<StickyNoteModel>())) ?? [],
                         canvasPoint: canvasPoint, hitSlop: hitSlop, into: &items) {
            ElementBounds(id: $0.id, cx: $0.x, cy: $0.y, width: $0.width, height: $0.height)
        }
        appendStackItems((try? context.fetch(FetchDescriptor<TodoListModel>())) ?? [],
                         canvasPoint: canvasPoint, hitSlop: hitSlop, into: &items) {
            ElementBounds(id: $0.id, cx: $0.x, cy: $0.y, width: $0.width, height: $0.height)
        }
        appendStackItems((try? context.fetch(FetchDescriptor<ShapeElementModel>())) ?? [],
                         canvasPoint: canvasPoint, hitSlop: hitSlop, into: &items) {
            ElementBounds(id: $0.id, cx: $0.x, cy: $0.y, width: $0.width, height: $0.height)
        }
        appendStackItems((try? context.fetch(FetchDescriptor<ImageElementModel>())) ?? [],
                         canvasPoint: canvasPoint, hitSlop: hitSlop, into: &items) {
            ElementBounds(id: $0.id, cx: $0.x, cy: $0.y, width: $0.width, height: $0.height)
        }
        appendStackItems((try? context.fetch(FetchDescriptor<PDFElementModel>())) ?? [],
                         canvasPoint: canvasPoint, hitSlop: hitSlop, into: &items) {
            ElementBounds(id: $0.id, cx: $0.x, cy: $0.y, width: $0.width, height: $0.height)
        }
        appendStackItems((try? context.fetch(FetchDescriptor<TableElementModel>())) ?? [],
                         canvasPoint: canvasPoint, hitSlop: hitSlop, into: &items) {
            ElementBounds(id: $0.id, cx: $0.x, cy: $0.y, width: $0.totalWidth, height: $0.totalHeight)
        }
        appendStackItems((try? context.fetch(FetchDescriptor<AudioElementModel>())) ?? [],
                         canvasPoint: canvasPoint, hitSlop: hitSlop, into: &items) {
            ElementBounds(id: $0.id, cx: $0.x, cy: $0.y, width: $0.width, height: $0.height)
        }
        appendStackItems((try? context.fetch(FetchDescriptor<YouTubeElementModel>())) ?? [],
                         canvasPoint: canvasPoint, hitSlop: hitSlop, into: &items) {
            ElementBounds(id: $0.id, cx: $0.x, cy: $0.y, width: $0.width, height: $0.height)
        }
        appendStackItems((try? context.fetch(FetchDescriptor<DrawingElementModel>())) ?? [],
                         canvasPoint: canvasPoint, hitSlop: hitSlop, into: &items) {
            ElementBounds(id: $0.id, cx: $0.x, cy: $0.y, width: $0.width, height: $0.height)
        }
        appendStackItems((try? context.fetch(FetchDescriptor<SymbolElementModel>())) ?? [],
                         canvasPoint: canvasPoint, hitSlop: hitSlop, into: &items) {
            ElementBounds(id: $0.id, cx: $0.x, cy: $0.y, width: $0.fontSize, height: $0.fontSize)
        }

        return items.sorted {
            if $0.zIndex == $1.zIndex { return $0.title < $1.title }
            return $0.zIndex > $1.zIndex
        }
    }

    private func appendStackItems<Element: LayerableElement>(
        _ elements: [Element],
        canvasPoint: CGPoint,
        hitSlop: CGFloat,
        into items: inout [CanvasStackPickerItem],
        bounds: (Element) -> ElementBounds
    ) {
        for element in elements where element.canvasID == canvas.id {
            guard bounds(element).contains(canvasPoint: canvasPoint, hitSlop: hitSlop) else { continue }
            items.append(CanvasStackPickerItem(
                id: element.id,
                title: element.layerTitle,
                icon: element.layerIcon,
                tint: element.layerTint,
                zIndex: element.zIndex
            ))
        }
    }

    private func makeStackPicker(items: [CanvasStackPickerItem],
                                 near screenPoint: CGPoint,
                                 viewportSize: CGSize) -> CanvasStackPickerState {
        let width = max(180, min(280, viewportSize.width - 24))
        let visibleRows = min(CGFloat(items.count), 6)
        let maxHeight = min(45 + visibleRows * 44, max(160, viewportSize.height - 24))
        let position = stackPickerPosition(
            near: screenPoint,
            pickerSize: CGSize(width: width, height: maxHeight),
            viewportSize: viewportSize
        )

        return CanvasStackPickerState(
            position: position,
            width: width,
            maxHeight: maxHeight,
            items: items
        )
    }

    private func stackPickerPosition(near point: CGPoint,
                                     pickerSize: CGSize,
                                     viewportSize: CGSize) -> CGPoint {
        let margin: CGFloat = 12
        let gap: CGFloat = 14

        var x = point.x + pickerSize.width / 2 + gap
        if x + pickerSize.width / 2 > viewportSize.width - margin {
            x = point.x - pickerSize.width / 2 - gap
        }
        x = min(max(margin + pickerSize.width / 2, x),
                viewportSize.width - margin - pickerSize.width / 2)

        var y = point.y + pickerSize.height / 2 + gap
        if y + pickerSize.height / 2 > viewportSize.height - margin {
            y = point.y - pickerSize.height / 2 - gap
        }
        y = min(max(margin + pickerSize.height / 2, y),
                viewportSize.height - margin - pickerSize.height / 2)

        return CGPoint(x: x, y: y)
    }

    private func selectStackItem(_ id: UUID) {
        withAnimation(.spring(duration: 0.2)) { stackPicker = nil }
        layersVM.highlight(id)
        selectElement(id: id)
    }

    // MARK: - Gestures

    private func canvasPanGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in vm.handleDragChange(value) }
            .onEnded { _ in
                vm.handleDragEnd()
                if !canvas.isInfinite {
                    vm.clampOffset(to: canvas.boundarySize, viewportSize: geo.size, scale: vm.scale)
                }
            }
    }

    private func canvasMagnifyGesture(geo: GeometryProxy) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                beginCanvasGestureSuppression()
                let focal = CGPoint(x: value.startAnchor.x * geo.size.width,
                                    y: value.startAnchor.y * geo.size.height)
                vm.handleMagnification(value.magnification, focalPoint: focal)
            }
            .onEnded { _ in
                vm.handleMagnificationEnd()
                if !canvas.isInfinite {
                    vm.clampOffset(to: canvas.boundarySize, viewportSize: geo.size, scale: vm.scale)
                }
                endCanvasGestureSuppression()
            }
    }

    private func beginCanvasGestureSuppression() {
        canvasGestureSuppressionID = UUID()
        isCanvasGestureActive = true
    }

    private func endCanvasGestureSuppression() {
        let token = UUID()
        canvasGestureSuppressionID = token
        isCanvasGestureActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if canvasGestureSuppressionID == token {
                isCanvasGestureActive = false
            }
        }
    }

    private func startCanvasDrawing() {
        dismissEverything()
        drawingStartScale  = vm.scale
        drawingStartOffset = vm.offset
        isCanvasDrawingInputActive = true
        vm.showCanvasDrawingOverlay = true
    }

    // MARK: - Sync

    private func pullFromCloud() {
        Task {
            await TextSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await StickyNoteSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await ShapeSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await ConnectorSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await DrawingSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await TodoSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await TableSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await ImageSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await PDFSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await AudioSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await YouTubeSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            await SymbolSyncService.shared.pullAll(canvasID: canvas.id, context: context)  // ← NEW
        }
    }

    private func generateThumbnail() {
        CanvasThumbnailRenderer.generate(
            canvas: canvas, textElements: textElements,
            stickyNotes: stickyNotes, todoLists: todoLists,
            shapes: shapes, images: images, drawings: drawings,
            gridStyle: settings.effectiveGridStyle,
            backgroundMode: settings.canvasBackgroundMode,
            backgroundPalette: settings.canvasBackgroundPalette,
            context: context
        )
    }

    @ViewBuilder
    private var youtubePlaybackControl: some View {
        if let activeID = vm.youtubeVM.activePlayingID,
           let video = youtubeElements.first(where: { $0.id == activeID }) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.red)

                Text(video.title.isEmpty ? "YouTube playing" : video.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 180, alignment: .leading)

                Button {
                    vm.youtubeVM.requestStopPlayback(for: activeID)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.red, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(duration: 0.25), value: vm.youtubeVM.activePlayingID)
        }
    }

    private var connectModeIcon: String {
        if case .pickingTo = vm.connectorVM.connectState {
            return "point.topleft.down.to.point.bottomright.curvepath"
        }
        return "hand.tap"
    }

    private var connectModeHint: String {
        switch vm.connectorVM.connectState {
        case .pickingFrom: return "Tap an anchor dot on the source element"
        case .pickingTo:   return "Now tap an anchor dot on the target"
        case .inactive:    return ""
        }
    }

    @ViewBuilder
    private func pageBoundaryOverlay(geo: GeometryProxy) -> some View {
        let boundary = canvas.boundarySize
        let bW = boundary.width * vm.scale
        let bH = boundary.height * vm.scale
        let bX = vm.offset.width
        let bY = vm.offset.height
        if bX > 0 {
            Rectangle().fill(Color.primary.opacity(0.06))
                .frame(width: bX, height: geo.size.height)
                .position(x: bX/2, y: geo.size.height/2).allowsHitTesting(false)
        }
        let rightStart = bX + bW
        if rightStart < geo.size.width {
            Rectangle().fill(Color.primary.opacity(0.06))
                .frame(width: geo.size.width - rightStart, height: geo.size.height)
                .position(x: rightStart + (geo.size.width - rightStart)/2, y: geo.size.height/2)
                .allowsHitTesting(false)
        }
        if bY > 0 {
            Rectangle().fill(Color.primary.opacity(0.06))
                .frame(width: geo.size.width, height: bY)
                .position(x: geo.size.width/2, y: bY/2).allowsHitTesting(false)
        }
        let bottomStart = bY + bH
        if bottomStart < geo.size.height {
            Rectangle().fill(Color.primary.opacity(0.06))
                .frame(width: geo.size.width, height: geo.size.height - bottomStart)
                .position(x: geo.size.width/2, y: bottomStart + (geo.size.height - bottomStart)/2)
                .allowsHitTesting(false)
        }
        Rectangle().strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1.5)
            .frame(width: max(0, bW), height: max(0, bH))
            .position(x: bX + bW/2, y: bY + bH/2).allowsHitTesting(false)
        Text(canvas.canvasSize.displayName)
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accentColor.opacity(0.7))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.08), in: Capsule())
            .position(x: bX + 36, y: max(14, bY - 14)).allowsHitTesting(false)
    }

    @ViewBuilder
    private func renderElement(_ element: any LayerableElement) -> some View {
        let boundary       = canvas.boundarySize
        let multiSelect    = selection.isMultiSelectActive
        let isElemSelected = selection.isSelected(element.id)

        Group {
            if let text = element as? TextElementModel {
                TextElementView(element: text, canvasScale: vm.scale, canvasBoundary: boundary,
                                vm: vm.textVM, isMultiSelectMode: multiSelect,
                                isSelectedInMultiSelect: isElemSelected,
                                onExternalTap: { dismissEverything() },
                                isCanvasGestureActive: isCanvasGestureActive)
            } else if let sticky = element as? StickyNoteModel {
                StickyNoteView(note: sticky, canvasScale: vm.scale, canvasBoundary: boundary,
                               vm: vm.stickyVM, isMultiSelectMode: multiSelect,
                               isSelectedInMultiSelect: isElemSelected,
                               onExternalTap: { dismissEverything() },
                               isCanvasGestureActive: isCanvasGestureActive)
            } else if let todo = element as? TodoListModel {
                TodoListView(list: todo, allTasks: todoTasks, canvasScale: vm.scale,
                             canvasBoundary: boundary, vm: vm.todoVM,
                             isMultiSelectMode: multiSelect,
                             isSelectedInMultiSelect: isElemSelected,
                             onExternalTap: { dismissEverything() },
                             isCanvasGestureActive: isCanvasGestureActive)
            } else if let shape = element as? ShapeElementModel {
                ShapeElementView(shape: shape, canvasScale: vm.scale, canvasBoundary: boundary,
                                 vm: vm.shapeVM, isMultiSelectMode: multiSelect,
                                 isSelectedInMultiSelect: isElemSelected,
                                 onExternalTap: { dismissEverything() },
                                 isCanvasGestureActive: isCanvasGestureActive)
            } else if let img = element as? ImageElementModel {
                ImageElementView(element: img, canvasScale: vm.scale, canvasBoundary: boundary,
                                 vm: vm.imageVM, isMultiSelectMode: multiSelect,
                                 ocrTextZIndex: LayersViewModel.nextZ(among: allLayerableElements),
                                 undoManager: vm.undoManager,
                                 isSelectedInMultiSelect: isElemSelected,
                                 onExternalTap: { dismissEverything() },
                                 isCanvasGestureActive: isCanvasGestureActive)
            } else if let pdf = element as? PDFElementModel {
                PDFElementView(element: pdf, canvasScale: vm.scale, canvasBoundary: boundary,
                               vm: vm.pdfVM, isMultiSelectMode: multiSelect,
                               isSelectedInMultiSelect: isElemSelected,
                               onOpenReader: { openPDFElement = pdf; showPDFReader = true },
                               onExternalTap: { dismissEverything() },
                               isCanvasGestureActive: isCanvasGestureActive)
            } else if let table = element as? TableElementModel {
                TableElementView(
                    table: table, allCells: tableCells,
                    canvasScale: vm.scale, canvasBoundary: boundary,
                    vm: vm.tableVM, isMultiSelectMode: multiSelect,
                    isSelectedInMultiSelect: isElemSelected,
                    onImportCSV: { vm.pendingCSVTableID = table.id; vm.showTableCSVImporter = true },
                    onExportCSV: {
                        let cells = tableCells.filter { $0.tableID == table.id }
                        csvExportString = CSVService.export(cells: cells, rows: table.rowCount, cols: table.colCount)
                        csvExportFilename = "table_\(table.rowCount)x\(table.colCount)"
                        showCSVExporter = true
                    },
                    onExternalTap: { dismissEverything() },
                    onMultiSelectTap: { selection.toggle(table.id) },
                    isCanvasGestureActive: isCanvasGestureActive)
            } else if let audio = element as? AudioElementModel {
                AudioElementView(element: audio, canvasScale: vm.scale, canvasBoundary: boundary,
                                 vm: vm.audioVM, isMultiSelectMode: multiSelect,
                                 isSelectedInMultiSelect: isElemSelected,
                                 onExternalTap: { dismissEverything() },
                                 isCanvasGestureActive: isCanvasGestureActive)
            } else if let youtube = element as? YouTubeElementModel {
                YouTubeElementView(element: youtube, canvasScale: vm.scale, canvasBoundary: boundary,
                                   vm: vm.youtubeVM, isMultiSelectMode: multiSelect,
                                   isSelectedInMultiSelect: isElemSelected,
                                   onExternalTap: { dismissEverything() },
                                   isCanvasGestureActive: isCanvasGestureActive)
            } else if let drawing = element as? DrawingElementModel {
                DrawingElementView(element: drawing, canvasScale: vm.scale, canvasBoundary: boundary,
                                   vm: vm.drawingVM, isMultiSelectMode: multiSelect,
                                   isSelectedInMultiSelect: isElemSelected,
                                   onExternalTap: { dismissEverything() },
                                   isCanvasGestureActive: isCanvasGestureActive)
            } else if let symbol = element as? SymbolElementModel {
                // ── NEW ────────────────────────────────────────────────────────
                SymbolElementView(element: symbol, canvasScale: vm.scale, canvasBoundary: boundary,
                                  vm: vm.symbolVM, isMultiSelectMode: multiSelect,
                                  isSelectedInMultiSelect: isElemSelected,
                                  onExternalTap: { dismissEverything() },
                                  isCanvasGestureActive: isCanvasGestureActive)
            }
        }
        .opacity(layersVM.highlightedID == element.id ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.3), value: layersVM.highlightedID)
        .allowsHitTesting(!vm.showCanvasDrawingOverlay)
        .highPriorityGesture(
            multiSelect ? nil : LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    guard !isCanvasGestureActive else { return }
                    duplicateElement(element, offset: .zero)
                }
        )
        .highPriorityGesture(
            multiSelect ? TapGesture().onEnded {
                guard !isCanvasGestureActive else { return }
                selection.toggle(element.id)
            } : nil
        )
    }

    @ViewBuilder
    private func toolbarLayer(geo: GeometryProxy) -> some View {
        let connectActive = vm.connectorVM.isConnectModeActive
        switch settings.toolbarPosition {
        case .hidden: EmptyView()
        case .bottom:
            VStack {
                Spacer()
                CanvasToolbar(
                    showTextSheet:  $vm.showTextSheet,
                    onAddSticky:    { addStickyAtCenter(viewportSize: geo.size) },
                    onAddTodo:      { addTodoAtCenter(viewportSize: geo.size) },
                    onAddShape:     { openShapePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddImage:     { openImagePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onScanOCR:      { openOCRScanner(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onScanDocument: { openDocumentScanner(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddPDF:       { openPDFPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddTable:     { openTableSizePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddAudio:     { openAudioPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddYouTube:   { openYouTubeLinkSheet(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddDrawing:   { addDrawingAtCenter(viewportSize: geo.size) },
                    onDrawOnCanvas: { startCanvasDrawing() },
                    onAddSymbol:    { openSymbolPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },  // ← NEW
                    onConnect:      { toggleConnectMode() },
                    isConnectModeActive: connectActive, isVertical: false
                )
            }
        case .left:
            HStack {
                CanvasToolbar(
                    showTextSheet:  $vm.showTextSheet,
                    onAddSticky:    { addStickyAtCenter(viewportSize: geo.size) },
                    onAddTodo:      { addTodoAtCenter(viewportSize: geo.size) },
                    onAddShape:     { openShapePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddImage:     { openImagePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onScanOCR:      { openOCRScanner(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onScanDocument: { openDocumentScanner(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddPDF:       { openPDFPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddTable:     { openTableSizePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddAudio:     { openAudioPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddYouTube:   { openYouTubeLinkSheet(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddDrawing:   { addDrawingAtCenter(viewportSize: geo.size) },
                    onDrawOnCanvas: { startCanvasDrawing() },
                    onAddSymbol:    { openSymbolPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },  // ← NEW
                    onConnect:      { toggleConnectMode() },
                    isConnectModeActive: connectActive, isVertical: true
                )
                .padding(.leading, 16)
                Spacer()
            }
        case .right:
            HStack {
                Spacer()
                CanvasToolbar(
                    showTextSheet:  $vm.showTextSheet,
                    onAddSticky:    { addStickyAtCenter(viewportSize: geo.size) },
                    onAddTodo:      { addTodoAtCenter(viewportSize: geo.size) },
                    onAddShape:     { openShapePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddImage:     { openImagePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onScanOCR:      { openOCRScanner(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onScanDocument: { openDocumentScanner(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddPDF:       { openPDFPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddTable:     { openTableSizePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddAudio:     { openAudioPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddYouTube:   { openYouTubeLinkSheet(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddDrawing:   { addDrawingAtCenter(viewportSize: geo.size) },
                    onDrawOnCanvas: { startCanvasDrawing() },
                    onAddSymbol:    { openSymbolPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },  // ← NEW
                    onConnect:      { toggleConnectMode() },
                    isConnectModeActive: connectActive, isVertical: true
                )
                .padding(.trailing, 16)
            }
        }
    }

    private func toggleConnectMode() {
        if vm.connectorVM.isConnectModeActive {
            vm.connectorVM.exitConnectMode()
        } else {
            dismissEverything()
            vm.connectorVM.enterConnectMode()
        }
    }

    private func dismissEverything() {
        stackPicker = nil
        if let inlineID = vm.textVM.inlineEditingID,
           let el = textElements.first(where: { $0.id == inlineID }),
           el.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.delete(el)
            try? context.save()
        }
        vm.textVM.stopEditing()
        vm.stickyVM.stopEditing(); vm.todoVM.stopEditing()
        vm.shapeVM.stopEditing(); vm.imageVM.stopEditing(); vm.pdfVM.stopEditing()
        vm.tableVM.stopAll(); vm.audioVM.stopEditing(); vm.youtubeVM.stopEditing(); vm.drawingVM.stopEditing()
        vm.connectorVM.stopEditing(); vm.symbolVM.stopEditing()  // ← NEW
        vm.hideAddMenu()
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        #endif
    }

    private func selectElement(id: UUID) {
        dismissEverything()
        if      textElements.contains(where:   { $0.id == id }) { vm.textVM.editingID = id }
        else if stickyNotes.contains(where:    { $0.id == id }) { vm.stickyVM.editingID = id }
        else if todoLists.contains(where:      { $0.id == id }) { vm.todoVM.editingID = id }
        else if shapes.contains(where:         { $0.id == id }) { vm.shapeVM.editingID = id }
        else if images.contains(where:         { $0.id == id }) { vm.imageVM.editingID = id }
        else if pdfs.contains(where:           { $0.id == id }) { vm.pdfVM.editingID = id }
        else if tables.contains(where:         { $0.id == id }) { vm.tableVM.selectTable(id: id) }
        else if audioElements.contains(where:  { $0.id == id }) { vm.audioVM.editingID = id }
        else if youtubeElements.contains(where:{ $0.id == id }) { vm.youtubeVM.editingID = id }
        else if drawings.contains(where:       { $0.id == id }) {
            vm.drawingVM.editingID = id; vm.drawingVM.isDrawingModeActive = false
        }
        else if symbols.contains(where:        { $0.id == id }) { vm.symbolVM.editingID = id }  // ← NEW
    }

    private func addStickyAtCenter(viewportSize: CGSize) {
        dismissEverything()
        vm.stickyVM.addNote(canvasID: canvas.id,
                            center: CGPoint(x: viewportSize.width/2, y: viewportSize.height/2),
                            offset: vm.offset, scale: vm.scale,
                            zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                            context: context, undoManager: vm.undoManager)
    }
    private func addTodoAtCenter(viewportSize: CGSize) {
        dismissEverything()
        vm.todoVM.addList(canvasID: canvas.id,
                          center: CGPoint(x: viewportSize.width/2, y: viewportSize.height/2),
                          offset: vm.offset, scale: vm.scale,
                          zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                          context: context, undoManager: vm.undoManager)
    }
    private func addDrawingAtCenter(viewportSize: CGSize) {
        dismissEverything()
        vm.drawingVM.addDrawing(canvasID: canvas.id,
                                center: CGPoint(x: viewportSize.width/2, y: viewportSize.height/2),
                                offset: vm.offset, scale: vm.scale,
                                zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                                context: context, undoManager: vm.undoManager)
    }
    private func openShapePicker(at point: CGPoint) {
        dismissEverything(); vm.pendingShapeLocation = point; vm.showShapePicker = true
    }
    // ← NEW
    private func openSymbolPicker(at point: CGPoint) {
        dismissEverything(); vm.pendingSymbolLocation = point; vm.showSymbolPicker = true
    }
    private func openImagePicker(at point: CGPoint) {
        dismissEverything(); vm.pendingImageLocation = point
        #if os(iOS)
        if UIImagePickerController.isSourceTypeAvailable(.camera) { vm.showImageSourcePicker = true }
        else { vm.showImagePicker = true }
        #else
        vm.showImagePicker = true
        #endif
    }
    private func openOCRScanner(at point: CGPoint) {
        dismissEverything()
        #if os(iOS)
        guard VNDocumentCameraViewController.isSupported else {
            ocrScanAlertMessage = "Document scanning is not available on this device."
            return
        }
        vm.pendingOCRLocation = point
        vm.showOCRScanner = true
        #else
        ocrScanAlertMessage = "Document scanning is available on iPhone and iPad."
        #endif
    }
    private func openDocumentScanner(at point: CGPoint) {
        dismissEverything()
        #if os(iOS)
        guard VNDocumentCameraViewController.isSupported else {
            ocrScanAlertMessage = "Document scanning is not available on this device."
            return
        }
        vm.pendingDocumentScanLocation = point
        vm.showDocumentScanner = true
        #else
        ocrScanAlertMessage = "Document scanning is available on iPhone and iPad."
        #endif
    }
    private func openPDFPicker(at point: CGPoint) {
        vm.pendingPDFLocation = point
        #if canImport(AppKit)
        openMacOSPDFPicker { url in
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let center = vm.pendingPDFLocation ?? CGPoint(x: 300, y: 400)
            vm.pdfVM.addPDF(canvasID: canvas.id, sourceURL: url, center: center,
                           offset: vm.offset, scale: vm.scale,
                           zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                           context: context, undoManager: vm.undoManager)
            vm.pendingPDFLocation = nil
        }
        #else
        showPDFImporter = true
        #endif
    }
    private func openTableSizePicker(at point: CGPoint) {
        dismissEverything(); vm.pendingTableLocation = point; showTableSizePicker = true
    }
    private func openAudioPicker(at point: CGPoint) {
        dismissEverything(); vm.pendingAudioLocation = point; vm.showAudioPicker = true
    }
    private func openYouTubeLinkSheet(at point: CGPoint) {
        dismissEverything(); vm.pendingYouTubeLocation = point; vm.showYouTubeLinkSheet = true
    }

    private func handleToolSelection(_ tool: CanvasTool, at screenPoint: CGPoint, geo: GeometryProxy) {
        vm.hideAddMenu(); lastMenuLocation = screenPoint
        let nextZ = LayersViewModel.nextZ(among: allLayerableElements)
        switch tool {
        case .text: vm.showTextSheet = true
        case .stickyNote:
            vm.stickyVM.addNote(canvasID: canvas.id, center: screenPoint,
                               offset: vm.offset, scale: vm.scale, zIndex: nextZ,
                               context: context, undoManager: vm.undoManager)
        case .todoList:
            vm.todoVM.addList(canvasID: canvas.id, center: screenPoint,
                             offset: vm.offset, scale: vm.scale, zIndex: nextZ,
                             context: context, undoManager: vm.undoManager)
        case .shape: openShapePicker(at: screenPoint)
        case .image: openImagePicker(at: screenPoint)
        case .ocrScan: openOCRScanner(at: screenPoint)
        case .documentScan: openDocumentScanner(at: screenPoint)
        case .pdf:   openPDFPicker(at: screenPoint)
        case .table: openTableSizePicker(at: screenPoint)
        case .audio: openAudioPicker(at: screenPoint)
        case .youtube: openYouTubeLinkSheet(at: screenPoint)
        case .drawing:
            dismissEverything()
            vm.drawingVM.addDrawing(canvasID: canvas.id, center: screenPoint,
                                   offset: vm.offset, scale: vm.scale, zIndex: nextZ,
                                   context: context, undoManager: vm.undoManager)
        }
    }

    #if os(iOS)
    private func createOCRTextFromScan(images: [UIImage], geo: GeometryProxy) {
        guard !images.isEmpty else {
            vm.pendingOCRLocation = nil
            ocrScanAlertMessage = "No scanned pages were found."
            return
        }

        isProcessingOCRScan = true
        Task {
            do {
                let text = try await ImageOCRService.recognizeText(images: images)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    isProcessingOCRScan = false
                    vm.pendingOCRLocation = nil
                    ocrScanAlertMessage = "No readable text was found in this scan."
                    return
                }

                let screenPoint = vm.pendingOCRLocation ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let canvasPoint = CGPoint(
                    x: (screenPoint.x - vm.offset.width) / vm.scale,
                    y: (screenPoint.y - vm.offset.height) / vm.scale
                )
                dismissEverything()
                let textID = vm.textVM.addOCRText(
                    canvasID: canvas.id,
                    text: trimmed,
                    canvasPoint: canvasPoint,
                    zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                    context: context,
                    undoManager: vm.undoManager
                )
                vm.pendingOCRLocation = nil
                isProcessingOCRScan = false
                if let textID {
                    vm.textVM.editingID = textID
                }
            } catch {
                isProcessingOCRScan = false
                vm.pendingOCRLocation = nil
                ocrScanAlertMessage = "Could not extract text from this scan."
            }
        }
    }

    private func createDocumentFromScan(images: [UIImage], geo: GeometryProxy) {
        guard !images.isEmpty else {
            vm.pendingDocumentScanLocation = nil
            ocrScanAlertMessage = "No scanned pages were found."
            return
        }

        isProcessingDocumentScan = true
        Task {
            let screenPoint = vm.pendingDocumentScanLocation ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            dismissEverything()
            let documentID = vm.pdfVM.addScannedDocument(
                canvasID: canvas.id,
                images: images,
                center: screenPoint,
                offset: vm.offset,
                scale: vm.scale,
                zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                context: context,
                undoManager: vm.undoManager
            )
            vm.pendingDocumentScanLocation = nil
            isProcessingDocumentScan = false
            if let documentID {
                vm.pdfVM.editingID = documentID
            } else {
                ocrScanAlertMessage = "Could not place this scan on the canvas."
            }
        }
    }
    #endif

    private func duplicateSelected() {
        var z = LayersViewModel.nextZ(among: allLayerableElements)
        for id in selection.selectedIDs {
            if let element = layerableElement(withID: id) {
                duplicateElement(element, zIndex: z, selectCopy: false)
            }
            z += 1
        }
        withAnimation(.spring(duration: 0.3)) { selection.exit() }
    }

    @discardableResult
    private func duplicateElement(_ element: any LayerableElement,
                                  zIndex: Int? = nil,
                                  offset: CGSize = CGSize(width: 30, height: 30),
                                  selectCopy: Bool = true) -> UUID? {
        guard !vm.showCanvasDrawingOverlay,
              !vm.connectorVM.isConnectModeActive else { return nil }

        if selectCopy { dismissEverything() }

        let z = zIndex ?? LayersViewModel.nextZ(among: allLayerableElements)
        var duplicatedID: UUID?
        if let el = element as? TextElementModel {
            duplicatedID = vm.textVM.duplicate(element: el, zIndex: z, offset: offset, context: context, undoManager: vm.undoManager)
            if let duplicatedID, selectCopy {
                vm.textVM.editingID = duplicatedID
            }
        } else if let el = element as? StickyNoteModel {
            duplicatedID = vm.stickyVM.duplicate(note: el, zIndex: z, offset: offset, context: context, undoManager: vm.undoManager)
            if let duplicatedID, selectCopy {
                vm.stickyVM.editingID = duplicatedID
            }
        } else if let el = element as? TodoListModel {
            duplicatedID = vm.todoVM.duplicate(list: el, zIndex: z, offset: offset, context: context, undoManager: vm.undoManager)
            if let duplicatedID, selectCopy {
                vm.todoVM.editingID = duplicatedID
            }
        } else if let el = element as? ShapeElementModel {
            duplicatedID = vm.shapeVM.duplicate(shape: el, zIndex: z, offset: offset, context: context, undoManager: vm.undoManager)
            if let duplicatedID, selectCopy {
                vm.shapeVM.editingID = duplicatedID
            }
        } else if let el = element as? ImageElementModel {
            duplicatedID = vm.imageVM.duplicate(element: el, zIndex: z, offset: offset, context: context, undoManager: vm.undoManager)
            if let duplicatedID, selectCopy {
                vm.imageVM.editingID = duplicatedID
            }
        } else if let el = element as? PDFElementModel {
            duplicatedID = vm.pdfVM.duplicate(element: el, zIndex: z, offset: offset, context: context, undoManager: vm.undoManager)
            if let duplicatedID, selectCopy {
                vm.pdfVM.editingID = duplicatedID
            }
        } else if let el = element as? TableElementModel {
            duplicatedID = vm.tableVM.duplicate(table: el, cells: tableCells, zIndex: z, offset: offset, context: context, undoManager: vm.undoManager)
            if let duplicatedID, selectCopy {
                vm.tableVM.selectTable(id: duplicatedID)
            }
        } else if let el = element as? AudioElementModel {
            duplicatedID = vm.audioVM.duplicate(element: el, zIndex: z, offset: offset, context: context, undoManager: vm.undoManager)
            if let duplicatedID, selectCopy {
                vm.audioVM.editingID = duplicatedID
            }
        } else if let el = element as? YouTubeElementModel {
            duplicatedID = vm.youtubeVM.duplicate(element: el, zIndex: z, offset: offset, context: context, undoManager: vm.undoManager)
            if let duplicatedID, selectCopy {
                vm.youtubeVM.editingID = duplicatedID
            }
        } else if let el = element as? DrawingElementModel {
            duplicatedID = vm.drawingVM.duplicate(element: el, zIndex: z, offset: offset, context: context, undoManager: vm.undoManager)
            if let duplicatedID, selectCopy {
                vm.drawingVM.editingID = duplicatedID
                vm.drawingVM.isDrawingModeActive = false
            }
        } else if let el = element as? SymbolElementModel {
            duplicatedID = vm.symbolVM.duplicate(element: el, zIndex: z, offset: offset, context: context, undoManager: vm.undoManager)
            if let duplicatedID, selectCopy {
                vm.symbolVM.editingID = duplicatedID
            }
        }
        return duplicatedID
    }

    private func layerableElement(withID id: UUID) -> (any LayerableElement)? {
        allLayerableElements.first { $0.id == id }
    }

    private func deleteSelected() {
        for id in selection.selectedIDs {
            if let el = textElements.first(where:       { $0.id == id }) { vm.textVM.delete(element: el, context: context, undoManager: vm.undoManager); vm.connectorVM.deleteOrphanedConnectors(for: id, allConnectors: connectors, context: context) }
            else if let el = stickyNotes.first(where:   { $0.id == id }) { vm.stickyVM.delete(note: el, context: context, undoManager: vm.undoManager); vm.connectorVM.deleteOrphanedConnectors(for: id, allConnectors: connectors, context: context) }
            else if let el = todoLists.first(where:     { $0.id == id }) { vm.todoVM.delete(list: el, tasks: todoTasks.filter { $0.listID == el.id }, context: context, undoManager: vm.undoManager); vm.connectorVM.deleteOrphanedConnectors(for: id, allConnectors: connectors, context: context) }
            else if let el = shapes.first(where:        { $0.id == id }) { vm.shapeVM.delete(shape: el, context: context, undoManager: vm.undoManager); vm.connectorVM.deleteOrphanedConnectors(for: id, allConnectors: connectors, context: context) }
            else if let el = images.first(where:        { $0.id == id }) { vm.imageVM.delete(element: el, context: context, undoManager: vm.undoManager); vm.connectorVM.deleteOrphanedConnectors(for: id, allConnectors: connectors, context: context) }
            else if let el = pdfs.first(where:          { $0.id == id }) { vm.pdfVM.delete(element: el, context: context, undoManager: vm.undoManager); vm.connectorVM.deleteOrphanedConnectors(for: id, allConnectors: connectors, context: context) }
            else if let el = tables.first(where:        { $0.id == id }) { vm.tableVM.delete(table: el, cells: tableCells.filter { $0.tableID == el.id }, context: context, undoManager: vm.undoManager); vm.connectorVM.deleteOrphanedConnectors(for: id, allConnectors: connectors, context: context) }
            else if let el = audioElements.first(where: { $0.id == id }) { vm.audioVM.delete(element: el, context: context, undoManager: vm.undoManager); vm.connectorVM.deleteOrphanedConnectors(for: id, allConnectors: connectors, context: context) }
            else if let el = youtubeElements.first(where: { $0.id == id }) { vm.youtubeVM.delete(element: el, context: context, undoManager: vm.undoManager); vm.connectorVM.deleteOrphanedConnectors(for: id, allConnectors: connectors, context: context) }
            else if let el = drawings.first(where:      { $0.id == id }) { vm.drawingVM.delete(element: el, context: context, undoManager: vm.undoManager); vm.connectorVM.deleteOrphanedConnectors(for: id, allConnectors: connectors, context: context) }
            else if let el = symbols.first(where:       { $0.id == id }) { vm.symbolVM.delete(element: el, context: context, undoManager: vm.undoManager); vm.connectorVM.deleteOrphanedConnectors(for: id, allConnectors: connectors, context: context) }  // ← NEW
        }
        withAnimation(.spring(duration: 0.3)) { selection.exit() }
    }
}

private extension ElementBounds {
    func contains(canvasPoint point: CGPoint, hitSlop: CGFloat) -> Bool {
        let rect = CGRect(
            x: CGFloat(cx - width / 2),
            y: CGFloat(cy - height / 2),
            width: CGFloat(width),
            height: CGFloat(height)
        )
        return rect.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point)
    }
}

struct CSVShareSheet: View {
    let csvString: String
    let filename: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export CSV").font(.title3.weight(.bold)); Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2)
                        .foregroundStyle(.secondary).symbolRenderingMode(.hierarchical)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)
            Divider()
            VStack(spacing: 16) {
                Image(systemName: "tablecells").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.indigo)
                Text("\(filename).csv").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                ShareLink(item: csvString, subject: Text(filename), message: Text("Exported from Canvio"),
                          preview: SharePreview("\(filename).csv", image: Image(systemName: "tablecells"))) {
                    Text("Share CSV").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 14).background(Color.accentColor).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }.padding(.horizontal, 24)
            }.padding(.vertical, 24)
        }
    }
}
