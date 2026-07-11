import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import PencilKit
#if os(iOS)
import Vision
import VisionKit
#elseif os(macOS)
import AppKit
#endif

let canvasViewportCoordinateSpace = "CanvasViewport"
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

/// Limits live pan/zoom invalidation to the tiny views that actually need the transform.
/// The canvas document itself remains stable while a finger is moving.
private struct CanvasNavigationObserver<Content: View>: View {
    @ObservedObject var navigation: CanvasNavigationState
    @ViewBuilder let content: (CGSize, CGFloat) -> Content

    var body: some View {
        content(navigation.offset, navigation.scale)
    }
}

private struct CanvasNavigationTransform<Content: View>: View {
    @ObservedObject var navigation: CanvasNavigationState
    let content: Content

    init(navigation: CanvasNavigationState, @ViewBuilder content: () -> Content) {
        self.navigation = navigation
        self.content = content()
    }

    var body: some View {
        content
            .scaleEffect(navigation.scale, anchor: .topLeading)
            .offset(navigation.offset)
    }
}

private struct ElementPositionSnapshot {
    let id: UUID
    let x: Double
    let y: Double
}

#if os(iOS)
private struct HandwritingRecognitionLine {
    let text: String
    let confidence: Float
    let bounds: CGRect
}

private struct HandwritingRecognitionResult {
    let lines: [HandwritingRecognitionLine]
    let confidence: Float

    var text: String {
        lines.map(\.text).joined(separator: "\n")
    }
}

private struct HandwritingTextBlock {
    let text: String
    let bounds: CGRect
}
#endif

private enum CanvasDrawingCaptureMode {
    case drawing
    case handwritingText
}

private enum CanvasDrawingToolMode: String, CaseIterable, Identifiable {
    case sketchCard
    case canvasInk
    case handwritingText

    var id: String { rawValue }

    static func availableModes(handwritingToTextEnabled: Bool) -> [CanvasDrawingToolMode] {
        #if os(iOS)
        var modes: [CanvasDrawingToolMode] = [.sketchCard, .canvasInk]
        if handwritingToTextEnabled {
            modes.append(.handwritingText)
        }
        return modes
        #else
        return [.sketchCard]
        #endif
    }

    var title: String {
        switch self {
        case .sketchCard: return "Drawing"
        case .canvasInk: return "Draw"
        case .handwritingText: return "Write"
        }
    }

    var subtitle: String {
        switch self {
        case .sketchCard: return "Place a movable sketch on the canvas"
        case .canvasInk: return "Ink directly across the canvas"
        case .handwritingText: return "Convert handwriting into editable text"
        }
    }

    var icon: String {
        switch self {
        case .sketchCard: return "pencil.and.scribble"
        case .canvasInk: return "scribble.variable"
        case .handwritingText: return "textformat.abc.dottedunderline"
        }
    }

    var tint: Color {
        switch self {
        case .sketchCard: return .orange
        case .canvasInk: return Color(red: 0.9, green: 0.5, blue: 0.1)
        case .handwritingText: return .blue
        }
    }
}

private enum CanvasScannerOutputMode: String, CaseIterable, Identifiable {
    case text
    case pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Editable Text"
        case .pdf: return "Scanned PDF"
        }
    }

    var subtitle: String {
        switch self {
        case .text: return "Extract readable text onto the canvas"
        case .pdf: return "Place scanned pages as a PDF"
        }
    }

    var icon: String {
        switch self {
        case .text: return "doc.text.viewfinder"
        case .pdf: return "doc.viewfinder"
        }
    }

    var tint: Color {
        switch self {
        case .text: return .teal
        case .pdf: return .red
        }
    }
}

private struct CanvasDrawingModePickerSheet: View {
    let modes: [CanvasDrawingToolMode]
    let onSelect: (CanvasDrawingToolMode) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 18)

            Text("Drawing")
                .font(.headline.weight(.bold))
                .padding(.bottom, 18)

            VStack(spacing: 10) {
                ForEach(modes) { mode in
                    modeButton(
                        icon: mode.icon,
                        color: mode.tint,
                        title: mode.title,
                        subtitle: mode.subtitle
                    ) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onSelect(mode)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private func modeButton(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct CanvasScannerOutputPickerSheet: View {
    let onSelect: (CanvasScannerOutputMode) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 18)

            Text("Scanner")
                .font(.headline.weight(.bold))
                .padding(.bottom, 18)

            VStack(spacing: 10) {
                ForEach(CanvasScannerOutputMode.allCases) { mode in
                    modeButton(
                        icon: mode.icon,
                        color: mode.tint,
                        title: mode.title,
                        subtitle: mode.subtitle
                    ) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onSelect(mode)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private func modeButton(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
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

    @Query private var allCanvasPages: [CanvasPageModel]
    @State private var selectedPageID: UUID?

    init(canvas: CanvasModel, onDelete: @escaping () -> Void, onRename: @escaping (String) -> Void) {
        self.canvas = canvas
        self.onDelete = onDelete
        self.onRename = onRename

        let canvasID = canvas.id
        self._allCanvasPages = Query(
            filter: #Predicate<CanvasPageModel> { $0.canvasID == canvasID }
        )
    }

    var body: some View {
        CanvasPageContentView(
            canvas: canvas,
            contentCanvasID: activeContentCanvasID,
            canvasPages: canvasPages,
            selectedPageID: $selectedPageID,
            onDelete: onDelete,
            onRename: onRename
        )
        .id(activeContentCanvasID)
    }

    private var canvasPages: [CanvasPageModel] {
        allCanvasPages.sorted {
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

    private var activeContentCanvasID: UUID {
        activePage?.resolvedContentCanvasID ?? canvas.id
    }
}

private struct CanvasPageContentView: View {
    let canvas: CanvasModel
    let contentCanvasID: UUID
    let canvasPages: [CanvasPageModel]
    @Binding var selectedPageID: UUID?
    var onDelete: () -> Void
    var onRename: (String) -> Void

    @EnvironmentObject private var settings: AppSettings
    @StateObject private var vm = CanvasViewModel()
    @ObservedObject private var pro = ProManager.shared
    @ObservedObject private var selection: SelectionViewModel = SelectionViewModel()
    @StateObject private var layersVM = LayersViewModel()
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Query private var allTextElements: [TextElementModel]
    @Query private var allStickyNotes: [StickyNoteModel]
    @Query private var allTodoLists: [TodoListModel]
    @Query private var allTodoTasks: [TodoTaskModel]
    @Query private var allShapes: [ShapeElementModel]
    @Query private var allImages: [ImageElementModel]
    @Query private var allPDFs: [PDFElementModel]
    @Query private var allPDFPages: [PDFPageElementModel]
    @Query private var allPDFHighlights: [PDFHighlightModel]
    @Query private var allPDFInkLayers: [PDFInkLayerModel]
    @Query private var allTables: [TableElementModel]
    @Query private var allTableCells: [TableCellModel]
    @Query private var allAudio: [AudioElementModel]
    @Query private var allYouTube: [YouTubeElementModel]
    @Query private var allDrawings: [DrawingElementModel]
    @Query private var allConnectors: [ConnectorModel]
    @Query private var allSymbols: [SymbolElementModel]
    @Query private var allElementGroups: [CanvasElementGroupModel]

    @State private var showDeleteAlert = false
    @State private var showRenameAlert = false
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var showExportSheet = false
    @State private var showLayers = false
    @State private var showPagesPanel = false
    @State private var showPDFReader = false
    @State private var showTableSizePicker = false
    @State private var showCSVExporter = false
    @State private var csvExportString = ""
    @State private var csvExportFilename = "table"
    @State private var stackPicker: CanvasStackPickerState?
    @State private var newName: String = ""
    @State private var pendingProPageAction: PendingProPageAction?
    @State private var pageForRename: CanvasPageModel?
    @State private var pageRenameText = ""
    @State private var pagePendingDeletion: CanvasPageModel?
    @State private var lastMenuLocation: CGPoint? = nil
    @State private var openPDFElement: PDFElementModel? = nil
    @State private var openPDFPageIndex = 0
    @State private var showPDFImporter = false
    @State private var drawingStartScale:  CGFloat = 1.0
    @State private var drawingStartOffset: CGSize  = .zero
    @State private var canvasDrawingInitialDrawing = PKDrawing()
    @State private var canvasDrawingCaptureMode: CanvasDrawingCaptureMode = .drawing
    @State private var continuingCanvasDrawingID: UUID?
    @State private var floatingYouTubeStopToken: UUID?
    @State private var isCanvasHighlighterToolSelected = false
    @State private var isCanvasDrawingInputActive = true
    @State private var isCanvasGestureActive = false
    @State private var isCanvasNavigationGestureInProgress = false
    @State private var viewportContentRevision = 0
    @State private var canvasGestureSuppressionID = UUID()
    #if os(macOS)
    @State private var showCommandPalette = false
    @State private var isSpacePanActive = false
    #endif
    @State private var selectedGroupID: UUID?
    @State private var draggingGroupID: UUID?
    @State private var groupDragOffset: CGSize = .zero
    @State private var multiSelectDragOffset: CGSize = .zero
    @State private var isLassoModeActive = false
    @State private var lassoPoints: [CGPoint] = []
    @State private var lassoFeedbackText: String?
    @State private var showDrawingModePicker = false
    @State private var pendingDrawingToolLocation: CGPoint?
    @State private var pendingScannerLocation: CGPoint?
    @State private var pendingScannerOutputMode: CanvasScannerOutputMode?
    @State private var isProcessingScan = false
    @State private var scannerAlertMessage: String?
    #if os(iOS)
    @State private var showScannerOutputPicker = false
    @State private var showScannerSourcePicker = false
    @State private var showScannerImagePicker = false
    @State private var selectedScannerPhotoItem: PhotosPickerItem?
    @State private var keyboardAvoidanceOffset: CGFloat = 0
    #endif

    @Environment(\.dismiss) private var dismiss

    private var activeContentCanvasID: UUID {
        contentCanvasID
    }

    private var drawingModePickerHeight: CGFloat {
        let modes = CanvasDrawingToolMode.availableModes(
            handwritingToTextEnabled: settings.handwritingToTextEnabled
        )
        return CGFloat(118 + modes.count * 68)
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
    private var pdfPages: [PDFPageElementModel]     { allPDFPages.filter     { $0.canvasID == activeContentCanvasID } }
    private var pdfHighlights: [PDFHighlightModel]  { allPDFHighlights.filter { $0.canvasID == activeContentCanvasID } }
    private var pdfInkLayers: [PDFInkLayerModel]    { allPDFInkLayers.filter { $0.canvasID == activeContentCanvasID } }
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

    private var elementCollection: CanvasElementCollection {
        CanvasElementCollection(
            textElements: textElements,
            stickyNotes: stickyNotes,
            todoLists: todoLists,
            shapes: shapes,
            images: images,
            pdfs: pdfs,
            pdfPages: pdfPages,
            tables: tables,
            audioElements: audioElements,
            youtubeElements: youtubeElements,
            drawings: drawings,
            symbols: symbols
        )
    }

    private var allLayerableElements: [any LayerableElement] {
        elementCollection.layerableElements
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
        allLayerableElements.sorted(by: canvasLayerSortsBefore)
    }

    private func canvasLayerSortsBefore(_ lhs: any LayerableElement,
                                        _ rhs: any LayerableElement) -> Bool {
        let lhsIsHighlight = (lhs as? DrawingElementModel)?.isCanvasHighlighterDrawing == true
        let rhsIsHighlight = (rhs as? DrawingElementModel)?.isCanvasHighlighterDrawing == true
        if lhsIsHighlight != rhsIsHighlight { return lhsIsHighlight }
        return lhs.zIndex < rhs.zIndex
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
        .sorted(by: canvasLayerSortsBefore)
    }

    private func visibleCanvasRect(viewportSize: CGSize) -> CGRect {
        // Keep the culling window stable while a gesture is in flight. Changing the
        // ForEach membership every few pixels forces SwiftUI to rebuild rich elements
        // (PDFs, drawings, tables) at display-link frequency.
        let renderScale = isCanvasNavigationGestureInProgress ? vm.lastScale : vm.scale
        let renderOffset = isCanvasNavigationGestureInProgress ? vm.lastOffset : vm.offset

        guard renderScale > 0, viewportSize.width > 0, viewportSize.height > 0 else {
            return CGRect(origin: .zero, size: viewportSize)
        }

        let width = viewportSize.width / renderScale
        let height = viewportSize.height / renderScale
        let rect = CGRect(
            x: -renderOffset.width / renderScale,
            y: -renderOffset.height / renderScale,
            width: width,
            height: height
        )

        let padX = max(220, width * 0.85)
        let padY = max(220, height * 0.85)
        return rect.insetBy(dx: -padX, dy: -padY)
    }

    private func elementBounds(for element: any LayerableElement) -> ElementBounds {
        elementCollection.bounds(for: element)
    }

    private var activeSelectedElementID: UUID? {
        if let id = vm.textVM.editingID { return id }
        if let id = vm.stickyVM.editingID { return id }
        if let id = vm.todoVM.editingID { return id }
        if let id = vm.shapeVM.editingID { return id }
        if let id = vm.imageVM.editingID { return id }
        if let id = vm.pdfVM.editingID { return id }
        if let id = vm.pdfPageVM.editingID { return id }
        if let id = vm.tableVM.selectedTableID { return id }
        if let id = vm.audioVM.editingID { return id }
        if let id = vm.youtubeVM.editingID { return id }
        if let id = vm.drawingVM.editingID { return id }
        if let id = vm.symbolVM.editingID { return id }
        return nil
    }

    /// Child controls only need the final zoom for hit targets and drag math. Freezing
    /// this value during navigation lets SwiftUI move/scale the parent layer without
    /// invalidating every individual element on every pinch frame.
    private var elementRenderScale: CGFloat {
        isCanvasNavigationGestureInProgress ? vm.lastScale : vm.scale
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

    init(
        canvas: CanvasModel,
        contentCanvasID: UUID,
        canvasPages: [CanvasPageModel],
        selectedPageID: Binding<UUID?>,
        onDelete: @escaping () -> Void,
        onRename: @escaping (String) -> Void
    ) {
        self.canvas = canvas
        self.contentCanvasID = contentCanvasID
        self.canvasPages = canvasPages
        self._selectedPageID = selectedPageID
        self.onDelete = onDelete
        self.onRename = onRename
        self._selection = ObservedObject(wrappedValue: SelectionViewModel())

        let activeCanvasID = contentCanvasID
        self._allTextElements = Query(
            filter: #Predicate<TextElementModel> { $0.canvasID == activeCanvasID }
        )
        self._allStickyNotes = Query(
            filter: #Predicate<StickyNoteModel> { $0.canvasID == activeCanvasID }
        )
        self._allTodoLists = Query(
            filter: #Predicate<TodoListModel> { $0.canvasID == activeCanvasID }
        )
        self._allTodoTasks = Query()
        self._allShapes = Query(
            filter: #Predicate<ShapeElementModel> { $0.canvasID == activeCanvasID }
        )
        self._allImages = Query(
            filter: #Predicate<ImageElementModel> { $0.canvasID == activeCanvasID }
        )
        self._allPDFs = Query(
            filter: #Predicate<PDFElementModel> { $0.canvasID == activeCanvasID }
        )
        self._allPDFPages = Query(
            filter: #Predicate<PDFPageElementModel> { $0.canvasID == activeCanvasID }
        )
        self._allPDFHighlights = Query(
            filter: #Predicate<PDFHighlightModel> { $0.canvasID == activeCanvasID }
        )
        self._allPDFInkLayers = Query(
            filter: #Predicate<PDFInkLayerModel> { $0.canvasID == activeCanvasID }
        )
        self._allTables = Query(
            filter: #Predicate<TableElementModel> { $0.canvasID == activeCanvasID }
        )
        self._allTableCells = Query()
        self._allAudio = Query(
            filter: #Predicate<AudioElementModel> { $0.canvasID == activeCanvasID }
        )
        self._allYouTube = Query(
            filter: #Predicate<YouTubeElementModel> { $0.canvasID == activeCanvasID }
        )
        self._allDrawings = Query(
            filter: #Predicate<DrawingElementModel> { $0.canvasID == activeCanvasID }
        )
        self._allConnectors = Query(
            filter: #Predicate<ConnectorModel> { $0.canvasID == activeCanvasID }
        )
        self._allSymbols = Query(
            filter: #Predicate<SymbolElementModel> { $0.canvasID == activeCanvasID }
        )
        self._allElementGroups = Query(
            filter: #Predicate<CanvasElementGroupModel> { $0.canvasID == activeCanvasID }
        )
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

                CanvasNavigationObserver(navigation: vm.navigation) { offset, scale in
                    CanvasGridView(
                        offset: offset,
                        scale: scale,
                        style: settings.effectiveGridStyle,
                        backgroundMode: settings.canvasBackgroundMode,
                        backgroundPalette: settings.canvasBackgroundPalette,
                        customBackgroundColors: settings.customCanvasBackgroundColors
                    )
                }
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
                                    style: settings.lastTextStyle(text: ""),
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
                    .zIndex(-2)

                if !canvas.isInfinite {
                    CanvasNavigationObserver(navigation: vm.navigation) { _, _ in
                        pageBoundaryOverlay(geo: geo)
                    }
                }

                canvasElementsSurface(geo: geo)

                #if os(iOS)
                CanvasGestureBridge(
                    isEnabled: !isLassoModeActive,
                    requiresTwoFingerPan: vm.showCanvasDrawingOverlay && isCanvasDrawingInputActive,
                    selectedElementFrame: vm.showCanvasDrawingOverlay ? nil : selectedElementGestureFrame,
                    onPanBegan: {
                        beginCanvasNavigationGesture()
                    },
                    onPanChanged: { translation in
                        updateCanvasNavigationPan(translation)
                    },
                    onPanEnded: {
                        endCanvasNavigationGesture(viewportSize: geo.size)
                    },
                    onPinchBegan: {
                        beginCanvasNavigationGesture()
                    },
                    onPinchChanged: { magnification, focal in
                        updateCanvasNavigationMagnification(magnification, focalPoint: focal)
                    },
                    onPinchEnded: {
                        endCanvasNavigationGesture(viewportSize: geo.size)
                    }
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)
                #endif

                if !vm.showCanvasDrawingOverlay && !selection.isMultiSelectActive && !isLassoModeActive {
                    toolbarLayer(geo: geo)
                }

                if !vm.showCanvasDrawingOverlay && !isLassoModeActive && settings.canvasPagesPanelVisible {
                    pagesPanelLayer(geo: geo)
                }

                if vm.connectorVM.isConnectModeActive {
                    connectModeOverlay
                }

                if selection.isMultiSelectActive {
                    multiSelectOverlay
                }

                if isLassoModeActive {
                    lassoOverlay(geo: geo)
                }

                if let picker = stackPicker {
                    stackPickerOverlay(picker)
                }

                if isProcessingScan {
                    processingOverlay
                }

                if let pos = vm.addMenuPosition {
                    addMenuOverlay(at: pos)
                }

                if vm.showCanvasDrawingOverlay {
                    canvasDrawingOverlayLayer
                }

                #if os(macOS)
                if isSpacePanActive && !showCommandPalette {
                    spacePanLayer(geo: geo)
                }

                if showCommandPalette {
                    CanvasCommandPalette(
                        actions: canvasCommandPaletteActions(viewportSize: geo.size),
                        isPresented: $showCommandPalette
                    )
                    .zIndex(30000)
                }
                #endif
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
                        scheduleViewportContentRefresh()
                    } else {
                        vm.offset = CGSize(width: vm.offset.width + deltaX, height: vm.offset.height + deltaY)
                        vm.lastOffset = vm.offset
                        if !canvas.isInfinite {
                            vm.clampOffset(to: canvasNavigationBoundary, viewportSize: geo.size, scale: vm.scale)
                        }
                        scheduleViewportContentRefresh()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            )
            .overlay(
                MacKeyboardShortcutMonitor(isEnabled: true) { event, viewportSize in
                    handleCanvasKeyEvent(event, viewportSize: viewportSize)
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
                if settings.canvasMinimapVisible
                    && !vm.showCanvasDrawingOverlay && !selection.isMultiSelectActive
                    && !vm.connectorVM.isConnectModeActive {
                    CanvasNavigationObserver(navigation: vm.navigation) { offset, scale in
                        Minimap(
                            textElements: textElements, stickyNotes: stickyNotes,
                            todoLists: todoLists, shapes: shapes, images: images,
                            pdfs: pdfs, pdfPages: pdfPages,
                            tables: tables, audioElements: audioElements,
                            youtubeElements: youtubeElements, drawings: drawings,
                            symbols: symbols, viewportSize: geo.size,
                            canvasOffset: offset, canvasScale: scale,
                            onTapElement: {
                                vm.centerOn(canvasPoint: $0, viewportSize: geo.size)
                                refreshViewportContent()
                            },
                            isExpanded: $vm.isMinimapExpanded,
                            isNavigationActive: isCanvasGestureActive
                        )
                    }
                    .padding(.trailing, 12).padding(.top, 12)
                }
            }
            #if os(iOS)
            .overlay(alignment: .top) {
                if !canvasTopBarIsVisible && !vm.showCanvasDrawingOverlay {
                    canvasTopBarRevealButton
                        .padding(.top, 12)
                }
            }
            #endif
            .overlay(alignment: .bottomTrailing) {
                if settings.floatingYouTubePlaybackEnabled {
                    floatingYouTubePlayerLayer(geo: geo)
                        .padding(.trailing, 16)
                        .padding(.bottom, floatingYouTubeBottomPadding)
                } else {
                    youtubePlaybackControl
                        .padding(.trailing, 16)
                        .padding(.bottom, 24)
                }
            }
            .onChange(of: vm.youtubeVM.stopPlaybackRequestID) { _, requestID in
                if settings.floatingYouTubePlaybackEnabled,
                   requestID == vm.youtubeVM.activePlayingID {
                    floatingYouTubeStopToken = UUID()
                }
            }
            .onChange(of: vm.youtubeVM.activePlayingID) { _, _ in
                floatingYouTubeStopToken = nil
            }
            .onChange(of: settings.floatingYouTubePlaybackEnabled) { _, _ in
                floatingYouTubeStopToken = nil
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
            .sheet(isPresented: $showDrawingModePicker) {
                CanvasDrawingModePickerSheet(
                    modes: CanvasDrawingToolMode.availableModes(
                        handwritingToTextEnabled: settings.handwritingToTextEnabled
                    )
                ) { mode in
                    handleDrawingToolMode(mode, viewportSize: geo.size)
                }
                .presentationDetents([.height(drawingModePickerHeight)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
            #if os(iOS)
            .sheet(isPresented: $showScannerOutputPicker) {
                CanvasScannerOutputPickerSheet { mode in
                    beginScannerOutput(mode)
                }
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
            .sheet(isPresented: $showScannerSourcePicker) {
                ScanSourcePickerSheet(
                    onPhotos: { showScannerImagePicker = true },
                    onCamera: { beginScannerCameraScan() }
                )
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
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
            .fullScreenCover(isPresented: $vm.showScanner) {
                OCRDocumentScannerView(
                    onComplete: { images in
                        vm.showScanner = false
                        createSelectedScannerOutput(from: images, viewportSize: geo.size)
                    },
                    onCancel: {
                        vm.showScanner = false
                        clearScannerFlow()
                    },
                    onError: { _ in
                        vm.showScanner = false
                        clearScannerFlow()
                        scannerAlertMessage = "Could not scan this document."
                    }
                )
                .ignoresSafeArea()
            }
            #endif
            .photosPicker(isPresented: $vm.showImagePicker, selection: $vm.selectedPhotoItem, matching: .images)
            #if os(iOS)
            .photosPicker(
                isPresented: $showScannerImagePicker,
                selection: $selectedScannerPhotoItem,
                matching: .images
            )
            .onChange(of: selectedScannerPhotoItem) { _, newItem in
                guard let item = newItem else { return }
                Task {
                    defer { selectedScannerPhotoItem = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        clearScannerFlow()
                        scannerAlertMessage = "Could not open this image."
                        return
                    }
                    createSelectedScannerOutput(from: [image], viewportSize: geo.size)
                }
            }
            #endif
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
        CanvasNavigationTransform(navigation: vm.navigation) {
            ZStack {
                connectorOverlayLayer
                connectorAnchorLayer
                visibleElementsLayer(viewportSize: geo.size)
            }
        }
        .allowsHitTesting(!vm.showCanvasDrawingOverlay)
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
            canvasScale: elementRenderScale
        )
        .zIndex(-1)
    }

    private var connectorAnchorLayer: some View {
        ConnectorAnchorDotsView(
            boundsMap: boundsMap,
            vm: vm.connectorVM,
            undoManager: vm.undoManager,
            canvasID: activeContentCanvasID,
            canvasScale: elementRenderScale,
            connectors: connectors
        )
        .zIndex(9999)
    }

    @ViewBuilder
    private var canvasDrawingOverlayLayer: some View {
        #if os(iOS)
        CanvasNavigationObserver(navigation: vm.navigation) { _, _ in
            CanvasDrawingOverlay(
                isActive: $vm.showCanvasDrawingOverlay,
                isDrawingInputActive: $isCanvasDrawingInputActive,
                startScale: drawingStartScale,
                startOffset: drawingStartOffset,
                liveScale: Binding(get: { vm.scale }, set: { vm.scale = $0 }),
                liveOffset: Binding(get: { vm.offset }, set: { vm.offset = $0 }),
                initialDrawing: canvasDrawingInitialDrawing,
                isCanvasNavigationGestureActive: isCanvasNavigationGestureInProgress,
                smartShapeSnappingEnabled: canvasDrawingCaptureMode == .drawing && settings.smartShapeSnappingEnabled,
                showsHandwritingTextGrouping: canvasDrawingCaptureMode == .handwritingText,
                handwritingTextGrouping: Binding(
                    get: { settings.handwritingTextGrouping },
                    set: { settings.handwritingTextGrouping = $0 }
                ),
                isHighlighterToolSelected: $isCanvasHighlighterToolSelected
            ) { pkDrawing, effectiveScale, effectiveOffset in
                saveCanvasDrawing(pkDrawing, effectiveScale: effectiveScale, effectiveOffset: effectiveOffset)
            }
        }
        .zIndex(isCanvasHighlighterToolSelected ? -1 : 200)
        .transition(.opacity)
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    private func visibleElementsLayer(viewportSize: CGSize) -> some View {
        let _ = viewportContentRevision
        let visibleElements = visibleSortedElements(viewportSize: viewportSize)
        let nextZIndex = LayersViewModel.nextZ(among: allLayerableElements)

        ForEach(visibleElements, id: \.id) { element in
            renderElement(element, nextZIndex: nextZIndex)
        }

        if selection.isMultiSelectActive {
            multiSelectDragLayer
        } else {
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
            .toolbar(canvasTopBarIsVisible ? .visible : .hidden, for: .navigationBar)
            .toolbarBackground(canvasTopBarBackgroundColor, for: .navigationBar)
            .toolbarBackground(canvasTopBarIsVisible ? .visible : .hidden, for: .navigationBar)
            .toolbarColorScheme(canvasTopBarColorScheme, for: .navigationBar)
            #endif
            .toolbar { canvasToolbar }
            .ignoresSafeArea(edges: .bottom)
    }

    private var resolvedCanvasColorScheme: ColorScheme {
        settings.canvasBackgroundMode.resolvedColorScheme(system: colorScheme)
    }

    private var canvasBackgroundAppearance: CanvasBackgroundAppearance {
        settings.canvasBackgroundPalette.appearance(
            for: resolvedCanvasColorScheme,
            customColors: settings.customCanvasBackgroundColors
        )
    }

    private var canvasTopBarBackgroundColor: Color {
        canvasBackgroundAppearance.base.opacity(resolvedCanvasColorScheme == .dark ? 0.96 : 0.94)
    }

    private var canvasTopBarColorScheme: ColorScheme {
        resolvedCanvasColorScheme
    }

    private var canvasTopBarIsVisible: Bool {
        #if os(macOS)
        true
        #else
        settings.canvasTopBarVisible
        #endif
    }

    private var canvasTopBarRevealButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.canvasTopBarVisible = true
            }
        } label: {
            Image(systemName: "eye")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(resolvedCanvasColorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.75))
                .frame(width: 42, height: 34)
                .background(canvasTopBarBackgroundColor, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(canvasBackgroundAppearance.line.opacity(0.8), lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show top bar")
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
                #if os(iOS)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.canvasTopBarVisible = false
                    }
                } label: {
                    Image(systemName: "eye.slash")
                }
                .accessibilityLabel("Hide top bar")
                #endif
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
        pdfReaderPresentation(content)
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

    @ViewBuilder
    private func pdfReaderPresentation<Content: View>(_ content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $showPDFReader, onDismiss: {
            openPDFElement = nil
            openPDFPageIndex = 0
        }) {
            pdfWorkspaceContent
        }
        #else
        content.sheet(isPresented: $showPDFReader, onDismiss: {
            openPDFElement = nil
            openPDFPageIndex = 0
        }) {
            pdfWorkspaceContent
                .frame(minWidth: 900, minHeight: 700)
        }
        #endif
    }

    @ViewBuilder
    private var pdfWorkspaceContent: some View {
                if let pdf = openPDFElement {
                    PDFWorkspaceView(
                        element: pdf,
                        canvasID: activeContentCanvasID,
                        initialPageIndex: openPDFPageIndex,
                        onExtract: { payload in
                            createTextCard(from: payload, source: pdf)
                        },
                        onPlacePages: { requests in
                            placePDFPages(requests, source: pdf)
                        }
                    )
                }
    }

    private func createTextCard(from payload: PDFSelectionPayload, source: PDFElementModel) {
        let existingExtracts = textElements.filter {
            $0.sourcePDFDocumentID == source.resolvedDocumentID
        }.count
        let point = CGPoint(
            x: source.x + source.width / 2 + 210,
            y: source.y + Double(existingExtracts % 5) * 54
        )
        _ = vm.textVM.addPDFExtract(
            canvasID: activeContentCanvasID,
            payload: payload,
            documentID: source.resolvedDocumentID,
            canvasPoint: point,
            zIndex: LayersViewModel.nextZ(among: allLayerableElements),
            context: context,
            undoManager: vm.undoManager
        )
    }

    private func placePDFPages(_ requests: [PDFPagePlacementRequest], source: PDFElementModel) {
        _ = vm.pdfPageVM.addPages(
            source: source,
            requests: requests,
            canvasID: activeContentCanvasID,
            zIndex: LayersViewModel.nextZ(among: allLayerableElements),
            boundary: elementInteractionBoundary,
            context: context,
            undoManager: vm.undoManager
        )
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
            .alert("Scanner", isPresented: scannerAlertBinding) {
                Button("OK", role: .cancel) { scannerAlertMessage = nil }
            } message: {
                Text(scannerAlertMessage ?? "")
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

    private var scannerAlertBinding: Binding<Bool> {
        Binding(
            get: { scannerAlertMessage != nil },
            set: { isPresented in
                if !isPresented { scannerAlertMessage = nil }
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
        let groups = fetchElementGroups(canvasID: contentCanvasID)
        let texts = fetchTextElements(canvasID: contentCanvasID)
        let stickies = fetchStickyNotes(canvasID: contentCanvasID)
        let todos = fetchTodoLists(canvasID: contentCanvasID)
        let todoIDs = todos.map(\.id)
        let tasks = fetchTodoTasks(listIDs: todoIDs)
        let shapes = fetchShapes(canvasID: contentCanvasID)
        let images = fetchImages(canvasID: contentCanvasID)
        let pdfs = fetchPDFs(canvasID: contentCanvasID)
        let pdfPages = fetchPDFPages(canvasID: contentCanvasID)
        let pdfHighlights = fetchPDFHighlights(canvasID: contentCanvasID)
        let pdfInkLayers = fetchPDFInkLayers(canvasID: contentCanvasID)
        let tables = fetchTables(canvasID: contentCanvasID)
        let tableIDs = tables.map(\.id)
        let cells = fetchTableCells(tableIDs: tableIDs)
        let audio = fetchAudio(canvasID: contentCanvasID)
        let youtube = fetchYouTube(canvasID: contentCanvasID)
        let drawings = fetchDrawings(canvasID: contentCanvasID)
        let connectors = fetchConnectors(canvasID: contentCanvasID)
        let symbols = fetchSymbols(canvasID: contentCanvasID)

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
            for page in pdfPages { await PDFWorkspaceSyncService.shared.delete(page) }
            for highlight in pdfHighlights { await PDFWorkspaceSyncService.shared.delete(highlight) }
            for ink in pdfInkLayers { await PDFWorkspaceSyncService.shared.delete(ink) }
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
        pdfPages.forEach { context.delete($0) }
        pdfHighlights.forEach { context.delete($0) }
        pdfInkLayers.forEach { context.delete($0) }
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
        refreshViewportContent()
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

    private func lassoOverlay(geo: GeometryProxy) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasViewportCoordinateSpace))
                        .onChanged { value in
                            lassoFeedbackText = nil
                            appendLassoPoint(value.location)
                        }
                        .onEnded { _ in
                            finishLassoSelection()
                        }
                )

            lassoDrawingLayer
                .allowsHitTesting(false)

            lassoModePill
                .padding(.top, 16)
                .padding(.horizontal, 16)
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .zIndex(130)
        .transition(.opacity)
    }

    private var lassoModePill: some View {
        HStack(spacing: 10) {
            Image(systemName: "lasso")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(lassoFeedbackText ?? "Draw around items")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Release to select")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                cancelLassoSelection()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel lasso")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: 260)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private var lassoDrawingLayer: some View {
        Canvas { context, _ in
            guard let first = lassoPoints.first else { return }

            var strokePath = Path()
            strokePath.move(to: first)
            for point in lassoPoints.dropFirst() {
                strokePath.addLine(to: point)
            }

            if lassoPoints.count > 2 {
                var fillPath = strokePath
                fillPath.closeSubpath()
                context.fill(fillPath, with: .color(Color.accentColor.opacity(0.10)))
            }

            context.stroke(
                strokePath,
                with: .color(Color.accentColor),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round, dash: [8, 5])
            )
        }
    }

    private func fetchElementGroups(canvasID: UUID) -> [CanvasElementGroupModel] {
        (try? context.fetch(FetchDescriptor<CanvasElementGroupModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchTextElements(canvasID: UUID) -> [TextElementModel] {
        (try? context.fetch(FetchDescriptor<TextElementModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchStickyNotes(canvasID: UUID) -> [StickyNoteModel] {
        (try? context.fetch(FetchDescriptor<StickyNoteModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchTodoLists(canvasID: UUID) -> [TodoListModel] {
        (try? context.fetch(FetchDescriptor<TodoListModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchTodoTasks(listIDs: [UUID]) -> [TodoTaskModel] {
        guard !listIDs.isEmpty else { return [] }
        return (try? context.fetch(FetchDescriptor<TodoTaskModel>(
            predicate: #Predicate { listIDs.contains($0.listID) }
        ))) ?? []
    }

    private func fetchShapes(canvasID: UUID) -> [ShapeElementModel] {
        (try? context.fetch(FetchDescriptor<ShapeElementModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchImages(canvasID: UUID) -> [ImageElementModel] {
        (try? context.fetch(FetchDescriptor<ImageElementModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchPDFs(canvasID: UUID) -> [PDFElementModel] {
        (try? context.fetch(FetchDescriptor<PDFElementModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchPDFPages(canvasID: UUID) -> [PDFPageElementModel] {
        (try? context.fetch(FetchDescriptor<PDFPageElementModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchPDFHighlights(canvasID: UUID) -> [PDFHighlightModel] {
        (try? context.fetch(FetchDescriptor<PDFHighlightModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchPDFInkLayers(canvasID: UUID) -> [PDFInkLayerModel] {
        (try? context.fetch(FetchDescriptor<PDFInkLayerModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchTables(canvasID: UUID) -> [TableElementModel] {
        (try? context.fetch(FetchDescriptor<TableElementModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchTableCells(tableIDs: [UUID]) -> [TableCellModel] {
        guard !tableIDs.isEmpty else { return [] }
        return (try? context.fetch(FetchDescriptor<TableCellModel>(
            predicate: #Predicate { tableIDs.contains($0.tableID) }
        ))) ?? []
    }

    private func fetchAudio(canvasID: UUID) -> [AudioElementModel] {
        (try? context.fetch(FetchDescriptor<AudioElementModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchYouTube(canvasID: UUID) -> [YouTubeElementModel] {
        (try? context.fetch(FetchDescriptor<YouTubeElementModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchDrawings(canvasID: UUID) -> [DrawingElementModel] {
        (try? context.fetch(FetchDescriptor<DrawingElementModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchConnectors(canvasID: UUID) -> [ConnectorModel] {
        (try? context.fetch(FetchDescriptor<ConnectorModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func fetchSymbols(canvasID: UUID) -> [SymbolElementModel] {
        (try? context.fetch(FetchDescriptor<SymbolElementModel>(
            predicate: #Predicate { $0.canvasID == canvasID }
        ))) ?? []
    }

    private func startLassoSelection() {
        dismissEverything()
        withAnimation(.spring(duration: 0.24)) {
            selection.exit()
            isLassoModeActive = true
            lassoPoints = []
            lassoFeedbackText = nil
        }
    }

    private func cancelLassoSelection() {
        withAnimation(.spring(duration: 0.2)) {
            isLassoModeActive = false
            lassoPoints = []
            lassoFeedbackText = nil
        }
    }

    private func appendLassoPoint(_ point: CGPoint) {
        guard let last = lassoPoints.last else {
            lassoPoints = [point]
            return
        }

        let dx = point.x - last.x
        let dy = point.y - last.y
        guard hypot(dx, dy) >= 2.5 else { return }
        lassoPoints.append(point)
    }

    private func finishLassoSelection() {
        guard lassoPoints.count >= 3 else {
            lassoPoints = []
            lassoFeedbackText = "Draw a larger loop"
            return
        }

        let selectedIDs = selectedElementIDs(inLasso: lassoPoints)
        lassoPoints = []

        guard !selectedIDs.isEmpty else {
            lassoFeedbackText = "No items selected"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                if isLassoModeActive {
                    lassoFeedbackText = nil
                }
            }
            return
        }

        withAnimation(.spring(duration: 0.28)) {
            selection.isMultiSelectActive = true
            selection.selectedIDs = selectedIDs
            isLassoModeActive = false
            lassoFeedbackText = nil
        }
    }

    private func selectedElementIDs(inLasso points: [CGPoint]) -> Set<UUID> {
        let polygonBounds = boundingRect(for: points).insetBy(dx: -8, dy: -8)
        var ids = Set<UUID>()

        for element in allLayerableElements {
            guard let bounds = boundsMap[element.id] else { continue }
            let rect = screenRect(for: bounds.rect).insetBy(dx: -8, dy: -8)
            guard rect.intersects(polygonBounds),
                  lasso(points, intersects: rect) else { continue }
            ids.formUnion(multiSelectIDs(for: element))
        }

        return ids
    }

    private func lasso(_ points: [CGPoint], intersects rect: CGRect) -> Bool {
        let rectPoints = [
            CGPoint(x: rect.midX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]

        if rectPoints.contains(where: { contains(point: $0, inPolygon: points) }) {
            return true
        }

        if points.contains(where: { rect.contains($0) }) {
            return true
        }

        return polygonSegments(points).contains { segment in
            lineSegment(segment.0, segment.1, intersects: rect)
        }
    }

    private func boundingRect(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func contains(point: CGPoint, inPolygon polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }

        var isInside = false
        var previous = polygon[polygon.count - 1]

        for current in polygon {
            let crossesY = (current.y > point.y) != (previous.y > point.y)
            if crossesY {
                let denominator = previous.y - current.y
                guard abs(denominator) > 0.0001 else {
                    previous = current
                    continue
                }
                let slopeX = (previous.x - current.x) * (point.y - current.y)
                    / denominator + current.x
                if point.x < slopeX {
                    isInside.toggle()
                }
            }
            previous = current
        }

        return isInside
    }

    private func polygonSegments(_ points: [CGPoint]) -> [(CGPoint, CGPoint)] {
        guard points.count >= 2 else { return [] }

        var segments = zip(points, points.dropFirst()).map { ($0, $1) }
        if let first = points.first, let last = points.last {
            segments.append((last, first))
        }
        return segments
    }

    private func lineSegment(_ a: CGPoint, _ b: CGPoint, intersects rect: CGRect) -> Bool {
        if rect.contains(a) || rect.contains(b) { return true }

        let edges = [
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY))
        ]

        return edges.contains { edge in
            lineSegmentsIntersect(a, b, edge.0, edge.1)
        }
    }

    private func lineSegmentsIntersect(_ p1: CGPoint,
                                       _ p2: CGPoint,
                                       _ p3: CGPoint,
                                       _ p4: CGPoint) -> Bool {
        let d1 = direction(p3, p4, p1)
        let d2 = direction(p3, p4, p2)
        let d3 = direction(p1, p2, p3)
        let d4 = direction(p1, p2, p4)
        let epsilon: CGFloat = 0.0001

        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
            ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }

        return abs(d1) < epsilon && point(p1, isOnSegmentFrom: p3, to: p4)
            || abs(d2) < epsilon && point(p2, isOnSegmentFrom: p3, to: p4)
            || abs(d3) < epsilon && point(p3, isOnSegmentFrom: p1, to: p2)
            || abs(d4) < epsilon && point(p4, isOnSegmentFrom: p1, to: p2)
    }

    private func direction(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (c.x - a.x) * (b.y - a.y) - (b.x - a.x) * (c.y - a.y)
    }

    private func point(_ point: CGPoint, isOnSegmentFrom start: CGPoint, to end: CGPoint) -> Bool {
        point.x >= min(start.x, end.x)
            && point.x <= max(start.x, end.x)
            && point.y >= min(start.y, end.y)
            && point.y <= max(start.y, end.y)
    }

    @ViewBuilder
    private var multiSelectDragLayer: some View {
        if let bounds = selectedMultiSelectBounds {
            multiSelectDragView(bounds: bounds)
        }
    }

    private var selectedMultiSelectBounds: CGRect? {
        let rects = selection.selectedIDs.compactMap { id in
            boundsMap[id]?.rect
        }
        guard var union = rects.first else { return nil }

        for rect in rects.dropFirst() {
            union = union.union(rect)
        }

        return union.insetBy(dx: -18, dy: -18)
    }

    private func multiSelectDragView(bounds: CGRect) -> some View {
        let safeScale = max(vm.scale, 0.01)
        let minimumHitSize = 88 / safeScale
        let hitWidth = max(bounds.width, minimumHitSize)
        let hitHeight = max(bounds.height, minimumHitSize)
        let isDragging = multiSelectDragOffset != .zero

        return ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.clear)
                .contentShape(RoundedRectangle(cornerRadius: 14))

            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    Color.blue.opacity(isDragging ? 0.95 : 0.78),
                    style: StrokeStyle(
                        lineWidth: max(1.5 / safeScale, 0.6),
                        dash: [8 / safeScale, 5 / safeScale]
                    )
                )
                .frame(width: bounds.width, height: bounds.height)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.blue.opacity(isDragging ? 0.075 : 0.045))
                        .frame(width: bounds.width, height: bounds.height)
                )
                .allowsHitTesting(false)

            HStack(spacing: 6) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 12, weight: .bold))
                Text("Move")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Color.blue, in: Capsule())
            .scaleEffect(1 / safeScale)
            .offset(y: -bounds.height / 2 - 28 / safeScale)
            .allowsHitTesting(false)
        }
        .frame(width: hitWidth, height: hitHeight)
        .position(
            x: bounds.midX + multiSelectDragOffset.width,
            y: bounds.midY + multiSelectDragOffset.height
        )
        .zIndex(17000)
        .gesture(multiSelectDragGesture)
        .animation(.spring(response: 0.22, dampingFraction: 0.88), value: selection.selectedIDs)
    }

    private var multiSelectDragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard selection.hasSelection, !isCanvasGestureActive else { return }
                multiSelectDragOffset = value.translation
            }
            .onEnded { value in
                guard selection.hasSelection else {
                    multiSelectDragOffset = .zero
                    return
                }
                moveSelectedElements(by: value.translation)
                multiSelectDragOffset = .zero
            }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 16)
        .zIndex(95)
    }

    private var processingStatusText: String {
        pendingScannerOutputMode == .pdf ? "Preparing scan..." : "Extracting text..."
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
        let collection = elementCollection

        return collection.layerableElements.compactMap { element in
            guard collection.bounds(for: element).contains(canvasPoint: canvasPoint, hitSlop: hitSlop) else {
                return nil
            }

            return CanvasStackPickerItem(
                id: element.id,
                title: element.layerTitle,
                icon: element.layerIcon,
                tint: element.layerTint,
                zIndex: element.zIndex
            )
        }
        .sorted {
            if $0.zIndex == $1.zIndex { return $0.title < $1.title }
            return $0.zIndex > $1.zIndex
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

    private func selectionDragOffset(for element: any LayerableElement) -> CGSize {
        if selection.isMultiSelectActive,
           selection.selectedIDs.contains(element.id) {
            return multiSelectDragOffset
        }

        return groupDragOffset(for: element)
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

    private func moveSelectedElements(by translation: CGSize) {
        guard translation != .zero else { return }
        let members = selection.selectedIDs.compactMap { layerableElement(withID: $0) }
        guard !members.isEmpty else { return }

        moveElements(members, by: translation, undoLabel: "Move Selection")
    }

    private func moveElements(_ elements: [any LayerableElement],
                              by translation: CGSize,
                              undoLabel: String) {
        let uniqueElements = Array(
            Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        )
        guard !uniqueElements.isEmpty else { return }

        let before = uniqueElements.map { ElementPositionSnapshot(id: $0.id, x: $0.x, y: $0.y) }
        let now = Date()

        for element in uniqueElements {
            element.x += Double(translation.width)
            element.y += Double(translation.height)
            element.updatedAt = now
        }

        try? context.save()

        Task {
            for element in uniqueElements {
                await syncElement(element)
            }
        }

        let after = uniqueElements.map { ElementPositionSnapshot(id: $0.id, x: $0.x, y: $0.y) }

        vm.undoManager.push(CanvasAction(
            undo: {
                applyElementPositionSnapshots(before)
            },
            redo: {
                applyElementPositionSnapshots(after)
            }
        ))
    }

    private func applyElementPositionSnapshots(_ snapshots: [ElementPositionSnapshot]) {
        let now = Date()
        var changed: [any LayerableElement] = []

        for snapshot in snapshots {
            guard let element = layerableElement(withID: snapshot.id) else { continue }
            element.x = snapshot.x
            element.y = snapshot.y
            element.updatedAt = now
            changed.append(element)
        }

        guard !changed.isEmpty else { return }
        try? context.save()
        Task {
            for element in changed {
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
        await CanvasElementSyncRouter.upsert(element)
    }

    #if os(macOS)
    private var canvasShortcutInputIsBlocked: Bool {
        showCommandPalette ||
        vm.showTextSheet ||
        vm.showShapePicker ||
        vm.showSymbolPicker ||
        vm.showImagePicker ||
        vm.showImageSourcePicker ||
        vm.showCameraPicker ||
        vm.showScanner ||
        vm.showPDFPicker ||
        vm.showAudioPicker ||
        vm.showYouTubeLinkSheet ||
        vm.showTemplatePicker ||
        vm.showTableSizePicker ||
        vm.showTableCSVImporter ||
        vm.showAudioImporter ||
        showSettings ||
        showExportSheet ||
        showLayers ||
        showPaywall ||
        showDeleteAlert ||
        showRenameAlert ||
        showPDFReader ||
        showPDFImporter ||
        showTableSizePicker ||
        showCSVExporter ||
        showDrawingModePicker ||
        openPDFElement != nil ||
        pageForRename != nil ||
        pagePendingDeletion != nil ||
        scannerAlertMessage != nil ||
        stackPicker != nil ||
        vm.textVM.inlineEditingID != nil ||
        vm.stickyVM.writingID != nil ||
        vm.todoVM.editingID != nil ||
        vm.tableVM.editingCellID != nil ||
        macTextInputIsFirstResponder
    }

    private var macTextInputIsFirstResponder: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField || responder is NSComboBox
    }

    private func spacePanLayer(geo: GeometryProxy) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: geo.size.width, height: geo.size.height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isCanvasNavigationGestureInProgress {
                            beginCanvasNavigationGesture()
                        }
                        updateCanvasNavigationPan(value.translation)
                    }
                    .onEnded { _ in
                        endCanvasNavigationGesture(viewportSize: geo.size)
                    }
            )
            .zIndex(25000)
    }

    private func handleCanvasKeyEvent(_ event: NSEvent, viewportSize: CGSize) -> Bool {
        let characters = (event.charactersIgnoringModifiers ?? event.characters ?? "").lowercased()
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = modifiers.contains(.command)
        let hasShift = modifiers.contains(.shift)
        let hasOption = modifiers.contains(.option)
        let hasControl = modifiers.contains(.control)
        let plain = !hasCommand && !hasOption && !hasControl
        let keyCode = Int(event.keyCode)

        if keyCode == 49, event.type == .keyUp, isSpacePanActive {
            isSpacePanActive = false
            if isCanvasNavigationGestureInProgress {
                endCanvasNavigationGesture(viewportSize: viewportSize)
            }
            return true
        }

        if canvasShortcutInputIsBlocked {
            return false
        }

        if keyCode == 49 {
            if event.type == .keyDown, plain {
                isSpacePanActive = true
                return true
            }
            if event.type == .keyUp {
                isSpacePanActive = false
                if isCanvasNavigationGestureInProgress {
                    endCanvasNavigationGesture(viewportSize: viewportSize)
                }
                return true
            }
        }

        guard event.type == .keyDown else { return false }

        if hasCommand && !hasOption && !hasControl && characters == "k" {
            showCommandPalette = true
            return true
        }

        if keyCode == 53 {
            cancelCanvasShortcutMode()
            return true
        }

        if hasCommand && !hasOption && !hasControl && characters == "d" {
            duplicateShortcutSelection()
            return true
        }

        if hasCommand && !hasOption && !hasControl && characters == "g" {
            if hasShift {
                ungroupShortcutSelection()
            } else {
                groupShortcutSelection()
            }
            return true
        }

        if plain {
            switch keyCode {
            case 51, 117:
                deleteShortcutSelection()
                return true
            case 126:
                nudgeShortcutSelection(CGSize(width: 0, height: hasShift ? -10 : -1))
                return true
            case 125:
                nudgeShortcutSelection(CGSize(width: 0, height: hasShift ? 10 : 1))
                return true
            case 123:
                nudgeShortcutSelection(CGSize(width: hasShift ? -10 : -1, height: 0))
                return true
            case 124:
                nudgeShortcutSelection(CGSize(width: hasShift ? 10 : 1, height: 0))
                return true
            default:
                break
            }
        }

        if plain && characters == "[" {
            adjustShortcutSelectionLayer(forward: false)
            return true
        }

        if plain && characters == "]" {
            adjustShortcutSelectionLayer(forward: true)
            return true
        }

        guard plain && !hasShift else { return false }

        switch characters {
        case "t":
            openTextShortcut(viewportSize: viewportSize)
        case "n":
            addStickyAtCenter(viewportSize: viewportSize)
        case "d":
            openDrawingTool(at: viewportCenter(viewportSize))
        case "s":
            openShapePicker(at: viewportCenter(viewportSize))
        case "l":
            startLassoSelection()
        case "m":
            settings.canvasMinimapVisible.toggle()
        case "p":
            settings.canvasPagesPanelVisible.toggle()
            if settings.canvasPagesPanelVisible { showPagesPanel = false }
        default:
            return false
        }

        return true
    }

    private func canvasCommandPaletteActions(viewportSize: CGSize) -> [CanvasCommandPaletteAction] {
        let hasAnySelection = selection.hasSelection || activeSelectedElementID != nil || selectedGroupID != nil
        let canGroup = selection.count >= 2
        let canUngroup = selectedGroupID != nil || selectedGroupForUngroup != nil

        return [
            CanvasCommandPaletteAction(
                id: "add-text",
                title: "Add Text",
                subtitle: "Create a formatted text object at the canvas center.",
                shortcut: "T",
                systemImage: "textformat",
                tint: .blue,
                isEnabled: true
            ) { openTextShortcut(viewportSize: viewportSize) },
            CanvasCommandPaletteAction(
                id: "add-sticky",
                title: "Add Sticky Note",
                subtitle: "Drop a sticky note at the canvas center.",
                shortcut: "N",
                systemImage: "note.text",
                tint: .orange,
                isEnabled: true
            ) { addStickyAtCenter(viewportSize: viewportSize) },
            CanvasCommandPaletteAction(
                id: "drawing-mode",
                title: "Drawing Mode",
                subtitle: "Open the drawing options for sketching or handwriting.",
                shortcut: "D",
                systemImage: "pencil.and.scribble",
                tint: .orange,
                isEnabled: true
            ) { openDrawingTool(at: viewportCenter(viewportSize)) },
            CanvasCommandPaletteAction(
                id: "add-shape",
                title: "Add Shape",
                subtitle: "Choose a line, rectangle, circle, triangle, or polygon.",
                shortcut: "S",
                systemImage: "square.on.circle",
                tint: .purple,
                isEnabled: true
            ) { openShapePicker(at: viewportCenter(viewportSize)) },
            CanvasCommandPaletteAction(
                id: "lasso",
                title: "Lasso Select",
                subtitle: "Draw around canvas objects to select them together.",
                shortcut: "L",
                systemImage: "lasso",
                tint: .blue,
                isEnabled: true
            ) { startLassoSelection() },
            CanvasCommandPaletteAction(
                id: "add-pdf",
                title: "Add PDF",
                subtitle: "Place a PDF document on this canvas.",
                shortcut: "",
                systemImage: "doc.richtext",
                tint: .red,
                isEnabled: true
            ) { openPDFPicker(at: viewportCenter(viewportSize)) },
            CanvasCommandPaletteAction(
                id: "scan",
                title: "Scan Document",
                subtitle: "Scan to text or PDF when document scanning is available.",
                shortcut: "",
                systemImage: "doc.viewfinder",
                tint: .teal,
                isEnabled: true
            ) { openScanner(at: viewportCenter(viewportSize)) },
            CanvasCommandPaletteAction(
                id: "export",
                title: "Export PNG or PDF",
                subtitle: "Open the export panel for all content or the current view.",
                shortcut: "",
                systemImage: "square.and.arrow.up",
                tint: .green,
                isEnabled: true
            ) { showExportSheet = true },
            CanvasCommandPaletteAction(
                id: "background",
                title: "Change Background",
                subtitle: "Open Canvas Settings for background colors and grid style.",
                shortcut: "",
                systemImage: "paintpalette",
                tint: .mint,
                isEnabled: true
            ) { showSettings = true },
            CanvasCommandPaletteAction(
                id: "toggle-minimap",
                title: settings.canvasMinimapVisible ? "Hide Minimap" : "Show Minimap",
                subtitle: "Hide or show the canvas minimap button.",
                shortcut: "M",
                systemImage: "map",
                tint: .cyan,
                isEnabled: true
            ) { settings.canvasMinimapVisible.toggle() },
            CanvasCommandPaletteAction(
                id: "toggle-pages",
                title: settings.canvasPagesPanelVisible ? "Hide Pages" : "Show Pages",
                subtitle: "Hide or show the pages switcher on the canvas.",
                shortcut: "P",
                systemImage: "rectangle.on.rectangle.angled",
                tint: .indigo,
                isEnabled: true
            ) {
                settings.canvasPagesPanelVisible.toggle()
                if settings.canvasPagesPanelVisible { showPagesPanel = false }
            },
            CanvasCommandPaletteAction(
                id: "duplicate-selection",
                title: "Duplicate Selection",
                subtitle: "Copy the selected item, group, or multi-selection.",
                shortcut: "⌘D",
                systemImage: "plus.square.on.square",
                tint: .blue,
                isEnabled: hasAnySelection
            ) { duplicateShortcutSelection() },
            CanvasCommandPaletteAction(
                id: "delete-selection",
                title: "Delete Selection",
                subtitle: "Remove the selected item, group, or multi-selection.",
                shortcut: "⌫",
                systemImage: "trash",
                tint: .red,
                isEnabled: hasAnySelection
            ) { deleteShortcutSelection() },
            CanvasCommandPaletteAction(
                id: "group-selection",
                title: "Group Selection",
                subtitle: "Group two or more selected canvas objects.",
                shortcut: "⌘G",
                systemImage: "square.stack.3d.up.fill",
                tint: .purple,
                isEnabled: canGroup
            ) { groupShortcutSelection() },
            CanvasCommandPaletteAction(
                id: "ungroup-selection",
                title: "Ungroup Selection",
                subtitle: "Release the selected group back into individual objects.",
                shortcut: "⌘⇧G",
                systemImage: "square.stack.3d.down.right",
                tint: .purple,
                isEnabled: canUngroup
            ) { ungroupShortcutSelection() },
            CanvasCommandPaletteAction(
                id: "send-backward",
                title: "Send Backward",
                subtitle: "Move the selected object one layer back.",
                shortcut: "[",
                systemImage: "square.2.layers.3d.bottom.filled",
                tint: .secondary,
                isEnabled: hasAnySelection
            ) { adjustShortcutSelectionLayer(forward: false) },
            CanvasCommandPaletteAction(
                id: "bring-forward",
                title: "Bring Forward",
                subtitle: "Move the selected object one layer forward.",
                shortcut: "]",
                systemImage: "square.2.layers.3d.top.filled",
                tint: .secondary,
                isEnabled: hasAnySelection
            ) { adjustShortcutSelectionLayer(forward: true) },
            CanvasCommandPaletteAction(
                id: "open-layers",
                title: "Open Layers",
                subtitle: "Select or reorder canvas objects from the layer list.",
                shortcut: "",
                systemImage: "square.3.layers.3d",
                tint: .brown,
                isEnabled: true
            ) { showLayers = true }
        ]
    }

    private func viewportCenter(_ size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func openTextShortcut(viewportSize: CGSize) {
        dismissEverything()
        lastMenuLocation = viewportCenter(viewportSize)
        vm.showTextSheet = true
    }

    private func cancelCanvasShortcutMode() {
        isSpacePanActive = false
        showCommandPalette = false
        isLassoModeActive = false
        lassoPoints = []
        lassoFeedbackText = nil
        if selection.isMultiSelectActive {
            withAnimation(.spring(duration: 0.25)) { selection.exit() }
        }
        vm.connectorVM.exitConnectMode()
        dismissEverything()
    }

    private func duplicateShortcutSelection() {
        if selection.hasSelection {
            duplicateSelected()
        } else if let selectedGroupID {
            duplicateGroup(selectedGroupID)
        } else if let id = activeSelectedElementID,
                  let element = layerableElement(withID: id) {
            duplicateElement(element)
        }
    }

    private func deleteShortcutSelection() {
        if selection.hasSelection {
            deleteSelected()
        } else if let selectedGroupID {
            deleteGroupContents(selectedGroupID)
        } else if let id = activeSelectedElementID,
                  let element = layerableElement(withID: id) {
            vm.deleteLayerableElement(
                element,
                todoTasks: todoTasks,
                tableCells: tableCells,
                connectors: connectors,
                context: context
            )
            cleanupEmptyGroups()
            dismissEverything()
        }
    }

    private func groupShortcutSelection() {
        guard selection.count >= 2 else { return }
        groupSelected()
    }

    private func ungroupShortcutSelection() {
        if let selectedGroupID {
            ungroup(selectedGroupID)
        } else if let groupID = selectedGroupForUngroup {
            ungroup(groupID)
        }
    }

    private func nudgeShortcutSelection(_ delta: CGSize) {
        if selection.hasSelection {
            moveSelectedElements(by: delta)
        } else if let selectedGroupID {
            moveGroup(selectedGroupID, by: delta)
        } else if let id = activeSelectedElementID,
                  let element = layerableElement(withID: id) {
            moveElements([element], by: delta, undoLabel: "Nudge Element")
        }
    }

    private func adjustShortcutSelectionLayer(forward: Bool) {
        let targets: [any LayerableElement]
        if selection.hasSelection {
            targets = selection.selectedIDs.compactMap { layerableElement(withID: $0) }
        } else if let selectedGroupID {
            targets = groupMembers(for: selectedGroupID)
        } else if let id = activeSelectedElementID,
                  let element = layerableElement(withID: id) {
            targets = [element]
        } else {
            targets = []
        }

        let orderedTargets = targets.sorted {
            forward ? $0.zIndex > $1.zIndex : $0.zIndex < $1.zIndex
        }

        for element in orderedTargets {
            if forward {
                layersVM.bringForward(element, in: allLayerableElements, context: context)
            } else {
                layersVM.sendBackward(element, in: allLayerableElements, context: context)
            }
        }

        Task {
            for element in orderedTargets {
                await syncElement(element)
            }
        }
    }
    #endif

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
                refreshViewportContent()
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
                refreshViewportContent()
            }
    }

    private func beginCanvasNavigationGesture() {
        let wasInProgress = isCanvasNavigationGestureInProgress
        beginCanvasGestureSuppression()

        guard !wasInProgress else { return }
        vm.lastOffset = vm.offset
        vm.lastScale = vm.scale
        vm.navigation.panTranslation = .zero
        vm.navigation.magnification = 1
        vm.navigation.focalPoint = nil
    }

    private func updateCanvasNavigationPan(_ translation: CGSize) {
        vm.navigation.panTranslation = translation
        applyCanvasNavigationGesture()
    }

    private func updateCanvasNavigationMagnification(_ magnification: CGFloat, focalPoint: CGPoint) {
        vm.navigation.magnification = magnification
        if vm.navigation.focalPoint == nil {
            vm.navigation.focalPoint = focalPoint
        }
        applyCanvasNavigationGesture()
    }

    private func applyCanvasNavigationGesture() {
        let baseScale = max(vm.lastScale, 0.0001)
        let nextScale = max(0.3, min(baseScale * vm.navigation.magnification, 5.0))
        let scaleDelta = nextScale / baseScale

        let zoomedOffset: CGSize
        if let focal = vm.navigation.focalPoint {
            zoomedOffset = CGSize(
                width: focal.x - (focal.x - vm.lastOffset.width) * scaleDelta,
                height: focal.y - (focal.y - vm.lastOffset.height) * scaleDelta
            )
        } else {
            zoomedOffset = vm.lastOffset
        }

        vm.scale = nextScale
        vm.offset = CGSize(
            width: zoomedOffset.width + vm.navigation.panTranslation.width,
            height: zoomedOffset.height + vm.navigation.panTranslation.height
        )
    }

    private func endCanvasNavigationGesture(viewportSize: CGSize) {
        vm.lastScale = vm.scale
        vm.lastOffset = vm.offset
        if !canvas.isInfinite {
            vm.clampOffset(to: canvasNavigationBoundary, viewportSize: viewportSize, scale: vm.scale)
        }

        vm.navigation.panTranslation = .zero
        vm.navigation.magnification = 1
        vm.navigation.focalPoint = nil
        endCanvasGestureSuppression()
        refreshViewportContent()
    }

    private func beginCanvasGestureSuppression() {
        if !isCanvasNavigationGestureInProgress {
            isCanvasNavigationGestureInProgress = true
        }
        if isCanvasGestureActive { return }
        canvasGestureSuppressionID = UUID()
        isCanvasGestureActive = true
    }

    private func endCanvasGestureSuppression() {
        isCanvasNavigationGestureInProgress = false
        let token = UUID()
        canvasGestureSuppressionID = token
        isCanvasGestureActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if canvasGestureSuppressionID == token {
                isCanvasGestureActive = false
            }
        }
    }

    private func refreshViewportContent() {
        viewportContentRevision &+= 1
    }

    /// Trackpad scroll events do not always deliver a reliable ended phase. Debounce the
    /// culling refresh while the lightweight transform continues immediately.
    private func scheduleViewportContentRefresh() {
        let token = UUID()
        vm.navigation.pendingViewportRefreshID = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard vm.navigation.pendingViewportRefreshID == token else { return }
            refreshViewportContent()
        }
    }

    private func startCanvasDrawing(mode: CanvasDrawingCaptureMode = .drawing) {
        dismissEverything()
        isCanvasHighlighterToolSelected = false
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
        isCanvasHighlighterToolSelected = element.isCanvasHighlighterDrawing
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
        guard canvasDrawingHasVisibleInk(pkDrawing),
              strokeBounds.width > 0, strokeBounds.height > 0 else {
            if let id = continuingCanvasDrawingID,
               let element = drawings.first(where: { $0.id == id }) {
                vm.drawingVM.delete(
                    element: element,
                    context: context,
                    undoManager: vm.undoManager
                )
            }
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

    /// PencilKit can keep a fully erased stroke as a masked record, so checking
    /// `strokes.isEmpty` is not enough. This follows the stroke's rendered mask
    /// ranges and only reports ink that still has at least one drawable point.
    private func canvasDrawingHasVisibleInk(_ drawing: PKDrawing) -> Bool {
        drawing.strokes.contains { stroke in
            stroke.maskedPathRanges.contains { range in
                !Array(stroke.path.interpolatedPoints(in: range, by: .distance(8))).isEmpty
            }
        }
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
        isProcessingScan = true
        defer { isProcessingScan = false }

        guard let result = recognizeHandwritingText(
            in: pkDrawing,
            bounds: recognitionBounds,
            minimumConfidence: Float(settings.handwritingToTextStrictness)
        ) else { return false }

        let blocks = handwritingTextBlocks(
            from: result,
            grouping: settings.handwritingTextGrouping
        )
        guard !blocks.isEmpty else { return false }

        if let id = continuingCanvasDrawingID,
           let element = drawings.first(where: { $0.id == id }) {
            Task { await DrawingSyncService.shared.delete(element) }
            context.delete(element)
        }

        let startingZIndex = LayersViewModel.nextZ(among: allLayerableElements)
        let placements = blocks.enumerated().map { index, block in
            let canvasPoint = CGPoint(
                x: (block.bounds.midX - effectiveOffset.width) / effectiveScale,
                y: (block.bounds.midY - effectiveOffset.height) / effectiveScale
            )
            let style = settings.handwritingTextStyle(text: block.text)

            return RecognizedHandwritingTextPlacement(
                style: style,
                canvasPoint: canvasPoint,
                zIndex: startingZIndex + index
            )
        }

        _ = vm.textVM.addRecognizedHandwritingTexts(
            canvasID: activeContentCanvasID,
            placements: placements,
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

        let lines = (request.results ?? []).compactMap { observation -> HandwritingRecognitionLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            let normalized = observation.boundingBox
            let lineBounds = CGRect(
                x: bounds.minX + normalized.minX * bounds.width,
                y: bounds.minY + (1 - normalized.maxY) * bounds.height,
                width: normalized.width * bounds.width,
                height: normalized.height * bounds.height
            )
            return HandwritingRecognitionLine(
                text: text,
                confidence: candidate.confidence,
                bounds: lineBounds
            )
        }
        .sorted {
            let verticalDifference = abs($0.bounds.midY - $1.bounds.midY)
            if verticalDifference <= max($0.bounds.height, $1.bounds.height) * 0.45 {
                return $0.bounds.minX < $1.bounds.minX
            }
            return $0.bounds.minY < $1.bounds.minY
        }

        guard !lines.isEmpty else { return nil }

        let text = lines.map(\.text).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2,
              text.rangeOfCharacter(from: .alphanumerics) != nil
        else { return nil }

        let weightedConfidence = lines.reduce(Float(0)) { partial, line in
            partial + line.confidence * Float(max(line.text.count, 1))
        }
        let totalWeight = lines.reduce(0) { $0 + max($1.text.count, 1) }
        let confidence = weightedConfidence / Float(max(totalWeight, 1))
        guard confidence >= minimumConfidence else { return nil }

        return HandwritingRecognitionResult(lines: lines, confidence: confidence)
    }

    private func handwritingTextBlocks(from result: HandwritingRecognitionResult,
                                       grouping: HandwritingTextGrouping) -> [HandwritingTextBlock] {
        switch grouping {
        case .oneBlock:
            guard let bounds = unionBounds(of: result.lines) else { return [] }
            return [HandwritingTextBlock(text: result.text, bounds: bounds)]

        case .eachLine:
            return result.lines.map {
                HandwritingTextBlock(text: $0.text, bounds: $0.bounds)
            }

        case .automatic:
            return automaticHandwritingTextBlocks(from: result.lines)
        }
    }

    private func automaticHandwritingTextBlocks(
        from lines: [HandwritingRecognitionLine]
    ) -> [HandwritingTextBlock] {
        guard !lines.isEmpty else { return [] }
        let sortedHeights = lines.map { max($0.bounds.height, 1) }.sorted()
        let medianHeight = sortedHeights[sortedHeights.count / 2]
        var unvisited = Set(lines.indices)
        var components: [[HandwritingRecognitionLine]] = []

        while let seed = unvisited.first {
            unvisited.remove(seed)
            var stack = [seed]
            var component: [HandwritingRecognitionLine] = []

            while let index = stack.popLast() {
                component.append(lines[index])
                let neighbors = unvisited.filter {
                    handwritingLinesBelongTogether(
                        lines[index],
                        lines[$0],
                        medianHeight: medianHeight
                    )
                }
                for neighbor in neighbors {
                    unvisited.remove(neighbor)
                    stack.append(neighbor)
                }
            }

            components.append(component)
        }

        return components.compactMap { component in
            let ordered = component.sorted {
                let verticalDifference = abs($0.bounds.midY - $1.bounds.midY)
                if verticalDifference <= medianHeight * 0.45 {
                    return $0.bounds.minX < $1.bounds.minX
                }
                return $0.bounds.minY < $1.bounds.minY
            }
            guard let bounds = unionBounds(of: ordered) else { return nil }

            var text = ""
            var previous: HandwritingRecognitionLine?
            for line in ordered {
                if let previous {
                    let sameVisualLine = abs(previous.bounds.midY - line.bounds.midY)
                        <= medianHeight * 0.45
                    text += sameVisualLine ? " " : "\n"
                }
                text += line.text
                previous = line
            }
            return HandwritingTextBlock(text: text, bounds: bounds)
        }
        .sorted {
            if abs($0.bounds.midY - $1.bounds.midY) <= medianHeight * 0.45 {
                return $0.bounds.minX < $1.bounds.minX
            }
            return $0.bounds.minY < $1.bounds.minY
        }
    }

    private func handwritingLinesBelongTogether(_ first: HandwritingRecognitionLine,
                                                _ second: HandwritingRecognitionLine,
                                                medianHeight: CGFloat) -> Bool {
        let a = first.bounds
        let b = second.bounds
        let verticalOverlap = max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
        let verticalOverlapRatio = verticalOverlap / max(1, min(a.height, b.height))
        let horizontalGap = max(0, max(a.minX, b.minX) - min(a.maxX, b.maxX))

        if verticalOverlapRatio >= 0.4 {
            return horizontalGap <= medianHeight * 3.5
        }

        let verticalGap = max(0, max(a.minY, b.minY) - min(a.maxY, b.maxY))
        guard verticalGap <= medianHeight * 1.35 else { return false }

        let horizontalOverlap = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
        let horizontalOverlapRatio = horizontalOverlap / max(1, min(a.width, b.width))
        let leftEdgesAreAligned = abs(a.minX - b.minX) <= medianHeight * 2
        return horizontalOverlapRatio >= 0.12 || leftEdgesAreAligned
    }

    private func unionBounds(of lines: [HandwritingRecognitionLine]) -> CGRect? {
        guard let first = lines.first else { return nil }
        return lines.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
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
        await PDFWorkspaceSyncService.shared.pullAll(canvasID: canvasID, context: context)
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
                customBackgroundColors: settings.customCanvasBackgroundColors,
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
                customBackgroundColors: settings.customCanvasBackgroundColors,
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
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(duration: 0.25), value: vm.youtubeVM.activePlayingID)
        }
    }

    private var floatingYouTubeBottomPadding: CGFloat {
        settings.toolbarPosition == .hidden ? 24 : 116
    }

    @ViewBuilder
    private func floatingYouTubePlayerLayer(geo: GeometryProxy) -> some View {
        if let activeID = vm.youtubeVM.activePlayingID,
           let video = youtubeElements.first(where: { $0.id == activeID }) {
            let availableWidth = max(240, geo.size.width - 32)
            let playerWidth = min(availableWidth, max(270, geo.size.width * 0.32))
            let playerHeight = playerWidth * 9 / 16

            VStack(spacing: 0) {
                YouTubePlayerWebView(
                    videoID: video.videoID,
                    startSeconds: video.playbackSeconds,
                    stopToken: floatingYouTubeStopToken
                ) { seconds in
                    vm.youtubeVM.finishStopPlayback(
                        for: video.id,
                        playbackSeconds: seconds,
                        element: video,
                        context: context
                    )
                    floatingYouTubeStopToken = nil
                }
                .frame(width: playerWidth, height: playerHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button {
                        floatingYouTubeStopToken = UUID()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.black.opacity(0.58), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .accessibilityLabel("Stop YouTube playback")
                }

                HStack(spacing: 8) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)

                    Text(video.title.isEmpty ? "YouTube playing" : video.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button {
                        floatingYouTubeStopToken = UUID()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.red, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop YouTube playback")
                }
                .padding(.horizontal, 10)
                .frame(width: playerWidth, height: 40)
                .background(.regularMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
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
                TextElementView(element: text, canvasScale: elementRenderScale, canvasOffset: vm.offset,
                                canvasBoundary: boundary,
                                vm: vm.textVM, isMultiSelectMode: multiSelect,
                                isSelectedInMultiSelect: isElemSelected,
                                onExternalTap: { dismissEverything() },
                                isCanvasGestureActive: childInteractionLocked)
            } else if let sticky = element as? StickyNoteModel {
                StickyNoteView(note: sticky, canvasScale: elementRenderScale, canvasBoundary: boundary,
                               vm: vm.stickyVM, isMultiSelectMode: multiSelect,
                               isSelectedInMultiSelect: isElemSelected,
                               onExternalTap: { dismissEverything() },
                               isCanvasGestureActive: childInteractionLocked)
            } else if let todo = element as? TodoListModel {
                TodoListView(list: todo, allTasks: todoTasks, canvasScale: elementRenderScale,
                             canvasBoundary: boundary, vm: vm.todoVM,
                             isMultiSelectMode: multiSelect,
                             isSelectedInMultiSelect: isElemSelected,
                             onExternalTap: { dismissEverything() },
                             isCanvasGestureActive: childInteractionLocked)
            } else if let shape = element as? ShapeElementModel {
                ShapeElementView(shape: shape, canvasScale: elementRenderScale, canvasOffset: vm.offset,
                                 canvasBoundary: boundary,
                                 vm: vm.shapeVM, isMultiSelectMode: multiSelect,
                                 isSelectedInMultiSelect: isElemSelected,
                                 onExternalTap: { dismissEverything() },
                                 isCanvasGestureActive: childInteractionLocked)
            } else if let img = element as? ImageElementModel {
                ImageElementView(element: img, canvasScale: elementRenderScale, canvasOffset: vm.offset,
                                 canvasBoundary: boundary,
                                 vm: vm.imageVM, isMultiSelectMode: multiSelect,
                                 ocrTextZIndex: nextZIndex,
                                 undoManager: vm.undoManager,
                                 isSelectedInMultiSelect: isElemSelected,
                                 onExternalTap: { dismissEverything() },
                                 isCanvasGestureActive: childInteractionLocked)
            } else if let pdf = element as? PDFElementModel {
                PDFElementView(element: pdf, canvasScale: elementRenderScale, canvasOffset: vm.offset,
                               canvasBoundary: boundary,
                               vm: vm.pdfVM, isMultiSelectMode: multiSelect,
                               isSelectedInMultiSelect: isElemSelected,
                               onOpenReader: {
                                   openPDFElement = pdf
                                   openPDFPageIndex = 0
                                   showPDFReader = true
                               },
                               onExternalTap: { dismissEverything() },
                               isCanvasGestureActive: childInteractionLocked)
            } else if let page = element as? PDFPageElementModel {
                let source = allPDFs.first { $0.resolvedDocumentID == page.documentID }
                PDFPageElementView(
                    element: page,
                    source: source,
                    highlights: pdfHighlights.filter {
                        $0.documentID == page.documentID && $0.pageIndex == page.pageIndex
                    },
                    inkLayer: pdfInkLayers.first {
                        $0.documentID == page.documentID && $0.pageIndex == page.pageIndex
                    },
                    canvasScale: elementRenderScale,
                    canvasOffset: vm.offset,
                    canvasBoundary: boundary,
                    vm: vm.pdfPageVM,
                    isMultiSelectMode: multiSelect,
                    isSelectedInMultiSelect: isElemSelected,
                    onOpenReader: {
                        guard let source else { return }
                        openPDFElement = source
                        openPDFPageIndex = page.pageIndex
                        showPDFReader = true
                    },
                    onRecrop: {
                        guard let source else { return }
                        openPDFElement = source
                        openPDFPageIndex = page.pageIndex
                        showPDFReader = true
                    },
                    onExternalTap: { dismissEverything() },
                    isCanvasGestureActive: childInteractionLocked
                )
            } else if let table = element as? TableElementModel {
                TableElementView(
                    table: table, allCells: tableCells,
                    canvasScale: elementRenderScale, canvasBoundary: boundary,
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
                AudioElementView(element: audio, canvasScale: elementRenderScale, canvasBoundary: boundary,
                                 vm: vm.audioVM, isMultiSelectMode: multiSelect,
                                 isSelectedInMultiSelect: isElemSelected,
                                 onExternalTap: { dismissEverything() },
                                 isCanvasGestureActive: childInteractionLocked)
            } else if let youtube = element as? YouTubeElementModel {
                YouTubeElementView(element: youtube, canvasScale: elementRenderScale, canvasBoundary: boundary,
                                   vm: vm.youtubeVM, isMultiSelectMode: multiSelect,
                                   isSelectedInMultiSelect: isElemSelected,
                                   usesFloatingPlayback: settings.floatingYouTubePlaybackEnabled,
                                   onExternalTap: { dismissEverything() },
                                   isCanvasGestureActive: childInteractionLocked)
            } else if let drawing = element as? DrawingElementModel {
                DrawingElementView(element: drawing, canvasScale: elementRenderScale, canvasOffset: vm.offset,
                                   canvasBoundary: boundary,
                                   vm: vm.drawingVM, isMultiSelectMode: multiSelect,
                                   isSelectedInMultiSelect: isElemSelected,
                                   onExternalTap: { dismissEverything() },
                                   onContinueCanvasDrawing: { continueCanvasDrawing($0) },
                                   isCanvasGestureActive: childInteractionLocked)
            } else if let symbol = element as? SymbolElementModel {
                // ── NEW ────────────────────────────────────────────────────────
                SymbolElementView(element: symbol, canvasScale: elementRenderScale, canvasBoundary: boundary,
                                  vm: vm.symbolVM, isMultiSelectMode: multiSelect,
                                  isSelectedInMultiSelect: isElemSelected,
                                  onExternalTap: { dismissEverything() },
                                  isCanvasGestureActive: childInteractionLocked)
            }
        }
        .opacity(vm.showCanvasDrawingOverlay && continuingCanvasDrawingID == element.id
                 ? 0
                 : layersVM.highlightedID == element.id ? 0.5 : 1)
        .zIndex((element as? DrawingElementModel)?.isCanvasHighlighterDrawing == true ? -2 : 0)
        .offset(selectionDragOffset(for: element))
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
                onScan:         { openScanner(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                onAddPDF:       { openPDFPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                onAddTable:     { openTableSizePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                onAddAudio:     { openAudioPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                onAddYouTube:   { openYouTubeLinkSheet(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                onLasso:        { startLassoSelection() },
                onDrawingTool:  { openDrawingTool(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                onAddSymbol:    { openSymbolPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                onConnect:      { toggleConnectMode() },
                isConnectModeActive: connectActive,
                lockedTools: lockedCanvasTools
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
            VStack {
                Spacer()
                CanvasToolbar(
                    showTextSheet:  $vm.showTextSheet,
                    onAddSticky:    { addStickyAtCenter(viewportSize: geo.size) },
                    onAddTodo:      { addTodoAtCenter(viewportSize: geo.size) },
                    onAddTemplate:  { openTemplatePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddShape:     { openShapePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddImage:     { openImagePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onScan:         { openScanner(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddPDF:       { openPDFPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddTable:     { openTableSizePicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddAudio:     { openAudioPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddYouTube:   { openYouTubeLinkSheet(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onLasso:        { startLassoSelection() },
                    onDrawingTool:  { openDrawingTool(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },
                    onAddSymbol:    { openSymbolPicker(at: CGPoint(x: geo.size.width/2, y: geo.size.height/2)) },  // ← NEW
                    onConnect:      { toggleConnectMode() },
                    isConnectModeActive: connectActive,
                    lockedTools: lockedCanvasTools
                )
                .padding(.horizontal, 16)
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 12) + 12)
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
        vm.shapeVM.stopEditing(); vm.imageVM.stopEditing(); vm.pdfVM.stopEditing(); vm.pdfPageVM.stopEditing()
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
        switch elementCollection.kind(forID: id) {
        case .text:
            vm.textVM.editingID = id
        case .stickyNote:
            vm.stickyVM.editingID = id
        case .todoList:
            vm.todoVM.editingID = id
        case .shape:
            vm.shapeVM.editingID = id
        case .image:
            vm.imageVM.editingID = id
        case .pdf:
            vm.pdfVM.editingID = id
        case .pdfPage:
            vm.pdfPageVM.editingID = id
        case .table:
            vm.tableVM.selectTable(id: id)
        case .audio:
            vm.audioVM.editingID = id
        case .youtube:
            vm.youtubeVM.editingID = id
        case .drawing:
            vm.drawingVM.editingID = id; vm.drawingVM.isDrawingModeActive = false
        case .symbol:
            vm.symbolVM.editingID = id
        case nil:
            break
        }
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
    private func addDrawing(at screenPoint: CGPoint) {
        dismissEverything()
        vm.drawingVM.addDrawing(canvasID: activeContentCanvasID,
                                center: screenPoint,
                                offset: vm.offset, scale: vm.scale,
                                zIndex: LayersViewModel.nextZ(among: allLayerableElements),
                                context: context, undoManager: vm.undoManager)
    }

    private func openDrawingTool(at point: CGPoint) {
        dismissEverything()
        pendingDrawingToolLocation = point
        showDrawingModePicker = true
    }

    private func handleDrawingToolMode(_ mode: CanvasDrawingToolMode, viewportSize: CGSize) {
        let point = pendingDrawingToolLocation ?? CGPoint(
            x: viewportSize.width / 2,
            y: viewportSize.height / 2
        )
        pendingDrawingToolLocation = nil
        showDrawingModePicker = false

        switch mode {
        case .sketchCard:
            addDrawing(at: point)
        case .canvasInk:
            startCanvasDrawing()
        case .handwritingText:
            startCanvasDrawing(mode: .handwritingText)
        }
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
    private func openScanner(at point: CGPoint) {
        dismissEverything()
        #if os(iOS)
        pendingScannerLocation = point
        pendingScannerOutputMode = nil
        showScannerOutputPicker = true
        #else
        scannerAlertMessage = "Scanning is available on iPhone and iPad."
        #endif
    }

    private func clearScannerFlow() {
        pendingScannerLocation = nil
        pendingScannerOutputMode = nil
        #if os(iOS)
        showScannerOutputPicker = false
        showScannerSourcePicker = false
        showScannerImagePicker = false
        selectedScannerPhotoItem = nil
        #endif
    }

    #if os(iOS)
    private func beginScannerOutput(_ mode: CanvasScannerOutputMode) {
        pendingScannerOutputMode = mode
        showScannerSourcePicker = true
    }

    private func beginScannerCameraScan() {
        guard VNDocumentCameraViewController.isSupported else {
            scannerAlertMessage = "Document scanning is not available on this device."
            clearScannerFlow()
            return
        }
        vm.showScanner = true
    }
    #endif
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
        case .scanner: openScanner(at: screenPoint)
        case .pdf:   openPDFPicker(at: screenPoint)
        case .table: openTableSizePicker(at: screenPoint)
        case .audio: openAudioPicker(at: screenPoint)
        case .youtube: openYouTubeLinkSheet(at: screenPoint)
        case .lasso: startLassoSelection()
        case .drawing: openDrawingTool(at: screenPoint)
        }
    }

    #if os(iOS)
    private func createSelectedScannerOutput(from images: [UIImage], viewportSize: CGSize) {
        switch pendingScannerOutputMode ?? .text {
        case .text:
            createOCRText(from: images, viewportSize: viewportSize)
        case .pdf:
            createDocumentFromScan(images: images, viewportSize: viewportSize)
        }
    }

    private func createOCRText(from images: [UIImage], viewportSize: CGSize) {
        guard !images.isEmpty else {
            clearScannerFlow()
            scannerAlertMessage = "No scanned pages were found."
            return
        }

        isProcessingScan = true
        Task {
            do {
                let text = try await ImageOCRService.recognizeText(images: images)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    isProcessingScan = false
                    clearScannerFlow()
                    scannerAlertMessage = "No readable text was found in this scan."
                    return
                }

                let screenPoint = pendingScannerLocation ?? CGPoint(
                    x: viewportSize.width / 2,
                    y: viewportSize.height / 2
                )
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
                clearScannerFlow()
                isProcessingScan = false
                if let textID {
                    vm.textVM.editingID = textID
                }
            } catch {
                isProcessingScan = false
                clearScannerFlow()
                scannerAlertMessage = "Could not extract text from this scan."
            }
        }
    }

    private func createDocumentFromScan(images: [UIImage], viewportSize: CGSize) {
        guard !images.isEmpty else {
            clearScannerFlow()
            scannerAlertMessage = "No scanned pages were found."
            return
        }

        isProcessingScan = true
        Task {
            let screenPoint = pendingScannerLocation ?? CGPoint(
                x: viewportSize.width / 2,
                y: viewportSize.height / 2
            )
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
            clearScannerFlow()
            isProcessingScan = false
            if let documentID {
                vm.pdfVM.editingID = documentID
            } else {
                scannerAlertMessage = "Could not place this scan on the canvas."
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
        } else if let el = element as? PDFPageElementModel {
            duplicatedID = vm.pdfPageVM.duplicate(element: el, zIndex: z, offset: offset, context: context)
            if let duplicatedID, selectCopy { vm.pdfPageVM.editingID = duplicatedID }
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
        elementCollection.element(withID: id)
    }

    private func deleteSelected() {
        for id in selection.selectedIDs {
            guard let element = layerableElement(withID: id) else { continue }
            vm.deleteLayerableElement(
                element,
                todoTasks: todoTasks,
                tableCells: tableCells,
                connectors: connectors,
                context: context
            )
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
