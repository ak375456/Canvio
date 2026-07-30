//
//  TextElementViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import Combine

struct RecognizedHandwritingTextPlacement {
    let style: TextStyle
    let canvasPoint: CGPoint
    let zIndex: Int
}

private struct RecognizedHandwritingTextRecord {
    let id: UUID
    let style: TextStyle
    let canvasPoint: CGPoint
    let zIndex: Int
}

struct TextElementHistoryState: Equatable {
    let document: RichTextDocument
    let backgroundColorName: String
    let strokeColorName: String
    let strokeWidth: Double

    init(element: TextElementModel) {
        document = element.resolvedRichTextDocument
        backgroundColorName = element.bgColorName
        strokeColorName = element.strokeColorName
        strokeWidth = element.strokeWidth
    }

    func apply(to element: TextElementModel) {
        element.setRichTextDocument(document)
        element.bgColorName = backgroundColorName
        element.strokeColorName = strokeColorName
        element.strokeWidth = strokeWidth
    }
}

@MainActor
class TextElementViewModel: ObservableObject {
    @Published var editingID: UUID?       = nil
    @Published var inlineEditingID: UUID? = nil
    private var inlineElementIsNew: Bool  = false

    // MARK: - Add (from sheet)

    func addText(canvasID: UUID, style: TextStyle, center: CGPoint,
                 offset: CGSize, scale: CGFloat, zIndex: Int,
                 context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let canvasX = (center.x - offset.width)  / scale
        let canvasY = (center.y - offset.height) / scale
        let element = TextElementModel(canvasID: canvasID, text: style.text,
                                       x: canvasX, y: canvasY)
        element.fontSize      = style.fontSize
        element.isBold        = style.isBold
        element.isItalic      = style.isItalic
        element.isUnderline   = style.isUnderline
        element.colorName     = style.colorName
        element.fontName      = style.fontName
        element.alignmentRaw  = style.alignmentRaw
        element.bgColorName     = style.bgColorName
        element.strokeColorName = style.strokeColorName
        element.strokeWidth     = style.strokeWidth
        element.zIndex        = zIndex
        element.updatedAt     = Date()
        element.rebuildRichTextFromLegacyStyle()
        context.insert(element)
        try? context.save()
        Task { await TextSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TextElementModel>())
                    .first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await TextSyncService.shared.delete(el) }
                }
            },
            redo: {
                let el = TextElementModel(canvasID: canvasID, text: style.text,
                                          x: canvasX, y: canvasY)
                el.id = id; el.fontSize = style.fontSize; el.isBold = style.isBold
                el.isItalic = style.isItalic; el.isUnderline = style.isUnderline
                el.colorName = style.colorName; el.fontName = style.fontName
                el.alignmentRaw = style.alignmentRaw
                el.bgColorName = style.bgColorName
                el.strokeColorName = style.strokeColorName
                el.strokeWidth = style.strokeWidth
                el.zIndex = zIndex
                el.updatedAt = Date()
                el.rebuildRichTextFromLegacyStyle()
                context.insert(el); try? context.save()
                Task { await TextSyncService.shared.upsert(el) }
            }
        ))
    }

    @discardableResult
    func addRecognizedHandwritingText(canvasID: UUID, style: TextStyle, canvasPoint: CGPoint,
                                      zIndex: Int, context: ModelContext,
                                      undoManager: CanvasUndoManager? = nil) -> UUID? {
        addRecognizedHandwritingTexts(
            canvasID: canvasID,
            placements: [RecognizedHandwritingTextPlacement(
                style: style,
                canvasPoint: canvasPoint,
                zIndex: zIndex
            )],
            context: context,
            undoManager: undoManager
        ).first
    }

    @discardableResult
    func addRecognizedHandwritingTexts(
        canvasID: UUID,
        placements: [RecognizedHandwritingTextPlacement],
        context: ModelContext,
        undoManager: CanvasUndoManager? = nil
    ) -> [UUID] {
        let records = placements.compactMap { placement -> RecognizedHandwritingTextRecord? in
            let trimmed = placement.style.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            var style = placement.style
            style.text = trimmed
            style.fontSize = TextStyle.clampedFontSize(style.fontSize)
            return RecognizedHandwritingTextRecord(
                id: UUID(),
                style: style,
                canvasPoint: placement.canvasPoint,
                zIndex: placement.zIndex
            )
        }
        guard !records.isEmpty else { return [] }

        let elements = records.map { record in
            makeRecognizedHandwritingElement(canvasID: canvasID, record: record)
        }
        for element in elements { context.insert(element) }
        try? context.save()
        editingID = elements.last?.id
        Task {
            for element in elements {
                await TextSyncService.shared.upsert(element)
            }
        }

        let ids = records.map(\.id)
        undoManager?.push(CanvasAction(
            undo: {
                let allText = (try? context.fetch(FetchDescriptor<TextElementModel>())) ?? []
                let matches = allText.filter { ids.contains($0.id) }
                for element in matches { context.delete(element) }
                try? context.save()
                Task {
                    for element in matches {
                        await TextSyncService.shared.delete(element)
                    }
                }
            },
            redo: {
                let restored = records.map { record in
                    self.makeRecognizedHandwritingElement(canvasID: canvasID, record: record)
                }
                for element in restored { context.insert(element) }
                try? context.save()
                Task {
                    for element in restored {
                        await TextSyncService.shared.upsert(element)
                    }
                }
            }
        ))

        return ids
    }

    private func makeRecognizedHandwritingElement(
        canvasID: UUID,
        record: RecognizedHandwritingTextRecord
    ) -> TextElementModel {
        let style = record.style
        let element = TextElementModel(
            canvasID: canvasID,
            text: style.text,
            x: record.canvasPoint.x,
            y: record.canvasPoint.y
        )
        element.id = record.id
        element.fontSize = style.fontSize
        element.isBold = style.isBold
        element.isItalic = style.isItalic
        element.isUnderline = style.isUnderline
        element.colorName = style.colorName
        element.fontName = style.fontName
        element.alignmentRaw = style.alignmentRaw
        element.bgColorName = style.bgColorName
        element.strokeColorName = style.strokeColorName
        element.strokeWidth = style.strokeWidth
        element.zIndex = record.zIndex
        element.updatedAt = Date()
        element.rebuildRichTextFromLegacyStyle()
        return element
    }

    // MARK: - Add inline (double-tap on canvas)

    func addInlineText(canvasID: UUID, style: TextStyle, canvasPoint: CGPoint, zIndex: Int,
                       context: ModelContext,
                       undoManager: CanvasUndoManager? = nil) -> TextElementModel {
        let element = TextElementModel(canvasID: canvasID, text: "",
                                       x: canvasPoint.x, y: canvasPoint.y)
        element.fontSize = TextStyle.clampedFontSize(style.fontSize)
        element.isBold = style.isBold
        element.isItalic = style.isItalic
        element.isUnderline = style.isUnderline
        element.colorName = style.colorName
        element.fontName = style.fontName
        element.alignmentRaw = style.alignmentRaw
        element.bgColorName = style.bgColorName
        element.strokeColorName = style.strokeColorName
        element.strokeWidth = style.strokeWidth
        element.zIndex = zIndex
        element.updatedAt = Date()
        element.rebuildRichTextFromLegacyStyle()
        context.insert(element)
        try? context.save()
        inlineEditingID    = element.id
        editingID          = element.id
        inlineElementIsNew = true
        return element
    }

    func commitInlineText(element: TextElementModel, text: String, fontSize: Double? = nil,
                          fontName: String? = nil,
                          colorName: String? = nil,
                          context: ModelContext,
                          undoManager: CanvasUndoManager? = nil) {
        let oldState = TextElementHistoryState(element: element)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasNew  = inlineElementIsNew
        inlineElementIsNew = false
        inlineEditingID    = nil

        if trimmed.isEmpty {
            if editingID == element.id { editingID = nil }
            context.delete(element)
            try? context.save()
            return
        }

        if let fontSize {
            element.fontSize = TextStyle.clampedFontSize(fontSize)
        }
        if let fontName {
            element.fontName = fontName
        }
        if let colorName {
            element.colorName = colorName
        }
        element.setRichTextDocument(
            element.resolvedRichTextDocument.replacingPlainText(
                trimmed,
                attributes: element.baseRichTextAttributes
            )
        )
        element.updatedAt = Date()
        try? context.save()
        Task { await TextSyncService.shared.upsert(element) }

        if wasNew {
            let id       = element.id
            let canvasID = element.canvasID
            let x        = element.x
            let y        = element.y
            let zIndex   = element.zIndex
            let fontSize = element.fontSize
            let isBold = element.isBold
            let isItalic = element.isItalic
            let isUnderline = element.isUnderline
            let colorName = element.colorName
            let fontName = element.fontName
            let alignmentRaw = element.alignmentRaw
            let bgColorName = element.bgColorName
            let strokeColorName = element.strokeColorName
            let strokeWidth = element.strokeWidth
            undoManager?.push(CanvasAction(
                name: "Add text",
                undo: {
                    if let el = try? context.fetch(FetchDescriptor<TextElementModel>())
                        .first(where: { $0.id == id }) {
                        context.delete(el); try? context.save()
                        Task { await TextSyncService.shared.delete(el) }
                    }
                },
                redo: {
                    let el = TextElementModel(canvasID: canvasID, text: trimmed, x: x, y: y)
                    el.id = id
                    el.zIndex = zIndex
                    el.fontSize = fontSize
                    el.isBold = isBold
                    el.isItalic = isItalic
                    el.isUnderline = isUnderline
                    el.colorName = colorName
                    el.fontName = fontName
                    el.alignmentRaw = alignmentRaw
                    el.bgColorName = bgColorName
                    el.strokeColorName = strokeColorName
                    el.strokeWidth = strokeWidth
                    el.updatedAt = Date()
                    el.rebuildRichTextFromLegacyStyle()
                    context.insert(el); try? context.save()
                    Task { await TextSyncService.shared.upsert(el) }
                }
            ))
        } else {
            let newState = TextElementHistoryState(element: element)
            undoManager?.recordElementChange(
                name: "Edit text",
                element: element,
                from: oldState,
                to: newState,
                context: context
            ) { target, state in
                state.apply(to: target)
            }
        }
    }

    @discardableResult
    func addOCRText(canvasID: UUID, text: String, canvasPoint: CGPoint,
                    zIndex: Int, context: ModelContext,
                    undoManager: CanvasUndoManager? = nil) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let element = TextElementModel(
            canvasID: canvasID,
            text: trimmed,
            x: canvasPoint.x,
            y: canvasPoint.y
        )
        element.fontSize = 16
        element.colorName = "primary"
        element.bgColorName = "none"
        element.strokeColorName = "none"
        element.zIndex = zIndex
        element.updatedAt = Date()
        element.rebuildRichTextFromLegacyStyle()
        context.insert(element)
        try? context.save()
        editingID = element.id
        Task { await TextSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TextElementModel>())
                    .first(where: { $0.id == id }) {
                    context.delete(el)
                    try? context.save()
                    Task { await TextSyncService.shared.delete(el) }
                }
            },
            redo: {
                let el = TextElementModel(canvasID: canvasID, text: trimmed,
                                          x: canvasPoint.x, y: canvasPoint.y)
                el.id = id
                el.fontSize = 16
                el.colorName = "primary"
                el.bgColorName = "none"
                el.strokeColorName = "none"
                el.zIndex = zIndex
                el.updatedAt = Date()
                el.rebuildRichTextFromLegacyStyle()
                context.insert(el)
                try? context.save()
                Task { await TextSyncService.shared.upsert(el) }
            }
        ))

        return id
    }

    @discardableResult
    func addPDFExtract(canvasID: UUID, payload: PDFSelectionPayload,
                       documentID: UUID, canvasPoint: CGPoint,
                       zIndex: Int, context: ModelContext,
                       undoManager: CanvasUndoManager? = nil) -> UUID? {
        let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let element = TextElementModel(
            canvasID: canvasID,
            text: trimmed,
            x: canvasPoint.x,
            y: canvasPoint.y
        )
        element.fontSize = 17
        element.colorName = "black"
        element.bgColorName = "white"
        element.strokeColorName = "gray"
        element.strokeWidth = 1
        element.zIndex = zIndex
        element.sourcePDFDocumentID = documentID
        element.sourcePDFPageIndex = payload.firstPageIndex
        element.sourcePDFRects = payload.firstPageRects
        element.updatedAt = Date()
        element.rebuildRichTextFromLegacyStyle()
        context.insert(element)
        try? context.save()
        editingID = element.id
        Task { await TextSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let local = try? context.fetch(FetchDescriptor<TextElementModel>())
                    .first(where: { $0.id == id }) {
                    Task { await TextSyncService.shared.delete(local) }
                    context.delete(local)
                    try? context.save()
                }
            },
            redo: {
                let restored = TextElementModel(
                    canvasID: canvasID,
                    text: trimmed,
                    x: canvasPoint.x,
                    y: canvasPoint.y
                )
                restored.id = id
                restored.fontSize = 17
                restored.colorName = "black"
                restored.bgColorName = "white"
                restored.strokeColorName = "gray"
                restored.strokeWidth = 1
                restored.zIndex = zIndex
                restored.sourcePDFDocumentID = documentID
                restored.sourcePDFPageIndex = payload.firstPageIndex
                restored.sourcePDFRects = payload.firstPageRects
                restored.updatedAt = Date()
                restored.rebuildRichTextFromLegacyStyle()
                context.insert(restored)
                try? context.save()
                Task { await TextSyncService.shared.upsert(restored) }
            }
        ))
        return id
    }

    // MARK: - Position

    func updatePosition(element: TextElementModel, translation: CGSize,
                        scale: CGFloat = 1, boundary: CGSize = .zero,
                        context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldX = element.x, oldY = element.y
        // translation is already in canvas coordinates (DragGesture inside SwiftUI's
        // scaleEffect ZStack inverse-maps touches automatically). Add directly,
        // matching ImageElementViewModel, StickyNoteViewModel, etc.
        let newX = element.x + Double(translation.width)
        let newY = element.y + Double(translation.height)
        let clamped = CanvasBoundaryHelper.clamp(x: newX, y: newY, boundary: boundary,
                                                  elementSize: CGSize(width: 200, height: 60))
        element.x = clamped.x; element.y = clamped.y
        element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TextElementModel>())
                    .first(where: { $0.id == id }) {
                    el.x = oldX; el.y = oldY; el.updatedAt = Date()
                    try? context.save()
                    Task { await TextSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<TextElementModel>())
                    .first(where: { $0.id == id }) {
                    el.x = clamped.x; el.y = clamped.y; el.updatedAt = Date()
                    try? context.save()
                    Task { await TextSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    // MARK: - Inline formatting

    func toggleBold(element: TextElementModel, context: ModelContext,
                    undoManager: CanvasUndoManager? = nil) {
        let target = !element.isBold
        applyRichTextStyle(element: element, context: context, undoManager: undoManager) { attrs in
            attrs.isBold = target
        }
    }

    func toggleItalic(element: TextElementModel, context: ModelContext,
                      undoManager: CanvasUndoManager? = nil) {
        let target = !element.isItalic
        applyRichTextStyle(element: element, context: context, undoManager: undoManager) { attrs in
            attrs.isItalic = target
        }
    }

    func toggleUnderline(element: TextElementModel, context: ModelContext,
                         undoManager: CanvasUndoManager? = nil) {
        let target = !element.isUnderline
        applyRichTextStyle(element: element, context: context, undoManager: undoManager) { attrs in
            attrs.isUnderline = target
        }
    }

    func setAlignment(_ alignment: TextAlignment, element: TextElementModel,
                      context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldDocument = element.resolvedRichTextDocument
        var document = element.resolvedRichTextDocument
        document.paragraph.textAlignment = alignment
        element.setRichTextDocument(document)
        element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
        undoManager?.recordElementChange(
            name: "Change text alignment",
            element: element,
            from: oldDocument,
            to: element.resolvedRichTextDocument,
            context: context
        ) { $0.setRichTextDocument($1) }
    }

    func adjustFontSize(by delta: Double, element: TextElementModel, context: ModelContext,
                        undoManager: CanvasUndoManager? = nil) {
        applyRichTextStyle(element: element, context: context, undoManager: undoManager) { attrs in
            attrs.fontSize = TextStyle.clampedFontSize(attrs.fontSize + delta)
        }
    }

    func setColor(_ colorName: String, element: TextElementModel, context: ModelContext,
                  undoManager: CanvasUndoManager? = nil) {
        applyRichTextStyle(element: element, context: context, undoManager: undoManager) { attrs in
            attrs.colorName = colorName
        }
    }

    private func applyRichTextStyle(
        element: TextElementModel,
        context: ModelContext,
        undoManager: CanvasUndoManager?,
        transform: (inout RichTextAttributes) -> Void
    ) {
        let oldDocument = element.resolvedRichTextDocument
        var document = oldDocument
        if document.runs.isEmpty, !element.text.isEmpty {
            document = RichTextDocument.legacy(
                text: element.text,
                fontSize: element.fontSize,
                isBold: element.isBold,
                isItalic: element.isItalic,
                isUnderline: element.isUnderline,
                colorName: element.colorName,
                fontName: element.fontName,
                alignmentRaw: element.alignmentRaw
            )
        }
        element.setRichTextDocument(document.applyingToAllRuns(transform))
        element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
        undoManager?.recordElementChange(
            name: "Format text",
            element: element,
            from: oldDocument,
            to: element.resolvedRichTextDocument,
            context: context,
            coalescingKey: "text-format-\(element.id)"
        ) { $0.setRichTextDocument($1) }
    }

    // MARK: - Card background & stroke

    func setBgColor(_ colorName: String, element: TextElementModel, context: ModelContext,
                    undoManager: CanvasUndoManager? = nil) {
        let oldValue = element.bgColorName
        element.bgColorName = colorName; element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
        undoManager?.recordElementChange(
            name: "Change text background", element: element,
            from: oldValue, to: element.bgColorName, context: context
        ) { $0.bgColorName = $1 }
    }

    func setStrokeColor(_ colorName: String, element: TextElementModel, context: ModelContext,
                        undoManager: CanvasUndoManager? = nil) {
        let oldValue = element.strokeColorName
        element.strokeColorName = colorName; element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
        undoManager?.recordElementChange(
            name: "Change text border", element: element,
            from: oldValue, to: element.strokeColorName, context: context
        ) { $0.strokeColorName = $1 }
    }

    func setStrokeWidth(_ width: Double, element: TextElementModel, context: ModelContext,
                        undoManager: CanvasUndoManager? = nil) {
        let oldValue = element.strokeWidth
        element.strokeWidth = width; element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
        undoManager?.recordElementChange(
            name: "Change text border width", element: element,
            from: oldValue, to: element.strokeWidth, context: context,
            coalescingKey: "text-stroke-width-\(element.id)"
        ) { $0.strokeWidth = $1 }
    }

    // MARK: - Duplicate

    @discardableResult
    func duplicate(element: TextElementModel, zIndex: Int,
                   offset: CGSize = CGSize(width: 30, height: 30),
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) -> UUID? {
        let copy = TextElementModel(canvasID: element.canvasID,
                                    text: element.text,
                                    x: element.x + Double(offset.width),
                                    y: element.y + Double(offset.height))
        copy.fontSize       = element.fontSize
        copy.isBold         = element.isBold
        copy.isItalic       = element.isItalic
        copy.isUnderline    = element.isUnderline
        copy.colorName      = element.colorName
        copy.fontName       = element.fontName
        copy.alignmentRaw   = element.alignmentRaw
        copy.bgColorName    = element.bgColorName
        copy.strokeColorName = element.strokeColorName
        copy.strokeWidth    = element.strokeWidth
        copy.richTextDocument = element.resolvedRichTextDocument
        copy.zIndex         = zIndex
        copy.updatedAt      = Date()
        context.insert(copy); try? context.save()
        Task { await TextSyncService.shared.upsert(copy) }

        let id = copy.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<TextElementModel>())
                    .first(where: { $0.id == id }) {
                    context.delete(el); try? context.save()
                    Task { await TextSyncService.shared.delete(el) }
                }
            },
            redo: {
                let el = TextElementModel(canvasID: element.canvasID,
                                          text: element.text,
                                          x: element.x + Double(offset.width),
                                          y: element.y + Double(offset.height))
                el.id = id; el.zIndex = zIndex; el.updatedAt = Date()
                el.fontSize = element.fontSize
                el.isBold = element.isBold
                el.isItalic = element.isItalic
                el.isUnderline = element.isUnderline
                el.colorName = element.colorName
                el.fontName = element.fontName
                el.alignmentRaw = element.alignmentRaw
                el.bgColorName = element.bgColorName
                el.strokeColorName = element.strokeColorName
                el.strokeWidth = element.strokeWidth
                el.richTextDocument = element.resolvedRichTextDocument
                context.insert(el); try? context.save()
                Task { await TextSyncService.shared.upsert(el) }
            }
        ))
        return id
    }

    // MARK: - Delete

    func delete(element: TextElementModel, context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snap = (
            id: element.id, canvasID: element.canvasID, text: element.text,
            x: element.x, y: element.y, fontSize: element.fontSize,
            isBold: element.isBold, isItalic: element.isItalic,
            isUnderline: element.isUnderline, colorName: element.colorName,
            fontName: element.fontName, alignmentRaw: element.alignmentRaw,
            bgColorName: element.bgColorName, strokeColorName: element.strokeColorName,
            strokeWidth: element.strokeWidth, zIndex: element.zIndex,
            richText: element.resolvedRichTextDocument,
            groupID: element.groupID, isLayerHidden: element.isLayerHidden,
            layerOpacity: element.layerOpacity,
            sourcePDFDocumentID: element.sourcePDFDocumentID,
            sourcePDFPageIndex: element.sourcePDFPageIndex,
            sourcePDFRectsData: element.sourcePDFRectsData
        )
        Task { await TextSyncService.shared.delete(element) }
        context.delete(element); try? context.save()
        if editingID       == snap.id { editingID       = nil }
        if inlineEditingID == snap.id { inlineEditingID = nil }

        undoManager?.push(CanvasAction(
            name: "Delete text",
            undo: {
                let el = TextElementModel(canvasID: snap.canvasID, text: snap.text,
                                          x: snap.x, y: snap.y)
                el.id = snap.id; el.fontSize = snap.fontSize; el.isBold = snap.isBold
                el.isItalic = snap.isItalic; el.isUnderline = snap.isUnderline
                el.colorName = snap.colorName; el.fontName = snap.fontName
                el.alignmentRaw = snap.alignmentRaw; el.zIndex = snap.zIndex
                el.bgColorName = snap.bgColorName
                el.strokeColorName = snap.strokeColorName
                el.strokeWidth = snap.strokeWidth
                el.richTextDocument = snap.richText
                el.groupID = snap.groupID
                el.isLayerHidden = snap.isLayerHidden
                el.layerOpacity = snap.layerOpacity
                el.sourcePDFDocumentID = snap.sourcePDFDocumentID
                el.sourcePDFPageIndex = snap.sourcePDFPageIndex
                el.sourcePDFRectsData = snap.sourcePDFRectsData
                el.updatedAt = Date()
                context.insert(el); try? context.save()
                Task { await TextSyncService.shared.upsert(el) }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<TextElementModel>())
                    .first(where: { $0.id == snap.id }) {
                    context.delete(el); try? context.save()
                    Task { await TextSyncService.shared.delete(el) }
                }
            }
        ))
    }

    func stopEditing() {
        editingID          = nil
        inlineEditingID    = nil
        inlineElementIsNew = false
    }

    func colorFromName(_ name: String) -> Color {
        TextStyle.color(named: name)
    }

    // Returns Color? — nil means transparent/none
    func cardColorFromName(_ name: String) -> Color? {
        guard name != "none" else { return nil }
        return cardColorOptions.first { $0.name == name }?.color
    }

    // All pickable card colors (bg + stroke share the same palette)
    let cardColorOptions: [(name: String, color: Color)] = [
        ("red",     .red),
        ("orange",  .orange),
        ("yellow",  Color(red: 1, green: 0.85, blue: 0)),
        ("green",   .green),
        ("blue",    .blue),
        ("purple",  .purple),
        ("pink",    .pink),
        ("teal",    .teal),
        ("white",   .white),
        ("black",   Color(white: 0.1)),
        ("gray",    Color(white: 0.5)),
    ]
}
