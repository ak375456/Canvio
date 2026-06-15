//
//  CanvasThumbnailRenderer.swift
//  Ponder
//

import SwiftUI
import SwiftData

// MARK: - Thumbnail size constants
private let kThumbWidth:  CGFloat = 360
private let kThumbHeight: CGFloat = 200
private let kThumbScale:  CGFloat = 2

// MARK: - Renderer

@MainActor
enum CanvasThumbnailRenderer {

    static func generate(
        canvas: CanvasModel,
        textElements:  [TextElementModel],
        stickyNotes:   [StickyNoteModel],
        todoLists:     [TodoListModel],
        shapes:        [ShapeElementModel],
        images:        [ImageElementModel],
        drawings:      [DrawingElementModel],
        gridStyle:     GridStyle = .dotted,
        backgroundMode: CanvasBackgroundMode = .adaptive,
        backgroundPalette: CanvasBackgroundPalette = .neutral,
        context:       ModelContext
    ) {
        guard let jpeg = renderThumbnailData(
            canvas: canvas,
            textElements: textElements,
            stickyNotes: stickyNotes,
            todoLists: todoLists,
            shapes: shapes,
            images: images,
            drawings: drawings,
            gridStyle: gridStyle,
            backgroundMode: backgroundMode,
            backgroundPalette: backgroundPalette
        ) else { return }

        canvas.thumbnailData = jpeg
        try? context.save()
    }

    static func generatePageThumbnail(
        page: CanvasPageModel,
        canvas: CanvasModel,
        textElements: [TextElementModel],
        stickyNotes: [StickyNoteModel],
        todoLists: [TodoListModel],
        shapes: [ShapeElementModel],
        images: [ImageElementModel],
        drawings: [DrawingElementModel],
        gridStyle: GridStyle = .dotted,
        backgroundMode: CanvasBackgroundMode = .adaptive,
        backgroundPalette: CanvasBackgroundPalette = .neutral,
        context: ModelContext
    ) {
        guard let jpeg = renderThumbnailData(
            canvas: canvas,
            textElements: textElements,
            stickyNotes: stickyNotes,
            todoLists: todoLists,
            shapes: shapes,
            images: images,
            drawings: drawings,
            gridStyle: gridStyle,
            backgroundMode: backgroundMode,
            backgroundPalette: backgroundPalette
        ) else { return }

        page.thumbnailData = jpeg
        canvas.thumbnailData = jpeg
        try? context.save()
    }

    private static func renderThumbnailData(
        canvas: CanvasModel,
        textElements: [TextElementModel],
        stickyNotes: [StickyNoteModel],
        todoLists: [TodoListModel],
        shapes: [ShapeElementModel],
        images: [ImageElementModel],
        drawings: [DrawingElementModel],
        gridStyle: GridStyle,
        backgroundMode: CanvasBackgroundMode,
        backgroundPalette: CanvasBackgroundPalette
    ) -> Data? {
        let snapshot = CanvasThumbnailSnapshot(
            canvas:       canvas,
            textElements: textElements,
            stickyNotes:  stickyNotes,
            todoLists:    todoLists,
            shapes:       shapes,
            images:       images,
            drawings:     drawings,
            gridStyle:    gridStyle,
            backgroundMode: backgroundMode,
            backgroundPalette: backgroundPalette,
            width:        kThumbWidth,
            height:       kThumbHeight
        )

        let renderer = ImageRenderer(content: snapshot)
        renderer.scale = kThumbScale

        #if os(iOS)
        guard let uiImage = renderer.uiImage else { return nil }

        // Flatten onto an opaque bitmap — JPEG has no alpha channel
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale  = uiImage.scale
        let opaque = UIGraphicsImageRenderer(size: uiImage.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: uiImage.size))
            uiImage.draw(at: .zero)
        }
        return opaque.jpegData(compressionQuality: 0.75)

        #elseif os(macOS)
        guard let nsImage = renderer.nsImage else { return nil }

        let size = nsImage.size
        let pixelW = Int(size.width  * kThumbScale)
        let pixelH = Int(size.height * kThumbScale)

        // Use RGBA (4 samples) — macOS CGBitmapContext requires alpha channel.
        // We composite onto a white background so the JPEG output looks opaque.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        guard let gc = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = gc
        // Fill white background so JPEG has no transparency
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        nsImage.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
        #else
        return nil
        #endif
    }
}

// MARK: - Snapshot view

private struct CanvasThumbnailSnapshot: View {
    let canvas:       CanvasModel
    let textElements: [TextElementModel]
    let stickyNotes:  [StickyNoteModel]
    let todoLists:    [TodoListModel]
    let shapes:       [ShapeElementModel]
    let images:       [ImageElementModel]
    let drawings:     [DrawingElementModel]
    let gridStyle:     GridStyle
    let backgroundMode: CanvasBackgroundMode
    let backgroundPalette: CanvasBackgroundPalette
    let width:        CGFloat
    let height:       CGFloat

    private var allPositions: [(x: Double, y: Double)] {
        var pts: [(Double, Double)] = []
        textElements.forEach { pts.append(($0.x, $0.y)) }
        stickyNotes.forEach  { pts.append(($0.x, $0.y)) }
        todoLists.forEach    { pts.append(($0.x, $0.y)) }
        shapes.forEach       { pts.append(($0.x, $0.y)) }
        images.forEach       { pts.append(($0.x, $0.y)) }
        drawings.forEach     { pts.append(($0.x, $0.y)) }
        return pts
    }

    private var transform: (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        guard !allPositions.isEmpty else { return (1, width / 2, height / 2) }
        let padding: CGFloat = 20
        let minX = allPositions.map { CGFloat($0.x) }.min()! - 80
        let minY = allPositions.map { CGFloat($0.y) }.min()! - 80
        let maxX = allPositions.map { CGFloat($0.x) }.max()! + 80
        let maxY = allPositions.map { CGFloat($0.y) }.max()! + 80
        let contentW = maxX - minX
        let contentH = maxY - minY
        guard contentW > 0, contentH > 0 else { return (1, width / 2, height / 2) }
        let scaleX = (width  - padding * 2) / contentW
        let scaleY = (height - padding * 2) / contentH
        let scale  = min(scaleX, scaleY, 1.0)
        return (scale, -minX * scale + padding, -minY * scale + padding)
    }

    var body: some View {
        let t = transform
        ZStack(alignment: .topLeading) {
            CanvasGridView(
                offset: CGSize(width: t.offsetX, height: t.offsetY),
                scale: t.scale,
                style: gridStyle,
                backgroundMode: backgroundMode,
                backgroundPalette: backgroundPalette
            )

            ZStack(alignment: .topLeading) {
                ForEach(shapes) { shape in
                    ThumbnailShapeView(shape: shape)
                        .position(x: CGFloat(shape.x) * t.scale + t.offsetX,
                                  y: CGFloat(shape.y) * t.scale + t.offsetY)
                }
                ForEach(stickyNotes) { note in
                    ThumbnailStickyView(note: note, scale: t.scale)
                        .position(x: CGFloat(note.x) * t.scale + t.offsetX,
                                  y: CGFloat(note.y) * t.scale + t.offsetY)
                }
                ForEach(todoLists) { list in
                    ThumbnailTodoView(list: list, scale: t.scale)
                        .position(x: CGFloat(list.x) * t.scale + t.offsetX,
                                  y: CGFloat(list.y) * t.scale + t.offsetY)
                }
                ForEach(images) { img in
                    ThumbnailImageView(element: img, scale: t.scale)
                        .position(x: CGFloat(img.x) * t.scale + t.offsetX,
                                  y: CGFloat(img.y) * t.scale + t.offsetY)
                }
                ForEach(textElements) { text in
                    ThumbnailTextView(element: text, scale: t.scale)
                        .position(x: CGFloat(text.x) * t.scale + t.offsetX,
                                  y: CGFloat(text.y) * t.scale + t.offsetY)
                }
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

// MARK: - Lightweight element sub-views

private struct ThumbnailShapeView: View {
    let shape: ShapeElementModel
    private var stroke: Color { thumbColor(shape.strokeColorName) }
    private var fill:   Color { thumbColor(shape.fillColorName) }
    var body: some View {
        Group {
            switch shape.shapeKind {
            case .rectangle:
                ZStack {
                    if shape.hasFill { RoundedRectangle(cornerRadius: 3).fill(fill) }
                    if shape.hasVisibleStroke {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(stroke, lineWidth: CGFloat(shape.strokeWidth))
                    }
                }
                    .frame(width: CGFloat(shape.width), height: CGFloat(shape.height))
            case .line:
                if shape.hasVisibleStroke {
                    Rectangle()
                        .fill(stroke)
                        .frame(width: CGFloat(shape.width), height: CGFloat(max(1, shape.strokeWidth)))
                } else {
                    Color.clear
                }
            case .triangle:
                ZStack {
                    if shape.hasFill { TriangleShape(variant: shape.triangleVariant).fill(fill) }
                    if shape.hasVisibleStroke {
                        TriangleShape(variant: shape.triangleVariant)
                            .stroke(stroke, lineWidth: CGFloat(shape.strokeWidth))
                    }
                }
                    .frame(width: CGFloat(shape.width), height: CGFloat(shape.height))
            case .polygon:
                ZStack {
                    if shape.hasFill { PolygonShape(sides: shape.polygonSides).fill(fill) }
                    if shape.hasVisibleStroke {
                        PolygonShape(sides: shape.polygonSides)
                            .stroke(stroke, lineWidth: CGFloat(shape.strokeWidth))
                    }
                }
                    .frame(width: CGFloat(shape.width), height: CGFloat(shape.height))
            case .circle:
                ZStack {
                    if shape.hasFill { Circle().fill(fill) }
                    if shape.hasVisibleStroke {
                        Circle().strokeBorder(stroke, lineWidth: CGFloat(shape.strokeWidth))
                    }
                }
                    .frame(width: CGFloat(shape.width), height: CGFloat(shape.height))
            }
        }
        .rotationEffect(.degrees(shape.rotation))
    }
}

private struct ThumbnailStickyView: View {
    let note: StickyNoteModel
    let scale: CGFloat
    private var bg: Color { StickyNoteColor.color(named: note.colorName).background }
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(bg)
            .frame(width: CGFloat(note.width) * scale,
                   height: CGFloat(note.height) * scale)
    }
}

private struct ThumbnailTodoView: View {
    let list: TodoListModel
    let scale: CGFloat
    private var accent: Color { thumbColor(list.colorName) }
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(accent.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(accent.opacity(0.3), lineWidth: 1))
            .frame(width: CGFloat(list.width) * scale,
                   height: CGFloat(list.height) * scale)
    }
}

private struct ThumbnailImageView: View {
    let element: ImageElementModel
    let scale: CGFloat
    var body: some View {
        Group {
            if let img = ImageStorageService.load(fileName: element.imageFileName) {
                #if os(iOS)
                Image(uiImage: img).resizable().scaledToFill()
                #elseif os(macOS)
                Image(nsImage: img).resizable().scaledToFill()
                #endif
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15))
            }
        }
        .frame(width: CGFloat(element.width)  * scale,
               height: CGFloat(element.height) * scale)
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(element.cornerRadius) * scale))
        .opacity(element.opacity)
        .rotationEffect(.degrees(element.rotation))
    }
}

private struct ThumbnailTextView: View {
    let element: TextElementModel
    let scale: CGFloat
    private var color: Color {
        TextStyle.colorOptions.first { $0.name == element.colorName }?.color ?? .primary
    }
    private var font: Font {
        let size = max(8, element.fontSize * Double(scale))
        var f: Font = element.fontName == "system"
            ? .system(size: size)
            : .custom(element.fontName, size: size)
        if element.isBold   { f = f.bold() }
        if element.isItalic { f = f.italic() }
        return f
    }
    var body: some View {
        Text(element.text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(3)
            .fixedSize()
    }
}

// MARK: - Color helper
private func thumbColor(_ name: String) -> Color {
    ShapeColorPalette.color(named: name)
}
