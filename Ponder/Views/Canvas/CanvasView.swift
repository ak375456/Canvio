import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import PencilKit
#if os(iOS)
import Vision
import VisionKit
#endif

private let canvasViewportCoordinateSpace = "CanvasViewport"
private let freeMediaElementLimit = 2
private let freePageLimitPerCanvas = 2

private enum PendingProPageAction {
    case add(viewportSize: CGSize)
    case newSameSize(pageID: UUID, viewportSize: CGSize)
}

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

#if os(iOS)
private struct HandwritingRecognitionResult {
    let text: String
    let confidence: Float
}
#endif

private enum CanvasDrawingCaptureMode {
    case drawing
    case handwritingText
}

private struct CanvasExportSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export Canvas")
                        .font(.title3.weight(.bold))
                    Text("Save the canvas as PNG or PDF.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close export")
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("SAVE AS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                content
            }
            .padding(24)
        }
    }
}

struct CanvasView: View {
    let canvas: CanvasModel
    var onDelete: () -> Void
    var onRename: (String) -> Void

    @EnvironmentObject private var settings: AppSettings
    @StateObject private var vm = CanvasViewModel()
    @ObservedObject private var pro = ProManager.shared
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
    @Query private var allSymbols: [SymbolElementModel]
    @Query private var allElementGroups: [CanvasElementGroupModel]
    @Query private var allCanvasPages: [CanvasPageModel]

    @State private var showDeleteAlert = false
    @State private var showRenameAlert = false
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var showExportSheet = false
    @State private var showLayers = false
    @State private var showPagesPanel = true
    @State private var showPDFReader = false
    @State private var showTableSizePicker = false
    @State private var showCSVExporter = false
    @State private var csvExportString = ""
    @State private var csvExportFilename = "table"
    @State private var stackPicker: CanvasStackPickerState?
    @State private var newName: String = ""
    @State private var selectedPageID: UUID?
    @State private var pendingProPageAction: PendingProPageAction?
    @State private var pageForRename: CanvasPageModel?
    @State private var pageRenameText = ""
    @State private var pagePendingDeletion: CanvasPageModel?
    @State private var lastMenuLocation: CGPoint? = nil
    @State private var openPDFElement: PDFElementModel? = nil
    @State private var showPDFImporter = false
    @State private var drawingStartScale:  CGFloat = 1.0
    @State private var drawingStartOffset: CGSize  = .zero
    @State private var canvasDrawingInitialDrawing = PKDrawing()
    @State private var canvasDrawingCaptureMode: CanvasDrawingCaptureMode = .drawing
    @State private var continuingCanvasDrawingID: UUID?
    @State private var isCanvasDrawingInputActive = true
    @State private var isCanvasGestureActive = false
    @State private var canvasGestureSuppressionID = UUID()
    @State private var selectedGroupID: UUID?
    @State private var draggingGroupID: UUID?
    @State private var groupDragOffset: CGSize = .zero
    @State private var isProcessingOCRScan = false
    @State private var isProcessingDocumentScan = false
    @State private var ocrScanAlertMessage: String?
    #if os(iOS)
    @State private var keyboardAvoidanceOffset: CGFloat = 0
    #endif

    @Environment(\.dismiss) private var dismiss

    private var activeContentCanvasID: UUID {
        activePage?.resolvedContentCanvasID ?? canvas.id
    }

    private var textElements: [TextElementModel]   { allTextElements.filter { $0.canvasID == activeContentCanvasID } }
    private var stickyNotes: [StickyNoteModel]     { allStickyNotes.filter  { $0.canvasID == activeContentCanvasID } }
    private var todoLists: [TodoListModel]          { allTodoLists.filter    { $0.canvasID == activeContentCanvasID } }
    private var todoTasks: [TodoTaskModel] {
        let ids = Set(todoLists.map { $0.id })
        return allTodoTasks.filter { ids.contains($0.listID) }
    }
    private var shapes: [ShapeElementModel]         { allShapes.filter       { $0.canvasID == activeContentCanvasID } }
    private var images: [ImageElementModel]         { allImages.filter       { $0.canvasID == activeContentCanvasID } }
    private var pdfs: [PDFElementModel]             { allPDFs.filter         { $0.canvasID == activeContentCanvasID } }
    private var tables: [TableElementModel]         { allTables.filter       { $0.canvasID == activeContentCanvasID } }
    private var tableCells: [TableCellModel] {
        let ids = Set(tables.map { $0.id })
        return allTableCells.filter { ids.contains($0.tableID) }
    }
    private var audioElements: [AudioElementModel] { allAudio.filter        { $0.canvasID == activeContentCanvasID } }
    private var youtubeElements: [YouTubeElementModel] { allYouTube.filter  { $0.canvasID == activeContentCanvasID } }
    private var drawings: [DrawingElementModel]    { allDrawings.filter     { $0.canvasID == activeContentCanvasID } }
    private var connectors: [ConnectorModel]       { allConnectors.filter   { $0.canvasID == activeContentCanvasID } }
    private var symbols: [SymbolElementModel]      { allSymbols.filter      { $0.canvasID == activeContentCanvasID } }
    private var elementGroups: [CanvasElementGroupModel] {
        allElementGroups.filter { $0.canvasID == activeContentCanvasID }
    }
    private var canvasPages: [CanvasPageModel] {
        allCanvasPages
            .filter { $0.canvasID == canvas.id }
            .sorted {
                if $0.orderIndex == $1.orderIndex { return $0.createdAt < $1.createdAt }
                return $0.orderIndex < $1.orderIndex
            }
    }

    private var activePage: CanvasPageModel? {
        if let selectedPageID,
           let page = canvasPages.first(where: { $0.id == selectedPageID }) {
            return page
        }
        return canvasPages.first
    }

    private var canCreateAdditionalPage: Bool {
        pro.isPro || canvasPages.count < freePageLimitPerCanvas
    }

    private var areAdditionalPagesLocked: Bool {
        !pro.isPro && canvasPages.count >= freePageLimitPerCanvas
    }

    private var canvasNavigationBoundary: CGSize {
        canvas.boundarySize
    }

    private var elementInteractionBoundary: CGSize {
        canvas.isInfinite ? .zero : canvasNavigationBoundary
    }

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

    private var lockedCanvasTools: Set<CanvasTool> {
        guard !pro.isPro else { return [] }
        var tools = Set<CanvasTool>()
        if images.count >= freeMediaElementLimit { tools.insert(.image) }
        if tables.count >= freeMediaElementLimit { tools.insert(.table) }
        if audioElements.count >= freeMediaElementLimit { tools.insert(.audio) }
        return tools
    }

    private var lockedTemplateIDs: Set<String> {
        guard !pro.isPro else { return [] }
        return Set(
            CanvasTemplateService.templates
                .filter { template in
                    template.tableCount > 0
                    && tables.count + template.tableCount > freeMediaElementLimit
                }
                .map(\.id)
        )
    }

    private var sortedElements: [any LayerableElement] {
        allLayerableElements.sorted { $0.zIndex < $1.zIndex }
    }

    private var boundsMap: [UUID: ElementBounds] {
        var map: [UUID: ElementBounds] = [:]
        for element in allLayerableElements {
            map[element.id] = elementBounds(for: element)
        }
        return map
    }

    private var alwaysRenderedElementIDs: Set<UUID> {
        var ids = selection.selectedIDs
        if let activeSelectedElementID {
            ids.insert(activeSelectedElementID)
        }
        if let selectedGroupID {
            ids.formUnion(groupMembers(for: selectedGroupID).map(\.id))
        }
        if let draggingGroupID {
            ids.formUnion(groupMembers(for: draggingGroupID).map(\.id))
        }
        if case .pickingTo(let fromID, _, _) = vm.connectorVM.connectState {
            ids.insert(fromID)
        }
        return ids
    }

    private func visibleSortedElements(viewportSize: CGSize) -> [any LayerableElement] {
        let viewportRect = visibleCanvasRect(viewportSize: viewportSize)
        let pinnedIDs = alwaysRenderedElementIDs

        return allLayerableElements.filter { element in
            pinnedIDs.contains(element.id)
            || elementBounds(for: element).intersects(canvasRect: viewportRect)
        }
        .sorted { $0.zIndex < $1.zIndex }
    }

    private func visibleCanvasRect(viewportSize: CGSize) -> CGRect {
        guard vm.scale > 0, viewportSize.width > 0, viewportSize.height > 0 else {
            return CGRect(origin: .zero, size: viewportSize)
        }

        let width = viewportSize.width / vm.scale
        let height = viewportSize.height / vm.scale
        let rect = CGRect(
            x: -vm.offset.width / vm.scale,
            y: -vm.offset.height / vm.scale,
            width: width,
            height: height
        )

        let padX = max(220, width * 0.85)
        let padY = max(220, height * 0.85)
        return rect.insetBy(dx: -padX, dy: -padY)
    }

    private func elementBounds(for element: any LayerableElement) -> ElementBounds {
        if let text = element as? TextElementModel {
            let lines = text.text.split(separator: "\n", omittingEmptySubsequences: false)
            let longestLine = lines.map(\.count).max() ?? 4
            let width = max(160, min(1200, Double(longestLine) * Double(text.fontSize) * 0.62 + 32))
            let height = max(40, Double(max(lines.count, 1)) * Double(text.fontSize) * 1.35 + 24)
            return ElementBounds(id: text.id, cx: text.x, cy: text.y, width: width, height: height)
        } else if let sticky = element as? StickyNoteModel {
            return ElementBounds(id: sticky.id, cx: sticky.x, cy: sticky.y, width: sticky.width, height: sticky.height)
        } else if let todo = element as? TodoListModel {
            return ElementBounds(id: todo.id, cx: todo.x, cy: todo.y, width: todo.width, height: todo.height)
        } else if let shape = element as? ShapeElementModel {
            return ElementBounds(id: shape.id, cx: shape.x, cy: shape.y, width: shape.width, height: shape.height)
        } else if let image = element as? ImageElementModel {
            return ElementBounds(id: image.id, cx: image.x, cy: image.y, width: image.width, height: image.height)
        } else if let pdf = element as? PDFElementModel {
            return ElementBounds(id: pdf.id, cx: pdf.x, cy: pdf.y, width: pdf.width, height: pdf.height)
        } else if let table = element as? TableElementModel {
            return ElementBounds(id: table.id, cx: table.x, cy: table.y, width: table.totalWidth, height: table.totalHeight)
        } else if let audio = element as? AudioElementModel {
            return ElementBounds(id: audio.id, cx: audio.x, cy: audio.y, width: audio.width, height: audio.height)
        } else if let youtube = element as? YouTubeElementModel {
            return ElementBounds(id: youtube.id, cx: youtube.x, cy: youtube.y, width: youtube.width, height: youtube.height)
        } else if let drawing = element as? DrawingElementModel {
            return ElementBounds(id: drawing.id, cx: drawing.x, cy: drawing.y, width: drawing.width, height: drawing.height)
        } else if let symbol = element as? SymbolElementModel {
            let size = symbol.fontSize + 24
            return ElementBounds(id: symbol.id, cx: symbol.x, cy: symbol.y, width: size, height: size)
        }

        return ElementBounds(id: element.id, cx: 0, cy: 0, width: 80, height: 80)
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
        if let selectedGroupID,
           let bounds = groupBounds(for: selectedGroupID) {
            return screenRect(for: bounds)
                .insetBy(dx: -44, dy: -80)
        }

        guard let id = activeSelectedElementID,
              let bounds = boundsMap[id] else { return nil }

        return screenRect(for: bounds.rect)
            .insetBy(dx: -44, dy: -80)
    }

    private var selectedGroupForUngroup: UUID? {
        let selectedElements = selection.selectedIDs.compactMap { layerableElement(withID: $0) }
        guard selectedElements.count == selection.count,
              !selectedElements.isEmpty,
              selectedElements.allSatisfy({ $0.groupID != nil }) else { return nil }
        let groupIDs = Set(selectedElements.compactMap(\.groupID))
        return groupIDs.count == 1 ? groupIDs.first : nil
    }

    private var canUseGroupAction: Bool {
        selectedGroupForUngroup != nil || selection.count >= 2
    }

    private var groupActionTitle: String {
        selectedGroupForUngroup == nil ? "Group" : "Ungroup"
    }

    private var groupActionIcon: String {
        selectedGroupForUngroup == nil ? "square.stack.3d.up.fill" : "square.stack.3d.down.right"
    }

    init(canvas: CanvasModel, onDelete: @escaping () -> Void, onRename: @escaping (String) -> Void) {
        self.canvas   = canvas
        self.onDelete = onDelete
        self.onRename = onRename
        self._selection = ObservedObject(wrappedValue: SelectionViewModel())
    }

    var body: some View {
        canvasAlerts(
            canvasDocumentSheets(
                canvasNavigation(canvasReader)
            )
        )
    }

    private var canvasReader: some View {
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
                                    canvasID: activeContentCanvasID,
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

                canvasElementsSurface(geo: geo)

                #if os(iOS)
                CanvasGestureBridge(
                    isEnabled: !vm.showCanvasDrawingOverlay || !isCanvasDrawingInputActive,
                    selectedElementFrame: selectedElementGestureFrame,
                    onPanBegan: {
                        beginCanvasGestureSuppression()
                        vm.lastOffset = vm.offset
                    },
                    onPanChanged: { translation in
                        vm.offset = CGSize(
                            width: vm.lastOffset.width + translation.width,
                            height: vm.lastOffset.height + translation.height
                        )
                    },
                    onPanEnded: {
                        vm.handleDragEnd()
                        if !canvas.isInfinite {
                            vm.clampOffset(to: canvasNavigationBoundary, viewportSize: geo.size, scale: vm.scale)
                        }
                        endCanvasGestureSuppression()
                    },
                    onPinchBegan: {
                        beginCanvasGestureSuppression()
                        vm.lastScale = vm.scale
                        vm.lastOffset = vm.offset
                    },
                    onPinchChanged: { magnification, focal in
                        vm.handleMagnification(magnification, focalPoint: focal)
                    },
                    onPinchEnded: {
                        vm.handleMagnificationEnd()
                        if !canvas.isInfinite {
                            vm.clampOffset(to: canvasNavigationBoundary, viewportSize: geo.size, scale: vm.scale)
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

                if !vm.showCanvasDrawingOverlay {
                    pagesPanelLayer(geo: geo)
                }

                if vm.connectorVM.isConnectModeActive {
                    connectModeOverlay
                }

                if selection.isMultiSelectActive {
                    multiSelectOverlay
                }

                if let picker = stackPicker {
                    stackPickerOverlay(picker)
                }

                if isProcessingOCRScan || isProcessingDocumentScan {
                    processingOverlay
                }

                if let pos = vm.addMenuPosition {
                    addMenuOverlay(at: pos)
                }

                if vm.showCanvasDrawingOverlay {
                    canvasDrawingOverlayLayer
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
                            vm.clampOffset(to: canvasNavigationBoundary, viewportSize: geo.size, scale: vm.scale)
                        }
                    } else {
                        vm.offset = CGSize(width: vm.offset.width + deltaX, height: vm.offset.height + deltaY)
                        vm.lastOffset = vm.offset
                        if !canvas.isInfinite {
                            vm.clampOffset(to: canvasNavigationBoundary, viewportSize: geo.size, scale: vm.scale)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            )
            #endif
            .onAppear {
                let initialPage = ensureDefaultPage()
                if selectedPageID == nil {
                    selectedPageID = (initialPage ?? canvasPages.first)?.id
                }
                if !canvas.isInfinite,
                   let page = initialPage ?? activePage {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusPage(page, viewportSize: geo.size, animated: false)
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
            .onChange(of: selectedPageID) { _, _ in
                dismissEverything()
                pullCurrentPageContent()
            }
            .onReceive(NotificationCenter.default.publisher(for: .ocrCreatedTextElement)) { notification in
                guard let textID = notification.object as? UUID else { return }
                dismissEverything()
                vm.textVM.editingID = textID
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification)) { notif in
                handleKeyboardWillShow(notif, viewportSize: geo.size,
                                       safeBottom: geo.safeAreaInsets.bottom)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification)) { notif in
                handleKeyboardWillHide(notif)
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
                        isExpanded: $vm.isMinimapExpanded,
                        isNavigationActive: isCanvasGestureActive
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
                        canvasID: activeContentCanvasID, style: style,
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
                    vm.shapeVM.addShape(canvasID: activeContentCanvasID, kind: kind, center: point,
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
                        canvasID: activeContentCanvasID, symbolName: symbolName,
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
                    vm.tableVM.addTable(canvasID: activeContentCanvasID, rows: rows, cols: cols, center: point,
                                       offset: vm.offset, scale: vm.scale,
                                       zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                                       context: context, undoManager: vm.undoManager)
                    vm.pendingTableLocation = nil
                }
                .presentationDetents([.height(600)]).presentationDragIndicator(.visible).presentationCornerRadius(24)
            }
            .sheet(isPresented: $vm.showTemplatePicker) {
                CanvasTemplateSheet(
                    templates: CanvasTemplateService.templates,
                    lockedTemplateIDs: lockedTemplateIDs
                ) { template in
                    insertTemplate(template, viewportSize: geo.size)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
            .sheet(isPresented: $showSettings) {
                settingsSheet()
            }
            .sheet(isPresented: $showExportSheet) {
                exportSheet(viewportSize: geo.size)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallSheet {
                    completePendingProPageAction()
                }
                .onDisappear {
                    if !pro.isPro {
                        pendingProPageAction = nil
                    }
                }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
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
                            canvasID: activeContentCanvasID,
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
                        canvasID: activeContentCanvasID,
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
                        canvasID: activeContentCanvasID, imageData: imageData, center: center,
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
                        vm.imageVM.addImage(canvasID: activeContentCanvasID, imageData: data, center: center,
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
                handleCSVImportResult(result)
            }
            .fileImporter(isPresented: $vm.showAudioImporter,
                         allowedContentTypes: [UTType.mp3, UTType.mpeg4Audio, UTType.aiff, UTType.wav],
                         allowsMultipleSelection: false) { result in
                handleAudioImportResult(result)
            }
        }
    }

    @ViewBuilder
    private func canvasElementsSurface(geo: GeometryProxy) -> some View {
        ZStack {
            connectorOverlayLayer
            connectorAnchorLayer
            visibleElementsLayer(viewportSize: geo.size)
        }
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
    }

    private var connectorOverlayLayer: some View {
        ConnectorOverlayView(
            connectors: connectors,
            boundsMap: boundsMap,
            vm: vm.connectorVM,
            undoManager: vm.undoManager,
            canvasID: activeContentCanvasID,
            canvasScale: vm.scale
        )
        .zIndex(-1)
    }

    private var connectorAnchorLayer: some View {
        ConnectorAnchorDotsView(
            boundsMap: boundsMap,
            vm: vm.connectorVM,
            undoManager: vm.undoManager,
            canvasID: activeContentCanvasID,
            canvasScale: vm.scale,
            connectors: connectors
        )
        .zIndex(9999)
    }

    @ViewBuilder
    private var canvasDrawingOverlayLayer: some View {
        #if os(iOS)
        CanvasDrawingOverlay(
            isActive: $vm.showCanvasDrawingOverlay,
            isDrawingInputActive: $isCanvasDrawingInputActive,
            startScale: drawingStartScale,
            startOffset: drawingStartOffset,
            liveScale: $vm.scale,
            liveOffset: $vm.offset,
            initialDrawing: canvasDrawingInitialDrawing,
            smartShapeSnappingEnabled: canvasDrawingCaptureMode == .drawing && settings.smartShapeSnappingEnabled
        ) { pkDrawing, effectiveScale, effectiveOffset in
            saveCanvasDrawing(pkDrawing, effectiveScale: effectiveScale, effectiveOffset: effectiveOffset)
        }
        .zIndex(200)
        .transition(.opacity)
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    private func visibleElementsLayer(viewportSize: CGSize) -> some View {
        let visibleElements = visibleSortedElements(viewportSize: viewportSize)
        let nextZIndex = LayersViewModel.nextZ(among: allLayerableElements)

        ForEach(visibleElements, id: \.id) { element in
            renderElement(element, nextZIndex: nextZIndex)
        }

        if !selection.isMultiSelectActive {
            groupSelectionLayer
        }
    }

    private func canvasNavigation<Content: View>(_ content: Content) -> some View {
        content
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .background(InteractivePopGestureDisabler(isDisabled: true))
            #endif
            .toolbar { canvasToolbar }
            .ignoresSafeArea(edges: .bottom)
    }

    @ToolbarContentBuilder
    private var canvasToolbar: some ToolbarContent {
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
                Button { showExportSheet = true } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Export canvas")
                Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                Menu {
                    Button { newName = canvas.name; showRenameAlert = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) { showDeleteAlert = true } label: {
                        Label("Delete Canvas", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func canvasDocumentSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showPDFReader, onDismiss: { openPDFElement = nil }) {
                if let pdf = openPDFElement {
                    PDFReaderSheet(
                        pdfFileName: pdf.pdfFileName,
                        originalName: pdf.originalName,
                        pageCount: pdf.pageCount
                    )
                }
            }
            .sheet(isPresented: $showPDFImporter) {
                pdfImporterSheet
            }
            .sheet(isPresented: $showCSVExporter) {
                CSVShareSheet(csvString: csvExportString, filename: csvExportFilename)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
    }

    private func canvasAlerts<Content: View>(_ content: Content) -> some View {
        content
            .alert("Delete Canvas", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) { onDelete(); dismiss() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\(canvas.name) will be permanently deleted.")
            }
            .alert("Rename Canvas", isPresented: $showRenameAlert) {
                TextField("Canvas name", text: $newName).autocorrectionDisabled()
                Button("Rename") {
                    let trimmed = newName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { onRename(trimmed) }
                }
                Button("Cancel", role: .cancel) { }
            }
            .alert("Rename Page", isPresented: renamePageAlertBinding) {
                TextField("Page name", text: $pageRenameText).autocorrectionDisabled()
                Button("Rename") { commitPageRename() }
                Button("Cancel", role: .cancel) { pageForRename = nil }
            }
            .alert("Delete Page", isPresented: deletePageAlertBinding) {
                Button("Delete", role: .destructive) {
                    if let page = pagePendingDeletion { deletePage(page) }
                    pagePendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pagePendingDeletion = nil }
            } message: {
                Text("This page and its content will be deleted.")
            }
            .alert("OCR Scan", isPresented: ocrScanAlertBinding) {
                Button("OK", role: .cancel) { ocrScanAlertMessage = nil }
            } message: {
                Text(ocrScanAlertMessage ?? "")
            }
    }

    private var renamePageAlertBinding: Binding<Bool> {
        Binding(
            get: { pageForRename != nil },
            set: { isPresented in
                if !isPresented { pageForRename = nil }
            }
        )
    }

    private var deletePageAlertBinding: Binding<Bool> {
        Binding(
            get: { pagePendingDeletion != nil },
            set: { isPresented in
                if !isPresented { pagePendingDeletion = nil }
            }
        )
    }

    private var ocrScanAlertBinding: Binding<Bool> {
        Binding(
            get: { ocrScanAlertMessage != nil },
            set: { isPresented in
                if !isPresented { ocrScanAlertMessage = nil }
            }
        )
    }

    @ViewBuilder
    private var pdfImporterSheet: some View {
        #if canImport(UIKit)
        PDFDocumentPicker { url in
            handlePDFImportURL(url)
        }
        #else
        EmptyView()
        #endif
    }

    private func handlePDFImportURL(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let center = vm.pendingPDFLocation ?? CGPoint(x: 300, y: 400)
        vm.pdfVM.addPDF(
            canvasID: activeContentCanvasID,
            sourceURL: url,
            center: center,
            offset: vm.offset,
            scale: vm.scale,
            zIndex: LayersViewModel.nextZ(among: allLayerableElements),
            context: context,
            undoManager: vm.undoManager
        )
        vm.pendingPDFLocation = nil
        showPDFImporter = false
    }

    private func handleAudioImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let imported = try AudioStorageService.importAudio(from: url)
                let center = vm.pendingAudioLocation ?? CGPoint(x: 300, y: 400)
                vm.audioVM.addAudio(
                    canvasID: activeContentCanvasID,
                    audioFileName: imported.fileName,
                    originalName: imported.originalName,
                    duration: imported.duration,
                    center: center,
                    offset: vm.offset,
                    scale: vm.scale,
                    zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                    context: context,
                    undoManager: vm.undoManager
                )
                vm.pendingAudioLocation = nil
            } catch {
                print("⚠️ Audio import error: \(error)")
            }
        case .failure(let error):
            print("⚠️ Audio file error: \(error)")
        }
    }

    @ViewBuilder
    private func pagesPanelLayer(geo: GeometryProxy) -> some View {
        CanvasPagesPanel(
            pages: canvasPages,
            activePageID: activePage?.id,
            viewportSize: geo.size,
            isAddLocked: areAdditionalPagesLocked,
            isExpanded: $showPagesPanel,
            onSelect: { page in
                selectPage(page, viewportSize: geo.size)
            },
            onAdd: { addPage(viewportSize: geo.size) },
            onRename: { page in
                pageRenameText = page.name
                pageForRename = page
            },
            onDuplicate: { duplicatePage($0, viewportSize: geo.size) },
            onDelete: { pagePendingDeletion = $0 }
        )
    }

    @discardableResult
    private func ensureDefaultPage() -> CanvasPageModel? {
        normalizePageContentIDs()

        if let firstPage = canvasPages.first {
            return firstPage
        }

        let size = canvas.defaultPageSize
        let page = CanvasPageModel(
            canvasID: canvas.id,
            contentCanvasID: canvas.id,
            name: "Page 1",
            width: size.width,
            height: size.height
        )
        context.insert(page)
        try? context.save()
        Task { await CanvasPageSyncService.shared.upsert(page) }
        return page
    }

    private func normalizePageContentIDs() {
        guard !canvasPages.isEmpty else { return }

        var changedPages: [CanvasPageModel] = []
        for (index, page) in canvasPages.enumerated() {
            let desiredID: UUID
            if index == 0 {
                desiredID = canvas.id
            } else if page.contentCanvasID == nil || page.resolvedContentCanvasID == canvas.id {
                desiredID = UUID()
            } else {
                continue
            }

            page.contentCanvasID = desiredID
            page.updatedAt = Date()
            changedPages.append(page)
        }

        guard !changedPages.isEmpty else { return }
        try? context.save()
        Task {
            for page in changedPages {
                await CanvasPageSyncService.shared.upsert(page)
            }
        }
    }

    private func addPage(viewportSize: CGSize) {
        guard canCreateAdditionalPage else {
            pendingProPageAction = .add(viewportSize: viewportSize)
            showPaywall = true
            return
        }

        createPage(viewportSize: viewportSize)
    }

    private func createPage(viewportSize: CGSize) {
        generateThumbnail()
        let size = canvas.defaultPageSize
        let nextIndex = (canvasPages.map(\.orderIndex).max() ?? -1) + 1

        let page = CanvasPageModel(
            canvasID: canvas.id,
            contentCanvasID: UUID(),
            name: "Page \(nextIndex + 1)",
            width: size.width,
            height: size.height,
            orderIndex: nextIndex
        )

        context.insert(page)
        try? context.save()
        selectedPageID = page.id
        Task { await CanvasPageSyncService.shared.upsert(page) }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusPage(page, viewportSize: viewportSize, animated: false)
        }
    }

    private func duplicatePage(_ page: CanvasPageModel, viewportSize: CGSize) {
        guard canCreateAdditionalPage else {
            pendingProPageAction = .newSameSize(pageID: page.id, viewportSize: viewportSize)
            showPaywall = true
            return
        }

        createPage(sameSizeAs: page, viewportSize: viewportSize)
    }

    private func createPage(sameSizeAs page: CanvasPageModel, viewportSize: CGSize) {
        generateThumbnail()
        let nextIndex = (canvasPages.map(\.orderIndex).max() ?? -1) + 1
        let duplicate = CanvasPageModel(
            canvasID: canvas.id,
            contentCanvasID: UUID(),
            name: "Page \(nextIndex + 1)",
            width: page.width,
            height: page.height,
            orderIndex: nextIndex
        )

        context.insert(duplicate)
        try? context.save()
        selectedPageID = duplicate.id
        Task { await CanvasPageSyncService.shared.upsert(duplicate) }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusPage(duplicate, viewportSize: viewportSize, animated: false)
        }
    }

    private func completePendingProPageAction() {
        guard let action = pendingProPageAction else { return }
        pendingProPageAction = nil

        switch action {
        case .add(let viewportSize):
            createPage(viewportSize: viewportSize)
        case .newSameSize(let pageID, let viewportSize):
            if let page = canvasPages.first(where: { $0.id == pageID }) {
                createPage(sameSizeAs: page, viewportSize: viewportSize)
            } else {
                createPage(viewportSize: viewportSize)
            }
        }
    }

    private func deletePage(_ page: CanvasPageModel) {
        guard canvasPages.count > 1 else { return }
        let remainingPages = canvasPages.filter { $0.id != page.id }
        deletePageContent(for: page.resolvedContentCanvasID)
        Task { await CanvasPageSyncService.shared.delete(page) }
        context.delete(page)
        try? context.save()

        if selectedPageID == page.id {
            selectedPageID = remainingPages.first?.id
        }
    }

    private func deletePageContent(for contentCanvasID: UUID) {
        let groups = allElementGroups.filter { $0.canvasID == contentCanvasID }
        let texts = allTextElements.filter { $0.canvasID == contentCanvasID }
        let stickies = allStickyNotes.filter { $0.canvasID == contentCanvasID }
        let todos = allTodoLists.filter { $0.canvasID == contentCanvasID }
        let todoIDs = Set(todos.map(\.id))
        let tasks = allTodoTasks.filter { todoIDs.contains($0.listID) }
        let shapes = allShapes.filter { $0.canvasID == contentCanvasID }
        let images = allImages.filter { $0.canvasID == contentCanvasID }
        let pdfs = allPDFs.filter { $0.canvasID == contentCanvasID }
        let tables = allTables.filter { $0.canvasID == contentCanvasID }
        let tableIDs = Set(tables.map(\.id))
        let cells = allTableCells.filter { tableIDs.contains($0.tableID) }
        let audio = allAudio.filter { $0.canvasID == contentCanvasID }
        let youtube = allYouTube.filter { $0.canvasID == contentCanvasID }
        let drawings = allDrawings.filter { $0.canvasID == contentCanvasID }
        let connectors = allConnectors.filter { $0.canvasID == contentCanvasID }
        let symbols = allSymbols.filter { $0.canvasID == contentCanvasID }

        Task {
            for connector in connectors { await ConnectorSyncService.shared.delete(connector) }
            for text in texts { await TextSyncService.shared.delete(text) }
            for sticky in stickies { await StickyNoteSyncService.shared.delete(sticky) }
            for todo in todos {
                let listTasks = tasks.filter { $0.listID == todo.id }
                await TodoSyncService.shared.deleteList(todo, tasks: listTasks)
            }
            for shape in shapes { await ShapeSyncService.shared.delete(shape) }
            for image in images { await ImageSyncService.shared.delete(image) }
            for pdf in pdfs { await PDFSyncService.shared.delete(pdf) }
            for table in tables {
                let tableCells = cells.filter { $0.tableID == table.id }
                await TableSyncService.shared.deleteTable(table, cells: tableCells)
            }
            for item in audio { await AudioSyncService.shared.delete(item) }
            for item in youtube { await YouTubeSyncService.shared.delete(item) }
            for drawing in drawings { await DrawingSyncService.shared.delete(drawing) }
            for symbol in symbols { await SymbolSyncService.shared.delete(symbol) }
            for group in groups { await ElementGroupSyncService.shared.delete(group) }
        }

        connectors.forEach { context.delete($0) }
        texts.forEach { context.delete($0) }
        stickies.forEach { context.delete($0) }
        tasks.forEach { context.delete($0) }
        todos.forEach { context.delete($0) }
        shapes.forEach { context.delete($0) }
        images.forEach { context.delete($0) }
        pdfs.forEach { context.delete($0) }
        cells.forEach { context.delete($0) }
        tables.forEach { context.delete($0) }
        audio.forEach { context.delete($0) }
        youtube.forEach { context.delete($0) }
        drawings.forEach { context.delete($0) }
        symbols.forEach { context.delete($0) }
        groups.forEach { context.delete($0) }
    }

    private func selectPage(_ page: CanvasPageModel, viewportSize: CGSize) {
        guard page.id != selectedPageID else { return }
        generateThumbnail()
        selectedPageID = page.id
        focusPage(page, viewportSize: viewportSize, animated: false)
    }

    private func commitPageRename() {
        guard let page = pageForRename else { return }
        let trimmed = pageRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pageForRename = nil
            return
        }

        page.name = trimmed
        page.updatedAt = Date()
        try? context.save()
        Task { await CanvasPageSyncService.shared.upsert(page) }
        pageForRename = nil
    }

    private func focusPage(_ page: CanvasPageModel, viewportSize: CGSize, animated: Bool = true) {
        guard viewportSize.width > 0,
              viewportSize.height > 0,
              page.width > 0,
              page.height > 0 else { return }

        let padding: CGFloat = viewportSize.width < 430 ? 42 : 72
        let availableWidth = max(80, viewportSize.width - padding * 2)
        let availableHeight = max(80, viewportSize.height - padding * 2)
        let scaleX = availableWidth / CGFloat(page.width)
        let scaleY = availableHeight / CGFloat(page.height)
        let nextScale = max(0.15, min(scaleX, scaleY, 1.1))
        let center = page.center
        let nextOffset = CGSize(
            width: viewportSize.width / 2 - CGFloat(center.x) * nextScale,
            height: viewportSize.height / 2 - CGFloat(center.y) * nextScale
        )

        let applyFocus = {
            vm.scale = nextScale
            vm.lastScale = nextScale
            vm.offset = nextOffset
            vm.lastOffset = nextOffset
        }

        if animated {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                applyFocus()
            }
        } else {
            applyFocus()
        }
    }

    private var connectModeOverlay: some View {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .accentColor.opacity(0.4), radius: 8, x: 0, y: 3)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .zIndex(90)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(duration: 0.3), value: vm.connectorVM.isConnectModeActive)
    }

    private var multiSelectOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 13, weight: .medium))
                Text(multiSelectStatusText)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.blue, in: Capsule())
            .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 3)
            .padding(.top, 16)

            Spacer()

            ScrollView(.horizontal, showsIndicators: false) {
                MultiSelectBar(
                    count: selection.count,
                    groupActionTitle: groupActionTitle,
                    groupActionIcon: groupActionIcon,
                    canUseGroupAction: canUseGroupAction,
                    onGroupAction: { handleGroupAction() },
                    onDuplicate: { duplicateSelected() },
                    onDelete: { deleteSelected() },
                    onDone: {
                        withAnimation(.spring(duration: 0.3)) { selection.exit() }
                        dismissEverything()
                    }
                )
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .zIndex(90)
        .transition(.opacity)
        .animation(.spring(duration: 0.3), value: selection.isMultiSelectActive)
    }

    private var multiSelectStatusText: String {
        selection.count == 0 ? "Tap elements to select" : "\(selection.count) selected"
    }

    @ViewBuilder
    private var groupSelectionLayer: some View {
        ForEach(elementGroups, id: \.id) { group in
            if let bounds = groupBounds(for: group.id) {
                groupSelectionView(group: group, bounds: bounds)
            }
        }
    }

    private func groupSelectionView(group: CanvasElementGroupModel, bounds: CGRect) -> some View {
        let isActive = selectedGroupID == group.id || draggingGroupID == group.id
        let dragOffset = draggingGroupID == group.id ? groupDragOffset : .zero
        let cornerRadius: CGFloat = 12
        let safeScale = max(vm.scale, 0.01)
        let minimumHitSize = 76 / safeScale
        let hitWidth = max(bounds.width, minimumHitSize)
        let hitHeight = max(bounds.height, minimumHitSize)

        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.clear)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))

            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        Color.accentColor.opacity(0.82),
                        style: StrokeStyle(lineWidth: max(1.4 / safeScale, 0.5),
                                           dash: [7 / safeScale, 5 / safeScale])
                    )
                    .frame(width: bounds.width, height: bounds.height)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.accentColor.opacity(0.045))
                            .frame(width: bounds.width, height: bounds.height)
                    )
                    .allowsHitTesting(false)

                groupToolbar(group: group)
                    .offset(y: -bounds.height / 2 - 34 / safeScale)
                    .scaleEffect(1 / safeScale)
                    .transition(.scale(scale: 0.88, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: hitWidth, height: hitHeight)
        .position(x: bounds.midX + dragOffset.width, y: bounds.midY + dragOffset.height)
        .zIndex(isActive ? 15000 : 14000)
        .allowsHitTesting(true)
        .gesture(isActive ? groupDragGesture(groupID: group.id) : nil)
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                guard !isCanvasGestureActive else { return }
                enterMultiSelectFromGroup(group.id)
            }
        )
        .onTapGesture {
            guard !isCanvasGestureActive else { return }
            selectGroup(group.id)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: selectedGroupID)
    }

    private func groupToolbar(group: CanvasElementGroupModel) -> some View {
        HStack(spacing: 6) {
            Text(group.name)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Divider().frame(height: 18)

            Button {
                duplicateGroup(group.id)
            } label: {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Duplicate group")

            Button {
                ungroup(group.id)
            } label: {
                Image(systemName: "square.stack.3d.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ungroup")

            Button(role: .destructive) {
                deleteGroupContents(group.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete group")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 38)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 4)
        .fixedSize()
    }

    @ViewBuilder
    private func stackPickerOverlay(_ picker: CanvasStackPickerState) -> some View {
        Color.black.opacity(0.001)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { stackPicker = nil }
            .zIndex(118)

        stackPickerView(picker)
            .zIndex(119)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private var processingOverlay: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(processingStatusText)
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

    private var processingStatusText: String {
        isProcessingOCRScan ? "Extracting text..." : "Preparing scan..."
    }

    @ViewBuilder
    private func addMenuOverlay(at position: CGPoint) -> some View {
        Color.black.opacity(0.001)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { vm.hideAddMenu() }

        AddElementMenu(position: position, lockedTools: lockedCanvasTools) { tool in
            handleToolSelection(tool, at: position)
        } onDismiss: {
            vm.hideAddMenu()
        }
        .zIndex(100)
    }

    private func settingsSheet() -> some View {
        SettingsSheet(settings: settings)
        .presentationDetents([.height(680), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }

    private func exportSheet(viewportSize: CGSize) -> some View {
        CanvasExportSheet {
            canvasExportButton(viewportSize: viewportSize)
        }
        .presentationDetents([.height(300), .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }

    private func canvasExportButton(viewportSize: CGSize) -> AnyView {
        AnyView(
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
                youtubeElements: youtubeElements,
                drawings:      drawings,
                symbols:       symbols,
                connectors:    connectors,
                currentViewportRect: currentViewportExportRect(viewportSize: viewportSize)
            )
        )
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
        for element in elements where element.canvasID == activeContentCanvasID {
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

    private func selectGroup(_ groupID: UUID) {
        dismissEverything()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            selectedGroupID = groupID
        }
    }

    private func groupMembers(for groupID: UUID) -> [any LayerableElement] {
        allLayerableElements.filter { $0.groupID == groupID }
    }

    private func groupBounds(for groupID: UUID) -> CGRect? {
        let rects = groupMembers(for: groupID).compactMap { element -> CGRect? in
            boundsMap[element.id]?.rect
        }
        guard var union = rects.first else { return nil }
        for rect in rects.dropFirst() {
            union = union.union(rect)
        }
        return union.insetBy(dx: -16, dy: -16)
    }

    private func screenRect(for canvasRect: CGRect) -> CGRect {
        CGRect(
            x: canvasRect.minX * vm.scale + vm.offset.width,
            y: canvasRect.minY * vm.scale + vm.offset.height,
            width: canvasRect.width * vm.scale,
            height: canvasRect.height * vm.scale
        )
    }

    private func groupDragOffset(for element: any LayerableElement) -> CGSize {
        guard let groupID = element.groupID,
              draggingGroupID == groupID else { return .zero }
        return groupDragOffset
    }

    private func multiSelectIDs(for element: any LayerableElement) -> Set<UUID> {
        guard let groupID = element.groupID else { return [element.id] }
        return Set(groupMembers(for: groupID).map(\.id))
    }

    private func isSelectedInMultiSelect(_ element: any LayerableElement) -> Bool {
        !selection.selectedIDs.isDisjoint(with: multiSelectIDs(for: element))
    }

    private func toggleMultiSelection(for element: any LayerableElement) {
        let ids = multiSelectIDs(for: element)
        guard !ids.isEmpty else { return }

        if ids.isSubset(of: selection.selectedIDs) {
            selection.selectedIDs.subtract(ids)
        } else {
            selection.selectedIDs.formUnion(ids)
        }
    }

    private func enterMultiSelectFromGroupedElement(_ element: any LayerableElement) {
        dismissEverything()
        withAnimation(.spring(duration: 0.3)) {
            selection.enterMultiSelect()
            selection.selectedIDs.formUnion(multiSelectIDs(for: element))
        }
    }

    private func enterMultiSelectFromGroup(_ groupID: UUID) {
        let ids = Set(groupMembers(for: groupID).map(\.id))
        guard !ids.isEmpty else { return }

        dismissEverything()
        withAnimation(.spring(duration: 0.3)) {
            selection.enterMultiSelect()
            selection.selectedIDs.formUnion(ids)
        }
    }

    private func groupDragGesture(groupID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !isCanvasGestureActive else { return }
                if draggingGroupID != groupID {
                    selectGroup(groupID)
                    draggingGroupID = groupID
                }
                groupDragOffset = value.translation
            }
            .onEnded { value in
                guard draggingGroupID == groupID else {
                    groupDragOffset = .zero
                    return
                }
                moveGroup(groupID, by: value.translation)
                groupDragOffset = .zero
                draggingGroupID = nil
            }
    }

    private func handleGroupAction() {
        if let groupID = selectedGroupForUngroup {
            ungroup(groupID)
        } else {
            groupSelected()
        }
    }

    private func groupSelected() {
        let elements = selection.selectedIDs.compactMap { layerableElement(withID: $0) }
        guard elements.count >= 2 else { return }

        let group = CanvasElementGroupModel(
            canvasID: activeContentCanvasID,
            name: "Group \(elementGroups.count + 1)"
        )
        context.insert(group)

        let now = Date()
        for element in elements {
            element.groupID = group.id
            element.updatedAt = now
        }

        try? context.save()

        Task {
            await ElementGroupSyncService.shared.upsert(group)
            for element in elements {
                await syncElement(element)
            }
        }

        cleanupEmptyGroups(excluding: Set([group.id]))

        withAnimation(.spring(duration: 0.3)) {
            selection.exit()
            selectedGroupID = group.id
        }
    }

    private func ungroup(_ groupID: UUID) {
        let members = groupMembers(for: groupID)
        let group = elementGroups.first { $0.id == groupID }
        let now = Date()

        for element in members {
            element.groupID = nil
            element.updatedAt = now
        }

        if let group {
            Task { await ElementGroupSyncService.shared.delete(group) }
            context.delete(group)
        }

        try? context.save()

        Task {
            for element in members {
                await syncElement(element)
            }
        }

        withAnimation(.spring(duration: 0.25)) {
            if selectedGroupID == groupID { selectedGroupID = nil }
            if draggingGroupID == groupID { draggingGroupID = nil }
            groupDragOffset = .zero
            selection.exit()
        }
    }

    private func moveGroup(_ groupID: UUID, by translation: CGSize) {
        let members = groupMembers(for: groupID)
        guard !members.isEmpty else { return }

        let now = Date()
        for element in members {
            element.x += Double(translation.width)
            element.y += Double(translation.height)
            element.updatedAt = now
        }

        if let group = elementGroups.first(where: { $0.id == groupID }) {
            group.updatedAt = now
            Task { await ElementGroupSyncService.shared.upsert(group) }
        }

        try? context.save()
        Task {
            for element in members {
                await syncElement(element)
            }
        }
    }

    private func duplicateGroup(_ groupID: UUID) {
        let members = groupMembers(for: groupID).sorted { $0.zIndex < $1.zIndex }
        guard !members.isEmpty else { return }

        let group = CanvasElementGroupModel(
            canvasID: activeContentCanvasID,
            name: "Group \(elementGroups.count + 1)"
        )
        context.insert(group)

        var z = LayersViewModel.nextZ(among: allLayerableElements)
        var copies: [any LayerableElement] = []

        for member in members {
            if let newID = duplicateElement(member, zIndex: z, selectCopy: false),
               let copy = layerableElement(withID: newID) {
                copy.groupID = group.id
                copy.updatedAt = Date()
                copies.append(copy)
            }
            z += 1
        }

        try? context.save()

        Task {
            await ElementGroupSyncService.shared.upsert(group)
            for copy in copies {
                await syncElement(copy)
            }
        }

        withAnimation(.spring(duration: 0.25)) {
            selectedGroupID = group.id
        }
    }

    private func deleteGroupContents(_ groupID: UUID) {
        let ids = Set(groupMembers(for: groupID).map(\.id))
        guard !ids.isEmpty else {
            ungroup(groupID)
            return
        }

        selection.selectedIDs = ids
        deleteSelected()

        if let group = elementGroups.first(where: { $0.id == groupID }) {
            Task { await ElementGroupSyncService.shared.delete(group) }
            context.delete(group)
            try? context.save()
        }

        withAnimation(.spring(duration: 0.25)) {
            selectedGroupID = nil
            draggingGroupID = nil
            groupDragOffset = .zero
        }
    }

    private func cleanupEmptyGroups(excluding protectedGroupIDs: Set<UUID> = []) {
        let usedGroupIDs = Set(allLayerableElements.compactMap(\.groupID))
        let emptyGroups = elementGroups.filter {
            !protectedGroupIDs.contains($0.id) && !usedGroupIDs.contains($0.id)
        }

        guard !emptyGroups.isEmpty else { return }

        for group in emptyGroups {
            Task { await ElementGroupSyncService.shared.delete(group) }
            context.delete(group)
        }

        try? context.save()
    }

    private func syncElement(_ element: any LayerableElement) async {
        if let element = element as? TextElementModel {
            await TextSyncService.shared.upsert(element)
        } else if let element = element as? StickyNoteModel {
            await StickyNoteSyncService.shared.upsert(element)
        } else if let element = element as? TodoListModel {
            await TodoSyncService.shared.upsertList(element)
        } else if let element = element as? ShapeElementModel {
            await ShapeSyncService.shared.upsert(element)
        } else if let element = element as? ImageElementModel {
            await ImageSyncService.shared.upsert(element)
        } else if let element = element as? PDFElementModel {
            await PDFSyncService.shared.upsert(element)
        } else if let element = element as? TableElementModel {
            await TableSyncService.shared.upsertTable(element)
        } else if let element = element as? AudioElementModel {
            await AudioSyncService.shared.upsert(element)
        } else if let element = element as? YouTubeElementModel {
            await YouTubeSyncService.shared.upsert(element)
        } else if let element = element as? DrawingElementModel {
            await DrawingSyncService.shared.upsert(element)
        } else if let element = element as? SymbolElementModel {
            await SymbolSyncService.shared.upsert(element)
        }
    }

    // MARK: - Gestures

    private func canvasPanGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                beginCanvasGestureSuppression()
                vm.handleDragChange(value)
            }
            .onEnded { _ in
                vm.handleDragEnd()
                if !canvas.isInfinite {
                    vm.clampOffset(to: canvasNavigationBoundary, viewportSize: geo.size, scale: vm.scale)
                }
                endCanvasGestureSuppression()
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
                    vm.clampOffset(to: canvasNavigationBoundary, viewportSize: geo.size, scale: vm.scale)
                }
                endCanvasGestureSuppression()
            }
    }

    private func beginCanvasGestureSuppression() {
        if isCanvasGestureActive { return }
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

    private func startCanvasDrawing(mode: CanvasDrawingCaptureMode = .drawing) {
        dismissEverything()
        continuingCanvasDrawingID = nil
        canvasDrawingInitialDrawing = PKDrawing()
        canvasDrawingCaptureMode = mode
        drawingStartScale  = vm.scale
        drawingStartOffset = vm.offset
        isCanvasDrawingInputActive = true
        vm.showCanvasDrawingOverlay = true
    }

    private func continueCanvasDrawing(_ element: DrawingElementModel) {
        guard element.isCanvasDrawing else {
            vm.drawingVM.isDrawingModeActive = true
            return
        }

        let initialDrawing = viewportDrawing(for: element)
        dismissEverything()
        continuingCanvasDrawingID = element.id
        canvasDrawingInitialDrawing = initialDrawing
        canvasDrawingCaptureMode = .drawing
        drawingStartScale = vm.scale
        drawingStartOffset = vm.offset
        isCanvasDrawingInputActive = true
        vm.showCanvasDrawingOverlay = true
    }

    private func viewportDrawing(for element: DrawingElementModel) -> PKDrawing {
        let width = CGFloat(element.width)
        let height = CGFloat(element.height)
        let angle = CGFloat(element.rotation) * .pi / 180
        let cosA = cos(angle)
        let sinA = sin(angle)
        let scale = vm.scale

        let tx = vm.offset.width + scale * (CGFloat(element.x) - cosA * width / 2 + sinA * height / 2)
        let ty = vm.offset.height + scale * (CGFloat(element.y) - sinA * width / 2 - cosA * height / 2)

        let transform = CGAffineTransform(
            a: scale * cosA,
            b: scale * sinA,
            c: -scale * sinA,
            d: scale * cosA,
            tx: tx,
            ty: ty
        )
        return element.pkDrawing.transformed(using: transform)
    }

    private func saveCanvasDrawing(_ pkDrawing: PKDrawing, effectiveScale: CGFloat, effectiveOffset: CGSize) {
        #if os(iOS)
        if canvasDrawingCaptureMode == .handwritingText,
           convertCanvasHandwritingToTextIfPossible(
                pkDrawing,
                effectiveScale: effectiveScale,
                effectiveOffset: effectiveOffset
           ) {
            continuingCanvasDrawingID = nil
            canvasDrawingInitialDrawing = PKDrawing()
            canvasDrawingCaptureMode = .drawing
            return
        }
        #endif

        persistCanvasDrawing(pkDrawing, effectiveScale: effectiveScale, effectiveOffset: effectiveOffset)
    }

    private func persistCanvasDrawing(_ pkDrawing: PKDrawing, effectiveScale: CGFloat, effectiveOffset: CGSize) {
        let strokeBounds = pkDrawing.bounds
        guard !pkDrawing.strokes.isEmpty,
              strokeBounds.width > 0, strokeBounds.height > 0 else {
            continuingCanvasDrawingID = nil
            canvasDrawingInitialDrawing = PKDrawing()
            canvasDrawingCaptureMode = .drawing
            return
        }

        let padding: CGFloat = 20
        let paddedBounds = strokeBounds.insetBy(dx: -padding, dy: -padding)
        let canvasX = (paddedBounds.midX - effectiveOffset.width) / effectiveScale
        let canvasY = (paddedBounds.midY - effectiveOffset.height) / effectiveScale
        let elemW = paddedBounds.width / effectiveScale
        let elemH = paddedBounds.height / effectiveScale
        let inverseScale = 1.0 / effectiveScale
        let transform = CGAffineTransform(
            a: inverseScale,
            b: 0,
            c: 0,
            d: inverseScale,
            tx: -paddedBounds.minX * inverseScale,
            ty: -paddedBounds.minY * inverseScale
        )
        let localDrawing = pkDrawing.transformed(using: transform)

        if let id = continuingCanvasDrawingID,
           let element = drawings.first(where: { $0.id == id }) {
            element.x = Double(canvasX)
            element.y = Double(canvasY)
            element.width = Double(elemW)
            element.height = Double(elemH)
            element.rotation = 0
            element.isCanvasDrawing = true
            element.pkDrawing = localDrawing
            element.updatedAt = Date()
            try? context.save()
            Task { await DrawingSyncService.shared.upsert(element) }
        } else {
            let element = DrawingElementModel(
                canvasID: activeContentCanvasID,
                x: Double(canvasX),
                y: Double(canvasY),
                width: Double(elemW),
                height: Double(elemH),
                isCanvasDrawing: true
            )
            element.pkDrawing = localDrawing
            element.zIndex = LayersViewModel.nextZ(among: allLayerableElements)
            context.insert(element)
            try? context.save()
            Task { await DrawingSyncService.shared.upsert(element) }
        }

        continuingCanvasDrawingID = nil
        canvasDrawingInitialDrawing = PKDrawing()
        canvasDrawingCaptureMode = .drawing
    }

    #if os(iOS)
    @discardableResult
    private func convertCanvasHandwritingToTextIfPossible(_ pkDrawing: PKDrawing,
                                                          effectiveScale: CGFloat,
                                                          effectiveOffset: CGSize) -> Bool {
        let strokeBounds = pkDrawing.bounds
        guard !pkDrawing.strokes.isEmpty,
              strokeBounds.width >= 30,
              strokeBounds.height >= 12
        else { return false }

        let padding: CGFloat = 24
        let recognitionBounds = strokeBounds.insetBy(dx: -padding, dy: -padding)
        isProcessingOCRScan = true
        defer { isProcessingOCRScan = false }

        guard let result = recognizeHandwritingText(
            in: pkDrawing,
            bounds: recognitionBounds,
            minimumConfidence: Float(settings.handwritingToTextStrictness)
        ) else { return false }

        let canvasPoint = CGPoint(
            x: (recognitionBounds.midX - effectiveOffset.width) / effectiveScale,
            y: (recognitionBounds.midY - effectiveOffset.height) / effectiveScale
        )
        let estimatedFontSize = estimatedHandwritingFontSize(
            recognitionText: result.text,
            bounds: recognitionBounds,
            scale: effectiveScale
        )
        let style = settings.lastTextStyle(text: result.text, estimatedFontSize: estimatedFontSize)

        if let id = continuingCanvasDrawingID,
           let element = drawings.first(where: { $0.id == id }) {
            Task { await DrawingSyncService.shared.delete(element) }
            context.delete(element)
        }

        _ = vm.textVM.addRecognizedHandwritingText(
            canvasID: activeContentCanvasID,
            style: style,
            canvasPoint: canvasPoint,
            zIndex: LayersViewModel.nextZ(among: allLayerableElements),
            context: context,
            undoManager: vm.undoManager
        )

        return true
    }

    private func recognizeHandwritingText(in drawing: PKDrawing,
                                          bounds: CGRect,
                                          minimumConfidence: Float) -> HandwritingRecognitionResult? {
        guard let cgImage = handwritingRecognitionImage(from: drawing, bounds: bounds) else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.025

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let candidates = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first }
            .filter { !$0.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !candidates.isEmpty else { return nil }

        let lines = candidates.map { $0.string.trimmingCharacters(in: .whitespacesAndNewlines) }
        let text = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2,
              text.rangeOfCharacter(from: .alphanumerics) != nil
        else { return nil }

        let weightedConfidence = candidates.reduce(Float(0)) { partial, candidate in
            partial + candidate.confidence * Float(max(candidate.string.count, 1))
        }
        let totalWeight = candidates.reduce(0) { $0 + max($1.string.count, 1) }
        let confidence = weightedConfidence / Float(max(totalWeight, 1))
        guard confidence >= minimumConfidence else { return nil }

        return HandwritingRecognitionResult(text: text, confidence: confidence)
    }

    private func handwritingRecognitionImage(from drawing: PKDrawing, bounds: CGRect) -> CGImage? {
        let size = CGSize(
            width: max(1, bounds.width),
            height: max(1, bounds.height)
        )
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 3
        rendererFormat.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let drawingImage = drawing.image(from: bounds, scale: rendererFormat.scale)
            drawingImage.draw(in: CGRect(origin: .zero, size: size))
        }
        return image.cgImage
    }

    private func estimatedHandwritingFontSize(recognitionText: String,
                                              bounds: CGRect,
                                              scale: CGFloat) -> Double {
        let lineCount = max(
            1,
            recognitionText
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
        )
        let canvasLineHeight = (bounds.height / max(scale, 0.0001)) / CGFloat(lineCount)
        return Double(max(10, min(72, canvasLineHeight * 0.72)))
    }
    #endif

    // MARK: - Sync

    private func pullFromCloud() {
        Task {
            await CanvasPageSyncService.shared.pullAll(canvasID: canvas.id, context: context)
            normalizePageContentIDs()
            await pullContent(canvasID: activeContentCanvasID)
        }
    }

    private func pullCurrentPageContent() {
        Task {
            await pullContent(canvasID: activeContentCanvasID)
        }
    }

    private func pullContent(canvasID: UUID) async {
        await ElementGroupSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await TextSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await StickyNoteSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await ShapeSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await ConnectorSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await DrawingSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await TodoSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await TableSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await ImageSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await PDFSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await AudioSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await YouTubeSyncService.shared.pullAll(canvasID: canvasID, context: context)
        await SymbolSyncService.shared.pullAll(canvasID: canvasID, context: context)
    }

    private func generateThumbnail() {
        if let activePage {
            CanvasThumbnailRenderer.generatePageThumbnail(
                page: activePage,
                canvas: canvas,
                textElements: textElements,
                stickyNotes: stickyNotes,
                todoLists: todoLists,
                shapes: shapes,
                images: images,
                drawings: drawings,
                gridStyle: settings.effectiveGridStyle,
                backgroundMode: settings.canvasBackgroundMode,
                backgroundPalette: settings.canvasBackgroundPalette,
                context: context
            )
        } else {
            CanvasThumbnailRenderer.generate(
                canvas: canvas,
                textElements: textElements,
                stickyNotes: stickyNotes,
                todoLists: todoLists,
                shapes: shapes,
                images: images,
                drawings: drawings,
                gridStyle: settings.effectiveGridStyle,
                backgroundMode: settings.canvasBackgroundMode,
                backgroundPalette: settings.canvasBackgroundPalette,
                context: context
            )
        }
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
    private func renderElement(_ element: any LayerableElement, nextZIndex: Int) -> some View {
        let boundary       = elementInteractionBoundary
        let multiSelect    = selection.isMultiSelectActive
        let isElemSelected = isSelectedInMultiSelect(element)
        let childInteractionLocked = isCanvasGestureActive || element.groupID != nil

        Group {
            if let text = element as? TextElementModel {
                TextElementView(element: text, canvasScale: vm.scale, canvasBoundary: boundary,
                                vm: vm.textVM, isMultiSelectMode: multiSelect,
                                isSelectedInMultiSelect: isElemSelected,
                                onExternalTap: { dismissEverything() },
                                isCanvasGestureActive: childInteractionLocked)
            } else if let sticky = element as? StickyNoteModel {
                StickyNoteView(note: sticky, canvasScale: vm.scale, canvasBoundary: boundary,
                               vm: vm.stickyVM, isMultiSelectMode: multiSelect,
                               isSelectedInMultiSelect: isElemSelected,
                               onExternalTap: { dismissEverything() },
                               isCanvasGestureActive: childInteractionLocked)
            } else if let todo = element as? TodoListModel {
                TodoListView(list: todo, allTasks: todoTasks, canvasScale: vm.scale,
                             canvasBoundary: boundary, vm: vm.todoVM,
                             isMultiSelectMode: multiSelect,
                             isSelectedInMultiSelect: isElemSelected,
                             onExternalTap: { dismissEverything() },
                             isCanvasGestureActive: childInteractionLocked)
            } else if let shape = element as? ShapeElementModel {
                ShapeElementView(shape: shape, canvasScale: vm.scale, canvasBoundary: boundary,
                                 vm: vm.shapeVM, isMultiSelectMode: multiSelect,
                                 isSelectedInMultiSelect: isElemSelected,
                                 onExternalTap: { dismissEverything() },
                                 isCanvasGestureActive: childInteractionLocked)
            } else if let img = element as? ImageElementModel {
                ImageElementView(element: img, canvasScale: vm.scale, canvasBoundary: boundary,
                                 vm: vm.imageVM, isMultiSelectMode: multiSelect,
                                 ocrTextZIndex: nextZIndex,
                                 undoManager: vm.undoManager,
                                 isSelectedInMultiSelect: isElemSelected,
                                 onExternalTap: { dismissEverything() },
                                 isCanvasGestureActive: childInteractionLocked)
            } else if let pdf = element as? PDFElementModel {
                PDFElementView(element: pdf, canvasScale: vm.scale, canvasBoundary: boundary,
                               vm: vm.pdfVM, isMultiSelectMode: multiSelect,
                               isSelectedInMultiSelect: isElemSelected,
                               onOpenReader: { openPDFElement = pdf; showPDFReader = true },
                               onExternalTap: { dismissEverything() },
                               isCanvasGestureActive: childInteractionLocked)
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
                    onMultiSelectTap: { toggleMultiSelection(for: table) },
                    isCanvasGestureActive: childInteractionLocked,
                    isCanvasNavigationActive: isCanvasGestureActive)
            } else if let audio = element as? AudioElementModel {
                AudioElementView(element: audio, canvasScale: vm.scale, canvasBoundary: boundary,
                                 vm: vm.audioVM, isMultiSelectMode: multiSelect,
                                 isSelectedInMultiSelect: isElemSelected,
                                 onExternalTap: { dismissEverything() },
                                 isCanvasGestureActive: childInteractionLocked)
            } else if let youtube = element as? YouTubeElementModel {
                YouTubeElementView(element: youtube, canvasScale: vm.scale, canvasBoundary: boundary,
                                   vm: vm.youtubeVM, isMultiSelectMode: multiSelect,
                                   isSelectedInMultiSelect: isElemSelected,
                                   onExternalTap: { dismissEverything() },
                                   isCanvasGestureActive: childInteractionLocked)
            } else if let drawing = element as? DrawingElementModel {
                DrawingElementView(element: drawing, canvasScale: vm.scale, canvasBoundary: boundary,
                                   vm: vm.drawingVM, isMultiSelectMode: multiSelect,
                                   isSelectedInMultiSelect: isElemSelected,
                                   onExternalTap: { dismissEverything() },
                                   onContinueCanvasDrawing: { continueCanvasDrawing($0) },
                                   isCanvasGestureActive: childInteractionLocked)
            } else if let symbol = element as? SymbolElementModel {
                // ── NEW ────────────────────────────────────────────────────────
                SymbolElementView(element: symbol, canvasScale: vm.scale, canvasBoundary: boundary,
                                  vm: vm.symbolVM, isMultiSelectMode: multiSelect,
                                  isSelectedInMultiSelect: isElemSelected,
                                  onExternalTap: { dismissEverything() },
                                  isCanvasGestureActive: childInteractionLocked)
            }
        }
        .opacity(vm.showCanvasDrawingOverlay && continuingCanvasDrawingID == element.id
                 ? 0
                 : layersVM.highlightedID == element.id ? 0.5 : 1)
        .offset(groupDragOffset(for: element))
        .animation(.easeInOut(duration: 0.3), value: layersVM.highlightedID)
        .allowsHitTesting(!vm.showCanvasDrawingOverlay)
        .highPriorityGesture(
            multiSelect ? nil : LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    guard !isCanvasGestureActive else { return }
                    if element.groupID != nil {
                        enterMultiSelectFromGroupedElement(element)
                    } else {
                        duplicateElement(element, offset: .zero)
                    }
                }
        )
        .highPriorityGesture(
            multiSelect ? TapGesture().onEnded {
                guard !isCanvasGestureActive else { return }
                toggleMultiSelection(for: element)
            } : nil
        )
        .highPriorityGesture(
            (!multiSelect && element.groupID != nil) ? TapGesture().onEnded {
                guard !isCanvasGestureActive,
                      let groupID = element.groupID else { return }
                selectGroup(groupID)
            } : nil
        )
    }

    @ViewBuilder
    private func toolbarLayer(geo: GeometryProxy) -> some View {
        let connectActive = vm.connectorVM.isConnectModeActive
        if settings.toolbarPosition == .hidden {
            EmptyView()
        } else if settings.toolbarStyle == .compactButtons {
            CompactCanvasToolbar(
                showTextSheet:  $vm.showTextSheet,
                onAddSticky:    { addStickyAtCenter(viewportSize: geo.size) },
                onAddTodo:      { addTodoAtCenter(viewportSize: geo.size) },
                onAddTemplate:  { openTemplatePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
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
                onWriteTextOnCanvas: { startCanvasDrawing(mode: .handwritingText) },
                onAddSymbol:    { openSymbolPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                onConnect:      { toggleConnectMode() },
                isConnectModeActive: connectActive,
                showsWriteTextTool: settings.handwritingToTextEnabled,
                lockedTools: lockedCanvasTools
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
            switch settings.toolbarPosition {
            case .hidden: EmptyView()
            case .bottom:
                VStack {
                    Spacer()
                    CanvasToolbar(
                    showTextSheet:  $vm.showTextSheet,
                    onAddSticky:    { addStickyAtCenter(viewportSize: geo.size) },
                    onAddTodo:      { addTodoAtCenter(viewportSize: geo.size) },
                    onAddTemplate:  { openTemplatePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
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
                    onWriteTextOnCanvas: { startCanvasDrawing(mode: .handwritingText) },
                    onAddSymbol:    { openSymbolPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },  // ← NEW
                    onConnect:      { toggleConnectMode() },
                    isConnectModeActive: connectActive,
                    showsWriteTextTool: settings.handwritingToTextEnabled,
                    lockedTools: lockedCanvasTools,
                    isVertical: false
                )
                .padding(.horizontal, 16)
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 12) + 12)
            }
            case .left:
                HStack {
                    CanvasToolbar(
                    showTextSheet:  $vm.showTextSheet,
                    onAddSticky:    { addStickyAtCenter(viewportSize: geo.size) },
                    onAddTodo:      { addTodoAtCenter(viewportSize: geo.size) },
                    onAddTemplate:  { openTemplatePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
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
                    onWriteTextOnCanvas: { startCanvasDrawing(mode: .handwritingText) },
                    onAddSymbol:    { openSymbolPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },  // ← NEW
                    onConnect:      { toggleConnectMode() },
                    isConnectModeActive: connectActive,
                    showsWriteTextTool: settings.handwritingToTextEnabled,
                    lockedTools: lockedCanvasTools,
                    isVertical: true
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
                    onAddTemplate:  { openTemplatePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
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
                    onWriteTextOnCanvas: { startCanvasDrawing(mode: .handwritingText) },
                    onAddSymbol:    { openSymbolPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },  // ← NEW
                    onConnect:      { toggleConnectMode() },
                    isConnectModeActive: connectActive,
                    showsWriteTextTool: settings.handwritingToTextEnabled,
                    lockedTools: lockedCanvasTools,
                    isVertical: true
                )
                .padding(.trailing, 16)
            }
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

    private func currentViewportExportRect(viewportSize: CGSize) -> CGRect? {
        guard vm.scale > 0, viewportSize.width > 0, viewportSize.height > 0 else { return nil }
        return CGRect(
            x: -vm.offset.width / vm.scale,
            y: -vm.offset.height / vm.scale,
            width: viewportSize.width / vm.scale,
            height: viewportSize.height / vm.scale
        )
    }

    private func handleCSVImportResult(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
            vm.pendingCSVTableID = nil
        }

        guard let csv = try? String(contentsOf: url, encoding: .utf8),
              let tableID = vm.pendingCSVTableID else { return }

        guard let table = tables.first(where: { $0.id == tableID }) else { return }
        vm.tableVM.importCSV(csv, into: table, cells: tableCells, context: context)
    }

    #if os(iOS)
    private func handleKeyboardWillShow(
        _ notification: Notification,
        viewportSize: CGSize,
        safeBottom: CGFloat
    ) {
        guard let editID = vm.textVM.inlineEditingID else { return }
        guard let kbFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        guard let element = textElements.first(where: { $0.id == editID }) else { return }

        let availableHeight = viewportSize.height - kbFrame.height + safeBottom
        let elementScreenY = CGFloat(element.y) * vm.scale + vm.offset.height
        let targetY = availableHeight - 80
        guard elementScreenY > targetY else { return }

        let delta = elementScreenY - targetY
        keyboardAvoidanceOffset = delta
        withAnimation(.easeOut(duration: duration)) {
            vm.offset.height -= delta
            vm.lastOffset = vm.offset
        }
    }

    private func handleKeyboardWillHide(_ notification: Notification) {
        guard keyboardAvoidanceOffset != 0 else { return }
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        withAnimation(.easeOut(duration: duration)) {
            vm.offset.height += keyboardAvoidanceOffset
            vm.lastOffset = vm.offset
        }
        keyboardAvoidanceOffset = 0
    }
    #endif

    private func dismissEverything() {
        stackPicker = nil
        selectedGroupID = nil
        draggingGroupID = nil
        groupDragOffset = .zero
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
        vm.showTemplatePicker = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        #endif
    }

    private func selectElement(id: UUID) {
        if let groupID = layerableElement(withID: id)?.groupID {
            selectGroup(groupID)
            return
        }

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
        vm.stickyVM.addNote(canvasID: activeContentCanvasID,
                            center: CGPoint(x: viewportSize.width/2, y: viewportSize.height/2),
                            offset: vm.offset, scale: vm.scale,
                            zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                            context: context, undoManager: vm.undoManager)
    }
    private func addTodoAtCenter(viewportSize: CGSize) {
        dismissEverything()
        vm.todoVM.addList(canvasID: activeContentCanvasID,
                          center: CGPoint(x: viewportSize.width/2, y: viewportSize.height/2),
                          offset: vm.offset, scale: vm.scale,
                          zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                          context: context, undoManager: vm.undoManager)
    }
    private func addDrawingAtCenter(viewportSize: CGSize) {
        dismissEverything()
        vm.drawingVM.addDrawing(canvasID: activeContentCanvasID,
                                center: CGPoint(x: viewportSize.width/2, y: viewportSize.height/2),
                                offset: vm.offset, scale: vm.scale,
                                zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                                context: context, undoManager: vm.undoManager)
    }
    private func openTemplatePicker(at point: CGPoint) {
        dismissEverything()
        vm.pendingTemplateLocation = point
        vm.showTemplatePicker = true
    }
    private func insertTemplate(_ template: CanvasTemplate, viewportSize: CGSize) {
        guard vm.scale > 0 else { return }

        if !pro.isPro,
           template.tableCount > 0,
           tables.count + template.tableCount > freeMediaElementLimit {
            vm.pendingTemplateLocation = nil
            showPaywall = true
            return
        }

        dismissEverything()
        let screenPoint = vm.pendingTemplateLocation
            ?? CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let canvasPoint = CGPoint(
            x: (screenPoint.x - vm.offset.width) / vm.scale,
            y: (screenPoint.y - vm.offset.height) / vm.scale
        )
        vm.pendingTemplateLocation = nil

        CanvasTemplateService.insert(
            template,
            canvasID: activeContentCanvasID,
            at: canvasPoint,
            startZIndex: LayersViewModel.nextZ(among: allLayerableElements),
            context: context,
            undoManager: vm.undoManager
        )
    }
    private func openShapePicker(at point: CGPoint) {
        dismissEverything(); vm.pendingShapeLocation = point; vm.showShapePicker = true
    }
    // ← NEW
    private func openSymbolPicker(at point: CGPoint) {
        dismissEverything(); vm.pendingSymbolLocation = point; vm.showSymbolPicker = true
    }
    private func canAddLimitedMediaElement(currentCount: Int) -> Bool {
        guard !pro.isPro, currentCount >= freeMediaElementLimit else { return true }
        dismissEverything()
        showPaywall = true
        return false
    }
    private func openImagePicker(at point: CGPoint) {
        guard canAddLimitedMediaElement(currentCount: images.count) else { return }
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
            vm.pdfVM.addPDF(canvasID: activeContentCanvasID, sourceURL: url, center: center,
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
        guard canAddLimitedMediaElement(currentCount: tables.count) else { return }
        dismissEverything(); vm.pendingTableLocation = point; showTableSizePicker = true
    }
    private func openAudioPicker(at point: CGPoint) {
        guard canAddLimitedMediaElement(currentCount: audioElements.count) else { return }
        dismissEverything(); vm.pendingAudioLocation = point; vm.showAudioPicker = true
    }
    private func openYouTubeLinkSheet(at point: CGPoint) {
        dismissEverything(); vm.pendingYouTubeLocation = point; vm.showYouTubeLinkSheet = true
    }

    private func handleToolSelection(_ tool: CanvasTool, at screenPoint: CGPoint) {
        vm.hideAddMenu(); lastMenuLocation = screenPoint
        let nextZ = LayersViewModel.nextZ(among: allLayerableElements)
        switch tool {
        case .text: vm.showTextSheet = true
        case .stickyNote:
            vm.stickyVM.addNote(canvasID: activeContentCanvasID, center: screenPoint,
                               offset: vm.offset, scale: vm.scale, zIndex: nextZ,
                               context: context, undoManager: vm.undoManager)
        case .todoList:
            vm.todoVM.addList(canvasID: activeContentCanvasID, center: screenPoint,
                             offset: vm.offset, scale: vm.scale, zIndex: nextZ,
                             context: context, undoManager: vm.undoManager)
        case .templates: openTemplatePicker(at: screenPoint)
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
            vm.drawingVM.addDrawing(canvasID: activeContentCanvasID, center: screenPoint,
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
                    canvasID: activeContentCanvasID,
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
                canvasID: activeContentCanvasID,
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
        cleanupEmptyGroups()
        withAnimation(.spring(duration: 0.3)) { selection.exit() }
    }
}

private extension ElementBounds {
    var rect: CGRect {
        CGRect(
            x: CGFloat(cx - width / 2),
            y: CGFloat(cy - height / 2),
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }

    func intersects(canvasRect: CGRect) -> Bool {
        rect.insetBy(dx: -24, dy: -24).intersects(canvasRect)
    }

    func contains(canvasPoint point: CGPoint, hitSlop: CGFloat) -> Bool {
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
