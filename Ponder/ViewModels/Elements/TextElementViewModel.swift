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
        context.insert(element)
        try? context.save()
        inlineEditingID    = element.id
        editingID          = element.id
        inlineElementIsNew = true
        return element
    }

    func commitInlineText(element: TextElementModel, text: String,
                          context: ModelContext,
                          undoManager: CanvasUndoManager? = nil) {
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

        element.text      = trimmed
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
                    context.insert(el); try? context.save()
                    Task { await TextSyncService.shared.upsert(el) }
                }
            ))
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

    func toggleBold(element: TextElementModel, context: ModelContext) {
        element.isBold = !element.isBold; element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
    }

    func toggleItalic(element: TextElementModel, context: ModelContext) {
        element.isItalic = !element.isItalic; element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
    }

    func toggleUnderline(element: TextElementModel, context: ModelContext) {
        element.isUnderline = !element.isUnderline; element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
    }

    func setAlignment(_ alignment: TextAlignment, element: TextElementModel,
                      context: ModelContext) {
        element.textAlignment = alignment; element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
    }

    func adjustFontSize(by delta: Double, element: TextElementModel, context: ModelContext) {
        element.fontSize = TextStyle.clampedFontSize(element.fontSize + delta)
        element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
    }

    func setColor(_ colorName: String, element: TextElementModel, context: ModelContext) {
        element.colorName = colorName; element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
    }

    // MARK: - Card background & stroke

    func setBgColor(_ colorName: String, element: TextElementModel, context: ModelContext) {
        element.bgColorName = colorName; element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
    }

    func setStrokeColor(_ colorName: String, element: TextElementModel, context: ModelContext) {
        element.strokeColorName = colorName; element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
    }

    func setStrokeWidth(_ width: Double, element: TextElementModel, context: ModelContext) {
        element.strokeWidth = width; element.updatedAt = Date(); try? context.save()
        Task { await TextSyncService.shared.upsert(element) }
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
            strokeWidth: element.strokeWidth, zIndex: element.zIndex
        )
        Task { await TextSyncService.shared.delete(element) }
        context.delete(element); try? context.save()
        if editingID       == snap.id { editingID       = nil }
        if inlineEditingID == snap.id { inlineEditingID = nil }

        undoManager?.push(CanvasAction(
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
