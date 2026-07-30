//
//  CanvasExporter.swift
//  Ponder
//

import SwiftUI
import SwiftData
import PencilKit
import Foundation

// MARK: - CanvasExporter

enum CanvasExportScope {
    case allContent
    case currentViewport(CGRect)
}

@MainActor
final class CanvasExporter {

    static func exportPNG(
        canvas:        CanvasModel,
        textElements:  [TextElementModel],
        stickyNotes:   [StickyNoteModel],
        todoLists:     [TodoListModel],
        todoTasks:     [TodoTaskModel],
        shapes:        [ShapeElementModel],
        images:        [ImageElementModel],
        pdfs:          [PDFElementModel],
        tables:        [TableElementModel],
        tableCells:    [TableCellModel],
        audioElements: [AudioElementModel],
        youtubeElements: [YouTubeElementModel],
        drawings:      [DrawingElementModel],
        symbols:       [SymbolElementModel],
        youtubeThumbnails: [UUID: PlatformImage] = [:],
        connectors:    [ConnectorModel],
        colorScheme:   ColorScheme = .light,
        gridStyle:     GridStyle = .dotted,
        gridSpacing:   CGFloat = CGFloat(AppSettings.defaultCanvasPatternSpacing),
        backgroundMode: CanvasBackgroundMode = .adaptive,
        backgroundPalette: CanvasBackgroundPalette = .neutral,
        customBackgroundColors: CanvasCustomBackgroundColors = .defaults,
        exportScope:   CanvasExportScope = .allContent,
        showsWatermark: Bool = false,
        scale:         CGFloat = 2.0
    ) -> Data? {

        let exportRect = resolvedExportRect(
            scope:         exportScope,
            canvas:        canvas,
            textElements:  textElements,
            stickyNotes:   stickyNotes,
            todoLists:     todoLists,
            shapes:        shapes,
            images:        images,
            pdfs:          pdfs,
            tables:        tables,
            audioElements: audioElements,
            youtubeElements: youtubeElements,
            drawings:      drawings,
            symbols:       symbols
        )

        guard exportRect.width > 0, exportRect.height > 0 else { return nil }

        guard let image = renderExportImage(
            exportRect:    exportRect,
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
            youtubeThumbnails: youtubeThumbnails,
            connectors:    connectors,
            colorScheme:   colorScheme,
            gridStyle:     gridStyle,
            gridSpacing:   gridSpacing,
            backgroundMode: backgroundMode,
            backgroundPalette: backgroundPalette,
            customBackgroundColors: customBackgroundColors,
            showsWatermark: showsWatermark,
            scale:         scale
        ) else { return nil }

        #if os(iOS)
        return image.pngData()
        #else
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
        #endif
    }

    static func exportPDF(
        canvas:        CanvasModel,
        textElements:  [TextElementModel],
        stickyNotes:   [StickyNoteModel],
        todoLists:     [TodoListModel],
        todoTasks:     [TodoTaskModel],
        shapes:        [ShapeElementModel],
        images:        [ImageElementModel],
        pdfs:          [PDFElementModel],
        tables:        [TableElementModel],
        tableCells:    [TableCellModel],
        audioElements: [AudioElementModel],
        youtubeElements: [YouTubeElementModel],
        drawings:      [DrawingElementModel],
        symbols:       [SymbolElementModel],
        youtubeThumbnails: [UUID: PlatformImage] = [:],
        connectors:    [ConnectorModel],
        colorScheme:   ColorScheme = .light,
        gridStyle:     GridStyle = .dotted,
        gridSpacing:   CGFloat = CGFloat(AppSettings.defaultCanvasPatternSpacing),
        backgroundMode: CanvasBackgroundMode = .adaptive,
        backgroundPalette: CanvasBackgroundPalette = .neutral,
        customBackgroundColors: CanvasCustomBackgroundColors = .defaults,
        exportScope:   CanvasExportScope = .allContent,
        showsWatermark: Bool = false,
        scale:         CGFloat = 2.0
    ) -> Data? {

        let exportRect = resolvedExportRect(
            scope:         exportScope,
            canvas:        canvas,
            textElements:  textElements,
            stickyNotes:   stickyNotes,
            todoLists:     todoLists,
            shapes:        shapes,
            images:        images,
            pdfs:          pdfs,
            tables:        tables,
            audioElements: audioElements,
            youtubeElements: youtubeElements,
            drawings:      drawings,
            symbols:       symbols
        )

        guard exportRect.width > 0, exportRect.height > 0 else { return nil }

        guard let image = renderExportImage(
            exportRect:    exportRect,
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
            youtubeThumbnails: youtubeThumbnails,
            connectors:    connectors,
            colorScheme:   colorScheme,
            gridStyle:     gridStyle,
            gridSpacing:   gridSpacing,
            backgroundMode: backgroundMode,
            backgroundPalette: backgroundPalette,
            customBackgroundColors: customBackgroundColors,
            showsWatermark: showsWatermark,
            scale:         scale
        ) else { return nil }

        return makeSinglePagePDF(image: image, pageSize: exportRect.size)
    }

    private static func renderExportImage(
        exportRect:    CGRect,
        textElements:  [TextElementModel],
        stickyNotes:   [StickyNoteModel],
        todoLists:     [TodoListModel],
        todoTasks:     [TodoTaskModel],
        shapes:        [ShapeElementModel],
        images:        [ImageElementModel],
        pdfs:          [PDFElementModel],
        tables:        [TableElementModel],
        tableCells:    [TableCellModel],
        audioElements: [AudioElementModel],
        youtubeElements: [YouTubeElementModel],
        drawings:      [DrawingElementModel],
        symbols:       [SymbolElementModel],
        youtubeThumbnails: [UUID: PlatformImage],
        connectors:    [ConnectorModel],
        colorScheme:   ColorScheme,
        gridStyle:     GridStyle,
        gridSpacing:   CGFloat,
        backgroundMode: CanvasBackgroundMode,
        backgroundPalette: CanvasBackgroundPalette,
        customBackgroundColors: CanvasCustomBackgroundColors,
        showsWatermark: Bool,
        scale:         CGFloat
    ) -> PlatformImage? {

        let drawingImages = prerenderDrawings(
            drawings:          drawings,
            colorScheme:       colorScheme,
            backgroundMode:    backgroundMode,
            backgroundPalette: backgroundPalette,
            scale:             scale
        )

        let view = CanvasExportView(
            exportRect:    exportRect,
            colorScheme:   colorScheme,
            gridStyle:     gridStyle,
            gridSpacing:   gridSpacing,
            backgroundMode: backgroundMode,
            backgroundPalette: backgroundPalette,
            customBackgroundColors: customBackgroundColors,
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
            drawingImages: drawingImages,
            youtubeThumbnails: youtubeThumbnails,
            symbols:       symbols,
            connectors:    connectors,
            showsWatermark: showsWatermark,
            exportRect_:   exportRect
        )

        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(
            width:  exportRect.width,
            height: exportRect.height
        )

        #if os(iOS)
        return renderer.uiImage
        #else
        return renderer.nsImage
        #endif
    }

    private static func makeSinglePagePDF(image: PlatformImage, pageSize: CGSize) -> Data? {
        guard pageSize.width > 0, pageSize.height > 0 else { return nil }

        #if os(iOS)
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            context.beginPage()
            image.draw(in: bounds)
        }
        #else
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        context.beginPDFPage(nil)
        context.draw(cgImage, in: CGRect(origin: .zero, size: pageSize))
        context.endPDFPage()
        context.closePDF()

        return data as Data
        #endif
    }

    // MARK: - Pre-render drawings
    // Must happen BEFORE ImageRenderer runs.
    // PKDrawing.image() renders using the CURRENT system appearance —
    // white strokes (dark mode) become invisible on a light background.
    // We composite each drawing over its correct background color explicitly.

    private static func prerenderDrawings(
        drawings:          [DrawingElementModel],
        colorScheme:       ColorScheme,
        backgroundMode:    CanvasBackgroundMode,
        backgroundPalette: CanvasBackgroundPalette,
        scale:             CGFloat
    ) -> [UUID: PlatformImage] {
        var result: [UUID: PlatformImage] = [:]

        for el in drawings {
            guard !el.pkDrawing.strokes.isEmpty else { continue }
            let size = CGSize(width: el.width, height: el.height)
            let rect = CGRect(origin: .zero, size: size)

            #if os(iOS)
            let rawImage = el.pkDrawing.image(from: rect, scale: scale)
            let format   = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = false
            let composed = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                if !el.isCanvasDrawing {
                    let bgColor = colorScheme == .dark
                        ? UIColor(white: 0.12, alpha: 1)
                        : UIColor.white
                    bgColor.setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))
                }
                rawImage.draw(in: CGRect(origin: .zero, size: size))
            }
            result[el.id] = composed

            #else
            // macOS — must render PKDrawing under the correct NSAppearance
            // so stroke colors are correct (dark mode = white strokes, etc.)
            let scale2 = NSScreen.main?.backingScaleFactor ?? 2.0
            let targetAppearance = NSAppearance(
                named: colorScheme == .dark ? .darkAqua : .aqua)!

            var rawImage = NSImage()
            targetAppearance.performAsCurrentDrawingAppearance {
                rawImage = el.pkDrawing.image(from: rect, scale: scale2)
            }

            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width * scale2),
                pixelsHigh: Int(size.height * scale2),
                bitsPerSample:   8,
                samplesPerPixel: 4,
                hasAlpha:        true,
                isPlanar:        false,
                colorSpaceName:  .deviceRGB,
                bytesPerRow:     0,
                bitsPerPixel:    0
            )!
            rep.size = size

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            if !el.isCanvasDrawing {
                let bgNSColor = colorScheme == .dark
                    ? NSColor(calibratedWhite: 0.12, alpha: 1)
                    : NSColor.white
                bgNSColor.setFill()
                NSRect(origin: .zero, size: size).fill()
            }
            rawImage.draw(in: NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()

            let composed = NSImage(size: size)
            composed.addRepresentation(rep)
            result[el.id] = composed
            #endif
        }

        return result
    }

    static func loadYouTubeThumbnails(for elements: [YouTubeElementModel]) async -> [UUID: PlatformImage] {
        var result: [UUID: PlatformImage] = [:]

        for element in elements {
            guard let url = URL(string: element.thumbnailURL) else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    continue
                }
                #if canImport(UIKit)
                if let image = UIImage(data: data) {
                    result[element.id] = image
                }
                #else
                if let image = NSImage(data: data) {
                    result[element.id] = image
                }
                #endif
            } catch {
                continue
            }
        }

        return result
    }

    // MARK: - Bounding box

    private static func resolvedExportRect(
        scope:         CanvasExportScope,
        canvas:        CanvasModel,
        textElements:  [TextElementModel],
        stickyNotes:   [StickyNoteModel],
        todoLists:     [TodoListModel],
        shapes:        [ShapeElementModel],
        images:        [ImageElementModel],
        pdfs:          [PDFElementModel],
        tables:        [TableElementModel],
        audioElements: [AudioElementModel],
        youtubeElements: [YouTubeElementModel],
        drawings:      [DrawingElementModel],
        symbols:       [SymbolElementModel]
    ) -> CGRect {
        let allContentRect = computeExportRect(
            canvas:        canvas,
            textElements:  textElements,
            stickyNotes:   stickyNotes,
            todoLists:     todoLists,
            shapes:        shapes,
            images:        images,
            pdfs:          pdfs,
            tables:        tables,
            audioElements: audioElements,
            youtubeElements: youtubeElements,
            drawings:      drawings,
            symbols:       symbols
        )

        switch scope {
        case .allContent:
            return allContentRect
        case .currentViewport(let rect):
            let normalized = rect.standardized
            guard normalized.width > 0, normalized.height > 0 else {
                return allContentRect
            }

            if canvas.isInfinite {
                return normalized
            }

            let boundaryRect = CGRect(origin: .zero, size: canvas.boundarySize)
            let clipped = normalized.intersection(boundaryRect)
            return clipped.isNull || clipped.isEmpty ? boundaryRect : clipped
        }
    }

    static func computeExportRect(
        canvas:        CanvasModel,
        textElements:  [TextElementModel],
        stickyNotes:   [StickyNoteModel],
        todoLists:     [TodoListModel],
        shapes:        [ShapeElementModel],
        images:        [ImageElementModel],
        pdfs:          [PDFElementModel],
        tables:        [TableElementModel],
        audioElements: [AudioElementModel],
        youtubeElements: [YouTubeElementModel],
        drawings:      [DrawingElementModel],
        symbols:       [SymbolElementModel]
    ) -> CGRect {

        if !canvas.isInfinite {
            return CGRect(origin: .zero, size: canvas.boundarySize)
        }

        var minX = CGFloat.infinity,  minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity

        func expand(cx: Double, cy: Double, w: Double, h: Double) {
            minX = min(minX, CGFloat(cx - w / 2))
            minY = min(minY, CGFloat(cy - h / 2))
            maxX = max(maxX, CGFloat(cx + w / 2))
            maxY = max(maxY, CGFloat(cy + h / 2))
        }

        for el in textElements  {
            let size = estimatedTextSize(for: el)
            expand(cx: el.x, cy: el.y, w: Double(size.width), h: Double(size.height))
        }
        for el in stickyNotes   { expand(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in todoLists     { expand(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in shapes        { expand(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in images        { expand(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in pdfs          { expand(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in audioElements { expand(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in youtubeElements { expand(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in drawings      { expand(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in symbols       {
            let size = el.fontSize + 24
            expand(cx: el.x, cy: el.y, w: size, h: size)
        }
        for el in tables {
            let rh = el.showRowHeaders ? 36.0 : 0.0
            let ch = el.showColHeaders ? max(28.0, el.cellHeight * 0.6) : 0.0
            expand(cx: el.x, cy: el.y,
                   w: rh + el.cellWidth  * Double(el.colCount),
                   h: ch + el.cellHeight * Double(el.rowCount))
        }

        guard minX < maxX, minY < maxY else {
            return CGRect(origin: .zero, size: CGSize(width: 800, height: 600))
        }

        let pad: CGFloat = 80
        return CGRect(x: minX - pad, y: minY - pad,
                      width:  maxX - minX + pad * 2,
                      height: maxY - minY + pad * 2)
    }

    fileprivate static func estimatedTextSize(for element: TextElementModel) -> CGSize {
        let fontSize = CGFloat(TextStyle.clampedFontSize(element.fontSize))
        let lines = element.text.split(separator: "\n", omittingEmptySubsequences: false)
        let longestLineLength = max(lines.map(\.count).max() ?? 0, 1)
        let lineCount = max(lines.count, 1)
        let padding: CGFloat = element.hasCard ? 32 : 20
        let width = min(
            20_000,
            max(80, CGFloat(longestLineLength) * fontSize * 0.62 + padding)
        )
        let height = max(36, CGFloat(lineCount) * fontSize * 1.25 + padding)
        return CGSize(width: width, height: height)
    }
}

// MARK: - CanvasExportView

struct CanvasExportView: View {
    let exportRect:    CGRect
    let colorScheme:   ColorScheme
    let gridStyle:     GridStyle
    let gridSpacing:   CGFloat
    let backgroundMode: CanvasBackgroundMode
    let backgroundPalette: CanvasBackgroundPalette
    let customBackgroundColors: CanvasCustomBackgroundColors
    let textElements:  [TextElementModel]
    let stickyNotes:   [StickyNoteModel]
    let todoLists:     [TodoListModel]
    let todoTasks:     [TodoTaskModel]
    let shapes:        [ShapeElementModel]
    let images:        [ImageElementModel]
    let pdfs:          [PDFElementModel]
    let tables:        [TableElementModel]
    let tableCells:    [TableCellModel]
    let audioElements: [AudioElementModel]
    let youtubeElements: [YouTubeElementModel]
    let drawings:      [DrawingElementModel]
    let drawingImages: [UUID: PlatformImage]
    let youtubeThumbnails: [UUID: PlatformImage]
    let symbols:       [SymbolElementModel]
    let connectors:    [ConnectorModel]
    let showsWatermark: Bool
    let exportRect_:   CGRect

    init(
        exportRect:    CGRect,
        colorScheme:   ColorScheme,
        gridStyle:     GridStyle,
        gridSpacing:   CGFloat,
        backgroundMode: CanvasBackgroundMode,
        backgroundPalette: CanvasBackgroundPalette,
        customBackgroundColors: CanvasCustomBackgroundColors,
        textElements:  [TextElementModel],
        stickyNotes:   [StickyNoteModel],
        todoLists:     [TodoListModel],
        todoTasks:     [TodoTaskModel],
        shapes:        [ShapeElementModel],
        images:        [ImageElementModel],
        pdfs:          [PDFElementModel],
        tables:        [TableElementModel],
        tableCells:    [TableCellModel],
        audioElements: [AudioElementModel],
        youtubeElements: [YouTubeElementModel],
        drawings:      [DrawingElementModel],
        drawingImages: [UUID: PlatformImage],
        youtubeThumbnails: [UUID: PlatformImage],
        symbols:       [SymbolElementModel],
        connectors:    [ConnectorModel],
        showsWatermark: Bool,
        exportRect_:   CGRect
    ) {
        self.exportRect    = exportRect
        self.colorScheme   = colorScheme
        self.gridStyle     = gridStyle
        self.gridSpacing   = gridSpacing
        self.backgroundMode = backgroundMode
        self.backgroundPalette = backgroundPalette
        self.customBackgroundColors = customBackgroundColors
        self.textElements  = textElements
        self.stickyNotes   = stickyNotes
        self.todoLists     = todoLists
        self.todoTasks     = todoTasks
        self.shapes        = shapes
        self.images        = images
        self.pdfs          = pdfs
        self.tables        = tables
        self.tableCells    = tableCells
        self.audioElements = audioElements
        self.youtubeElements = youtubeElements
        self.drawings      = drawings
        self.drawingImages = drawingImages
        self.youtubeThumbnails = youtubeThumbnails
        self.symbols       = symbols
        self.connectors    = connectors
        self.showsWatermark = showsWatermark
        self.exportRect_   = exportRect_
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }

    private var sortedElements: [any LayerableElement] {
        var elements: [any LayerableElement] = []
        elements += textElements as [any LayerableElement]
        elements += stickyNotes as [any LayerableElement]
        elements += todoLists as [any LayerableElement]
        elements += shapes as [any LayerableElement]
        elements += images as [any LayerableElement]
        elements += pdfs as [any LayerableElement]
        elements += drawings as [any LayerableElement]
        elements += tables as [any LayerableElement]
        elements += audioElements as [any LayerableElement]
        elements += youtubeElements as [any LayerableElement]
        elements += symbols as [any LayerableElement]
        return elements.sorted { lhs, rhs in
            let lhsIsHighlight = (lhs as? DrawingElementModel)?.isCanvasHighlighterDrawing == true
            let rhsIsHighlight = (rhs as? DrawingElementModel)?.isCanvasHighlighterDrawing == true
            if lhsIsHighlight != rhsIsHighlight { return lhsIsHighlight }
            return lhs.zIndex < rhs.zIndex
        }
    }

    private var boundsMap: [UUID: CGRect] {
        var map: [UUID: CGRect] = [:]
        let ox = exportRect.minX
        let oy = exportRect.minY

        func makeRect(cx: Double, cy: Double, w: Double, h: Double) -> CGRect {
            CGRect(x: CGFloat(cx) - CGFloat(w / 2) - ox,
                   y: CGFloat(cy) - CGFloat(h / 2) - oy,
                   width: CGFloat(w), height: CGFloat(h))
        }

        for el in textElements  {
            let size = CanvasExporter.estimatedTextSize(for: el)
            map[el.id] = makeRect(cx: el.x, cy: el.y, w: Double(size.width), h: Double(size.height))
        }
        for el in stickyNotes   { map[el.id] = makeRect(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in todoLists     { map[el.id] = makeRect(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in shapes        { map[el.id] = makeRect(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in images        { map[el.id] = makeRect(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in pdfs          { map[el.id] = makeRect(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in audioElements { map[el.id] = makeRect(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in youtubeElements { map[el.id] = makeRect(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in drawings      { map[el.id] = makeRect(cx: el.x, cy: el.y, w: el.width, h: el.height) }
        for el in symbols {
            let size = el.fontSize + 24
            map[el.id] = makeRect(cx: el.x, cy: el.y, w: size, h: size)
        }
        for el in tables {
            let rh = el.showRowHeaders ? 36.0 : 0.0
            let ch = el.showColHeaders ? max(28.0, el.cellHeight * 0.6) : 0.0
            let w  = rh + el.cellWidth  * Double(el.colCount)
            let h  = ch + el.cellHeight * Double(el.rowCount)
            map[el.id] = makeRect(cx: el.x, cy: el.y, w: w, h: h)
        }
        return map
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CanvasGridView(
                offset: CGSize(width: -exportRect.minX, height: -exportRect.minY),
                scale: 1,
                style: gridStyle,
                spacing: gridSpacing,
                backgroundMode: backgroundMode,
                backgroundPalette: backgroundPalette,
                customBackgroundColors: customBackgroundColors
            )

            // Connectors — SwiftUI Shape views, not Canvas{},
            // because Canvas{} closures may not execute in ImageRenderer on macOS
            ConnectorExportOverlay(
                connectors:  connectors,
                boundsMap:   boundsMap,
                colorScheme: colorScheme,
                width:       exportRect.width,
                height:      exportRect.height
            )

            ForEach(sortedElements, id: \.id) { element in
                exportElement(element)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsWatermark {
                exportWatermark
                    .padding(watermarkPadding)
            }
        }
        .frame(width: exportRect.width, height: exportRect.height)
        .colorScheme(colorScheme)
    }

    private var exportWatermark: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: watermarkFontSize, weight: .semibold))
            Text("Made with Canvio")
                .font(.system(size: watermarkFontSize, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, watermarkHorizontalPadding)
        .padding(.vertical, watermarkVerticalPadding)
        .background(Color.black.opacity(0.62), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 2)
        .frame(maxWidth: max(70, exportRect.width - watermarkPadding * 2), alignment: .trailing)
    }

    private var watermarkFontSize: CGFloat {
        min(12, max(8, exportRect.width * 0.018))
    }

    private var watermarkHorizontalPadding: CGFloat {
        min(12, max(7, exportRect.width * 0.014))
    }

    private var watermarkVerticalPadding: CGFloat {
        min(7, max(4, exportRect.height * 0.008))
    }

    private var watermarkPadding: CGFloat {
        min(22, max(8, min(exportRect.width, exportRect.height) * 0.035))
    }

    // MARK: - Coordinate helper

    private func pos(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x) - exportRect.minX, y: CGFloat(y) - exportRect.minY)
    }

    // MARK: - Font helpers

    private func makeFont(_ el: TextElementModel) -> Font {
        makeFont(fontName: el.fontName, fontSize: el.fontSize,
                 isBold: el.isBold, isItalic: el.isItalic)
    }

    private func makeFont(fontName: String, fontSize: CGFloat,
                          isBold: Bool, isItalic: Bool) -> Font {
        var f: Font = fontName == "system"
            ? .system(size: fontSize)
            : .custom(fontName, size: fontSize)
        if isBold   { f = f.bold() }
        if isItalic { f = f.italic() }
        return f
    }

    // MARK: - Color helpers

    private func textColor(_ name: String) -> Color {
        if name == "primary" {
            return colorScheme == .dark ? .white : .black
        }
        return TextStyle.color(
            named: name,
            fallback: colorScheme == .dark ? .white : .black
        )
    }

    private func textCardColor(_ name: String) -> Color? {
        switch name {
        case "none":   return nil
        case "red":    return .red
        case "orange": return .orange
        case "yellow": return Color(red: 1, green: 0.85, blue: 0)
        case "green":  return .green
        case "blue":   return .blue
        case "purple": return .purple
        case "pink":   return .pink
        case "teal":   return .teal
        case "white":  return .white
        case "black":  return Color(white: 0.1)
        case "gray":   return Color(white: 0.5)
        default:       return nil
        }
    }

    private func symbolColor(_ name: String) -> Color {
        switch name {
        case "primary": return colorScheme == .dark ? .white : .black
        case "blue":    return .blue
        case "red":     return .red
        case "green":   return .green
        case "orange":  return .orange
        case "purple":  return .purple
        case "pink":    return .pink
        case "teal":    return .teal
        case "yellow":  return .yellow
        case "indigo":  return .indigo
        case "mint":    return .mint
        case "cyan":    return .cyan
        case "brown":   return .brown
        case "gray":    return .gray
        case "black":   return Color(white: 0.1)
        case "white":   return .white
        default:        return colorScheme == .dark ? .white : .black
        }
    }

    private func shapeColor(_ name: String) -> Color {
        ShapeColorPalette.color(
            named: name,
            fallback: colorScheme == .dark ? .white : .black
        )
    }

    private func todoAccentColor(_ name: String) -> Color {
        switch name {
        case "blue":   return .blue;   case "purple": return .purple
        case "green":  return .green;  case "orange": return .orange
        case "pink":   return .pink;   case "red":    return .red
        case "teal":   return .teal;   default:       return .blue
        }
    }

    private func underlinedString(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        attr.underlineStyle = .single
        return attr
    }

    // MARK: - Text

    @ViewBuilder
    private func exportText(_ el: TextElementModel) -> some View {
        let p   = pos(el.x, el.y)
        let hasBg = el.bgColorName != "none"
        let hasStroke = el.strokeColorName != "none"
        let hasCard = hasBg || hasStroke
        let document = el.resolvedRichTextDocument
        let textView = Text(document.attributedString())
            .multilineTextAlignment(document.paragraph.textAlignment)
        textView
        .lineLimit(nil)
        .padding(hasCard ? 16 : 10)
        .fixedSize()
        .background {
            if hasCard {
                RoundedRectangle(cornerRadius: 8)
                    .fill(hasBg ? (textCardColor(el.bgColorName) ?? Color.clear) : Color.clear)
                    .overlay {
                        if hasStroke {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    textCardColor(el.strokeColorName) ?? Color.clear,
                                    lineWidth: el.strokeWidth
                                )
                        }
                    }
                    .shadow(color: .black.opacity(hasBg ? 0.12 : 0), radius: 6, x: 0, y: 3)
            }
        }
        .position(x: p.x, y: p.y)
    }

    // MARK: - Sticky Note

    @ViewBuilder
    private func exportStickyNote(_ el: StickyNoteModel) -> some View {
        let p       = pos(el.x, el.y)
        let palette = StickyNoteColor.color(named: el.colorName)
        let fnt     = makeFont(fontName: el.fontName, fontSize: el.fontSize,
                               isBold: el.isBold, isItalic: el.isItalic)
        let fold: CGFloat = 26

        ZStack(alignment: .topLeading) {
            FoldedRectangle(foldSize: fold)
                .fill(palette.background)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 1, y: 2)
            Text(el.text).font(fnt)
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .multilineTextAlignment(.leading)
                .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: fold + 8))
            GeometryReader { geo in
                Path { path in
                    let w = geo.size.width
                    path.move(to: CGPoint(x: w - fold, y: 0))
                    path.addLine(to: CGPoint(x: w, y: fold))
                    path.addLine(to: CGPoint(x: w - fold, y: fold))
                    path.closeSubpath()
                }.fill(palette.foldShadow)
            }.allowsHitTesting(false)
        }
        .frame(width: el.width, height: el.height)
        .rotationEffect(.degrees(el.rotation))
        .position(x: p.x, y: p.y)
    }

    // MARK: - Shape

    @ViewBuilder
    private func exportShape(_ el: ShapeElementModel) -> some View {
        let p  = pos(el.x, el.y)
        let sc = shapeColor(el.strokeColorName)
        let fc = shapeColor(el.fillColorName)
        Group {
            switch el.shapeKind {
            case .line:
                if el.hasVisibleStroke {
                    exportLine(stroke: sc, strokeWidth: el.strokeWidth, hasArrow: el.hasArrowHead)
                } else {
                    Color.clear
                }
            case .rectangle:
                ZStack {
                    if el.hasFill { RoundedRectangle(cornerRadius: 4).fill(fc) }
                    if el.hasVisibleStroke {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(sc, lineWidth: el.strokeWidth)
                    }
                }
            case .triangle:
                ZStack {
                    if el.hasFill { TriangleShape(variant: el.triangleVariant).fill(fc) }
                    if el.hasVisibleStroke {
                        TriangleShape(variant: el.triangleVariant).stroke(sc, lineWidth: el.strokeWidth)
                    }
                }
            case .polygon:
                ZStack {
                    if el.hasFill { PolygonShape(sides: el.polygonSides).fill(fc) }
                    if el.hasVisibleStroke {
                        PolygonShape(sides: el.polygonSides).stroke(sc, lineWidth: el.strokeWidth)
                    }
                }
            case .circle:
                ZStack {
                    if el.hasFill { Circle().fill(fc) }
                    if el.hasVisibleStroke {
                        Circle().strokeBorder(sc, lineWidth: el.strokeWidth)
                    }
                }
            }
        }
        .frame(width: el.width, height: el.height)
        .rotationEffect(.degrees(el.rotation))
        .position(x: p.x, y: p.y)
    }

    @ViewBuilder
    private func exportLine(stroke: Color, strokeWidth: Double, hasArrow: Bool) -> some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(
                        x: geo.size.width - (hasArrow ? CGFloat(strokeWidth * 3) : 0), y: midY))
                }.stroke(stroke, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                if hasArrow {
                    Path { path in
                        let h = CGFloat(strokeWidth * 3), ex = geo.size.width
                        path.move(to: CGPoint(x: ex, y: midY))
                        path.addLine(to: CGPoint(x: ex - h, y: midY - h * 0.7))
                        path.addLine(to: CGPoint(x: ex - h, y: midY + h * 0.7))
                        path.closeSubpath()
                    }.fill(stroke)
                }
            }
        }
    }

    // MARK: - Image

    @ViewBuilder
    private func exportImage(_ el: ImageElementModel) -> some View {
        let p = pos(el.x, el.y)
        Group {
            if let img = ImageStorageService.load(fileName: el.imageFileName) {
                #if canImport(UIKit)
                Image(uiImage: img).resizable().scaledToFill()
                #else
                Image(nsImage: img).resizable().scaledToFill()
                #endif
            } else {
                Color.secondary.opacity(0.12)
            }
        }
        .frame(width: el.width, height: el.height)
        .clipShape(RoundedRectangle(cornerRadius: el.cornerRadius))
        .opacity(el.opacity)
        .rotationEffect(.degrees(el.rotation))
        .position(x: p.x, y: p.y)
    }

    // MARK: - PDF

    @ViewBuilder
    private func exportPDF(_ el: PDFElementModel) -> some View {
        let p = pos(el.x, el.y)
        VStack(spacing: 0) {
            ZStack {
                Color.secondary.opacity(0.07)
                if let thumb = PDFStorageService.loadThumbnail(fileName: el.thumbnailFileName) {
                    #if canImport(UIKit)
                    Image(uiImage: thumb).resizable().scaledToFit().padding(8)
                    #else
                    Image(nsImage: thumb).resizable().scaledToFit().padding(8)
                    #endif
                } else {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.red.opacity(0.6))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.red)
                Text(el.originalName.isEmpty ? "Document" : el.originalName)
                    .font(.caption.weight(.medium)).lineLimit(1)
                Spacer()
                Text("\(el.pageCount)p").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }.padding(.horizontal, 10).padding(.vertical, 8)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        .frame(width: el.width, height: el.height)
        .rotationEffect(.degrees(el.rotation))
        .position(x: p.x, y: p.y)
    }

    // MARK: - Todo List

    @ViewBuilder
    private func exportTodoList(_ el: TodoListModel) -> some View {
        let p      = pos(el.x, el.y)
        let accent = todoAccentColor(el.colorName)
        let tasks  = todoTasks
            .filter { $0.listID == el.id && $0.parentTaskID == nil }
            .sorted { $0.order < $1.order }
        let textCol: Color = colorScheme == .dark ? .white : .primary

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4).fill(accent).frame(width: 4, height: 22)
                Text(el.title.isEmpty ? "Todo" : el.title)
                    .font(.headline.weight(.semibold)).foregroundStyle(textCol)
                Spacer()
                let done = tasks.filter { $0.isCompleted }.count
                Text("\(done)/\(tasks.count)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }.padding(12)
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                ForEach(tasks.prefix(8)) { task in
                    HStack(spacing: 10) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(task.isCompleted ? accent : Color.secondary.opacity(0.4))
                        Text(task.title).font(.system(size: 14))
                            .strikethrough(task.isCompleted, color: .secondary)
                            .foregroundStyle(task.isCompleted ? Color.secondary : textCol)
                            .lineLimit(1)
                        Spacer()
                    }.padding(.horizontal, 12).padding(.vertical, 4)
                    Divider().padding(.leading, 42)
                }
                if tasks.count > 8 {
                    Text("+ \(tasks.count - 8) more").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                }
            }.padding(.vertical, 4)
            Spacer(minLength: 0)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
        .frame(width: el.width, height: el.height)
        .position(x: p.x, y: p.y)
    }

    // MARK: - Table

    @ViewBuilder
    private func exportTable(_ el: TableElementModel) -> some View {
        let p          = pos(el.x, el.y)
        let cells      = tableCells.filter { $0.tableID == el.id }
        let rowHeaderW: CGFloat = el.showRowHeaders ? 36 : 0
        let colHeaderH: CGFloat = el.showColHeaders ? max(28, CGFloat(el.cellHeight) * 0.6) : 0
        let totalW     = rowHeaderW + CGFloat(el.cellWidth) * CGFloat(el.colCount)
        let totalH     = colHeaderH + CGFloat(el.cellHeight) * CGFloat(el.rowCount)
        let fontSize   = max(10, min(18, CGFloat(el.cellHeight) * 0.32))
        let tableBg    = colorScheme == .dark ? Color(white: 0.08) : Color.white
        let headerBg   = Color.secondary.opacity(colorScheme == .dark ? 0.2 : 0.1)

        VStack(spacing: 0) {
            if el.showColHeaders {
                HStack(spacing: 0) {
                    if el.showRowHeaders {
                        Color.secondary.opacity(colorScheme == .dark ? 0.25 : 0.12)
                            .frame(width: rowHeaderW, height: colHeaderH)
                            .border(Color.secondary.opacity(0.25), width: 0.5)
                    }
                    ForEach(0..<el.colCount, id: \.self) { c in
                        Text(colLabel(c))
                            .font(.system(size: fontSize * 0.85, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: CGFloat(el.cellWidth), height: colHeaderH)
                            .background(headerBg)
                            .border(Color.secondary.opacity(0.25), width: 0.5)
                    }
                }
            }
            ForEach(0..<el.rowCount, id: \.self) { r in
                HStack(spacing: 0) {
                    if el.showRowHeaders {
                        Text("\(r + 1)")
                            .font(.system(size: fontSize * 0.85, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: rowHeaderW, height: CGFloat(el.cellHeight))
                            .background(headerBg)
                            .border(Color.secondary.opacity(0.25), width: 0.5)
                    }
                    ForEach(0..<el.colCount, id: \.self) { c in
                        if let cell = cells.first(where: { $0.row == r && $0.col == c }) {
                            if cell.isMerged {
                                Color.clear.frame(width: 0, height: 0)
                            } else {
                                Text(cell.value)
                                    .font(.system(size: fontSize,
                                                  weight: cell.isBold ? .semibold : .regular))
                                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
                                    .frame(
                                        width:  CGFloat(el.cellWidth) * CGFloat(max(1, cell.colSpan)),
                                        height: CGFloat(el.cellHeight),
                                        alignment: cellAlignment(cell.alignmentRaw)
                                    )
                                    .padding(.horizontal, 6)
                                    .border(Color.secondary.opacity(0.2), width: 0.5)
                            }
                        } else {
                            Color.clear
                                .frame(width: CGFloat(el.cellWidth), height: CGFloat(el.cellHeight))
                                .border(Color.secondary.opacity(0.2), width: 0.5)
                        }
                    }
                }
            }
        }
        .background(tableBg)
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        .frame(width: totalW, height: totalH)
        .rotationEffect(.degrees(el.rotation))
        .position(x: p.x, y: p.y)
    }

    private func colLabel(_ col: Int) -> String {
        var result = "", n = col
        repeat {
            result = String(UnicodeScalar(65 + (n % 26))!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }

    private func cellAlignment(_ raw: String) -> Alignment {
        switch raw {
        case "center":   return .center
        case "trailing": return .trailing
        default:         return .leading
        }
    }

    // MARK: - Audio

    @ViewBuilder
    private func exportAudio(_ el: AudioElementModel) -> some View {
        let p = pos(el.x, el.y)
        let barHeights: [(Int, CGFloat)] = [
            (0,12),(1,20),(2,16),(3,28),(4,10),(5,24),(6,18),(7,14),
            (8,26),(9,8),(10,22),(11,15),(12,27),(13,11),(14,19),(15,17),
            (16,25),(17,9),(18,13),(19,21)
        ]
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.pink.opacity(0.15)).frame(width: 34, height: 34)
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(.pink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(el.originalName.isEmpty ? "Audio" : el.originalName)
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
                    Text(formattedDuration(el.duration))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            HStack(spacing: 2) {
                ForEach(barHeights, id: \.0) { _, h in
                    Capsule().fill(Color.pink.opacity(0.5)).frame(width: 3, height: h)
                }
            }.frame(height: 32).padding(.horizontal, 12).padding(.bottom, 8)
            HStack(spacing: 24) {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary)
                ZStack {
                    Circle().fill(Color.pink).frame(width: 34, height: 34)
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white).offset(x: 1)
                }
                Image(systemName: "goforward.10")
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary)
            }.padding(.bottom, 10)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
        .frame(width: el.width, height: el.height)
        .rotationEffect(.degrees(el.rotation))
        .position(x: p.x, y: p.y)
    }

    private func formattedDuration(_ s: Double) -> String {
        let t = Int(s); return String(format: "%d:%02d", t / 60, t % 60)
    }

    // MARK: - YouTube

    @ViewBuilder
    private func exportYouTube(_ el: YouTubeElementModel) -> some View {
        let p = pos(el.x, el.y)
        ZStack {
            if let thumbnail = youtubeThumbnails[el.id] {
                #if canImport(UIKit)
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                #else
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                #endif
            } else {
                youtubeFallbackThumbnail
            }

            LinearGradient(
                colors: [.black.opacity(0.45), .black.opacity(0.05), .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.red)
                    Spacer()
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .padding(10)

                Spacer()

                ZStack {
                    Circle().fill(Color.red).frame(width: 48, height: 48)
                    Image(systemName: "play.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 2)
                }

                Spacer()

                Text(el.title.isEmpty ? "YouTube Video" : el.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: el.width, height: el.height)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 9, x: 0, y: 3)
        .position(x: p.x, y: p.y)
    }

    private var youtubeFallbackThumbnail: some View {
        ZStack {
            Rectangle().fill(Color(red: 0.12, green: 0.12, blue: 0.13))
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Symbol

    @ViewBuilder
    private func exportSymbol(_ el: SymbolElementModel) -> some View {
        let p = pos(el.x, el.y)
        let size = CGFloat(el.fontSize)
        Image(systemName: el.symbolName)
            .font(.system(size: size))
            .foregroundStyle(symbolColor(el.colorName))
            .frame(width: size + 24, height: size + 24)
            .position(x: p.x, y: p.y)
    }

    // MARK: - Layered element dispatch

    @ViewBuilder
    private func exportElement(_ element: any LayerableElement) -> some View {
        if let el = element as? TextElementModel {
            exportText(el)
        } else if let el = element as? StickyNoteModel {
            exportStickyNote(el)
        } else if let el = element as? TodoListModel {
            exportTodoList(el)
        } else if let el = element as? ShapeElementModel {
            exportShape(el)
        } else if let el = element as? ImageElementModel {
            exportImage(el)
        } else if let el = element as? PDFElementModel {
            exportPDF(el)
        } else if let el = element as? DrawingElementModel {
            exportDrawing(el)
        } else if let el = element as? TableElementModel {
            exportTable(el)
        } else if let el = element as? AudioElementModel {
            exportAudio(el)
        } else if let el = element as? YouTubeElementModel {
            exportYouTube(el)
        } else if let el = element as? SymbolElementModel {
            exportSymbol(el)
        }
    }

    // MARK: - Drawing

    @ViewBuilder
    private func exportDrawing(_ el: DrawingElementModel) -> some View {
        let p = pos(el.x, el.y)
        ZStack {
            if !el.isCanvasDrawing {
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardBackground)
                    .shadow(color: .black.opacity(0.07), radius: 5, x: 0, y: 3)
            }
            if let img = drawingImages[el.id] {
                #if canImport(UIKit)
                Image(uiImage: img)
                    .resizable()
                    .frame(width: el.width, height: el.height)
                    .clipShape(RoundedRectangle(cornerRadius: el.isCanvasDrawing ? 0 : 12))
                #else
                Image(nsImage: img)
                    .resizable()
                    .frame(width: el.width, height: el.height)
                    .clipShape(RoundedRectangle(cornerRadius: el.isCanvasDrawing ? 0 : 12))
                #endif
            }
            if !el.isCanvasDrawing {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            }
        }
        .frame(width: el.width, height: el.height)
        .rotationEffect(.degrees(el.rotation))
        .position(x: p.x, y: p.y)
    }
}

// MARK: - Connector export (SwiftUI Shape views — work in ImageRenderer on all platforms)

private struct ConnectorExportOverlay: View {
    let connectors:  [ConnectorModel]
    let boundsMap:   [UUID: CGRect]
    let colorScheme: ColorScheme
    let width:       CGFloat
    let height:      CGFloat

    var body: some View {
        ZStack {
            ForEach(connectors) { connector in
                if let fromRect = boundsMap[connector.fromElementID],
                   let toRect   = boundsMap[connector.toElementID] {
                    ConnectorPathView(
                        connector:   connector,
                        fromRect:    fromRect,
                        toRect:      toRect,
                        colorScheme: colorScheme
                    )
                }
            }
        }
        .frame(width: width, height: height)
    }
}

private struct ConnectorPathView: View {
    let connector:   ConnectorModel
    let fromRect:    CGRect
    let toRect:      CGRect
    let colorScheme: ColorScheme

    private func anchorPt(rect: CGRect, anchor: ConnectorAnchor) -> CGPoint {
        switch anchor {
        case .top:    return CGPoint(x: rect.midX,              y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX,              y: rect.maxY)
        case .left:   return CGPoint(x: rect.minX,              y: rect.midY)
        case .right:  return CGPoint(x: rect.maxX,              y: rect.midY)
        }
    }

    private var strokeColor: Color {
        switch connector.colorName {
        case "blue":   return .blue
        case "red":    return .red
        case "green":  return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink":   return .pink
        case "teal":   return .teal
        case "gray":   return Color(white: 0.5)
        default:       return colorScheme == .dark ? Color(white: 0.8) : Color(white: 0.2)
        }
    }

    var body: some View {
        let fromPt = anchorPt(rect: fromRect, anchor: connector.fromAnchor)
        let toPt   = anchorPt(rect: toRect,   anchor: connector.toAnchor)
        let lw     = CGFloat(connector.strokeWidth)

        ZStack {
            ConnectorLinePath(
                from: fromPt,
                fromAnchor: connector.fromAnchor,
                to: toPt,
                toAnchor: connector.toAnchor,
                style: connector.lineStyle
            )
                .stroke(strokeColor, style: StrokeStyle(lineWidth: lw, lineCap: .round))

            if connector.hasArrowHead {
                ArrowHeadPath(
                    from: fromPt,
                    fromAnchor: connector.fromAnchor,
                    to: toPt,
                    toAnchor: connector.toAnchor,
                    style: connector.lineStyle,
                    size: max(10, lw * 4)
                )
                    .stroke(strokeColor, style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }
        }
    }
}

private struct ConnectorLinePath: Shape {
    let from:       CGPoint
    let fromAnchor: ConnectorAnchor
    let to:         CGPoint
    let toAnchor:   ConnectorAnchor
    let style:      ConnectorLineStyle

    func path(in rect: CGRect) -> Path {
        ConnectorGeometry.path(
            from: from,
            fromAnchor: fromAnchor,
            to: to,
            toAnchor: toAnchor,
            style: style
        )
    }
}

private struct ArrowHeadPath: Shape {
    let from:       CGPoint
    let fromAnchor: ConnectorAnchor
    let to:         CGPoint
    let toAnchor:   ConnectorAnchor
    let style:      ConnectorLineStyle
    let size:       CGFloat

    func path(in rect: CGRect) -> Path {
        let start = ConnectorGeometry.pointBeforeEnd(
            from: from,
            fromAnchor: fromAnchor,
            to: to,
            toAnchor: toAnchor,
            style: style,
            distance: size
        )
        let angle = atan2(to.y - start.y, to.x - start.x)
        let aa: CGFloat = 0.4
        var p = Path()
        p.move(to: to)
        p.addLine(to: CGPoint(x: to.x - size * cos(angle - aa),
                              y: to.y - size * sin(angle - aa)))
        p.move(to: to)
        p.addLine(to: CGPoint(x: to.x - size * cos(angle + aa),
                              y: to.y - size * sin(angle + aa)))
        return p
    }
}
