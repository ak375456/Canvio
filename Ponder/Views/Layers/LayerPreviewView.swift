import SwiftUI
import PencilKit
import ImageIO

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A deliberately tiny representation of a canvas element. Cheap element types
/// stay vector-based; bitmap-heavy types are rendered lazily at thumbnail size.
struct LayerPreviewView: View {
    let element: any LayerableElement

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))

            preview
                .padding(3)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .frame(width: 54, height: 46)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var preview: some View {
        if let text = element as? TextElementModel {
            textPreview(text)
        } else if let note = element as? StickyNoteModel {
            stickyPreview(note)
        } else if let todo = element as? TodoListModel {
            todoPreview(todo)
        } else if let shape = element as? ShapeElementModel {
            shapePreview(shape)
        } else if let image = element as? ImageElementModel {
            LayerBitmapPreview(source: .image(fileName: image.imageFileName)) {
                fallback(icon: image.layerIcon, tint: image.layerTint)
            }
        } else if let pdf = element as? PDFElementModel {
            LayerBitmapPreview(source: .pdfThumbnail(fileName: pdf.thumbnailFileName)) {
                fallback(icon: pdf.layerIcon, tint: pdf.layerTint)
            }
        } else if let page = element as? PDFPageElementModel {
            LayerBitmapPreview(source: .pdfPage(
                fileName: page.pdfFileName,
                pageIndex: page.pageIndex,
                crop: page.cropRect
            )) {
                fallback(icon: page.layerIcon, tint: page.layerTint)
            }
        } else if let table = element as? TableElementModel {
            tablePreview(table)
        } else if let audio = element as? AudioElementModel {
            audioPreview(audio)
        } else if let youtube = element as? YouTubeElementModel {
            RemoteLayerPreview(urlString: youtube.thumbnailURL) {
                fallback(icon: youtube.layerIcon, tint: youtube.layerTint)
            }
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.black.opacity(0.55), in: Circle())
            }
        } else if let drawing = element as? DrawingElementModel {
            LayerBitmapPreview(source: .drawing(
                id: drawing.id,
                version: drawing.updatedAt.timeIntervalSinceReferenceDate,
                data: drawing.drawingData,
                width: drawing.width,
                height: drawing.height
            )) {
                fallback(icon: drawing.layerIcon, tint: drawing.layerTint)
            }
        } else if let symbol = element as? SymbolElementModel {
            Image(systemName: symbol.symbolName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(TextStyle.color(named: symbol.colorName, fallback: .cyan))
                .minimumScaleFactor(0.5)
        } else {
            fallback(icon: element.layerIcon, tint: element.layerTint)
        }
    }

    private func textPreview(_ text: TextElementModel) -> some View {
        let value = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let font: Font = text.fontName == "system"
            ? .system(size: 10, weight: text.isBold ? .bold : .regular)
            : .custom(text.fontName, size: 11)
        return Text(value.isEmpty ? "Text" : value)
            .font(font)
            .italic(text.isItalic)
            .foregroundStyle(TextStyle.color(named: text.colorName))
            .multilineTextAlignment(text.textAlignment)
            .lineLimit(3)
            .minimumScaleFactor(0.55)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(3)
            .background(TextStyle.color(named: text.bgColorName, fallback: .clear).opacity(text.bgColorName == "none" ? 0 : 1))
    }

    private func stickyPreview(_ note: StickyNoteModel) -> some View {
        let palette = StickyNoteColor.color(named: note.colorName)
        return ZStack(alignment: .topLeading) {
            palette.background
            Text(note.text.isEmpty ? "Note" : note.text)
                .font(.system(size: 7, weight: note.isBold ? .bold : .regular))
                .foregroundStyle(.black.opacity(0.72))
                .lineLimit(4)
                .padding(5)
        }
        .overlay(alignment: .topTrailing) {
            TriangleFold().fill(palette.foldShadow).frame(width: 10, height: 10)
        }
    }

    private func todoPreview(_ todo: TodoListModel) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(todo.title.isEmpty ? "Todo" : todo.title)
                .font(.system(size: 7, weight: .bold))
                .lineLimit(1)
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 3) {
                    Image(systemName: index == 0 ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 6))
                        .foregroundStyle(index == 0 ? .green : .secondary)
                    Capsule().fill(Color.secondary.opacity(0.28))
                        .frame(width: CGFloat(25 - index * 4), height: 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(5)
    }

    private func shapePreview(_ shape: ShapeElementModel) -> some View {
        let stroke = ShapeColorPalette.color(named: shape.strokeColorName)
        let fill = shape.hasFill
            ? ShapeColorPalette.color(named: shape.fillColorName).opacity(0.6)
            : Color.clear
        return Image(systemName: shape.shapeKind.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .symbolRenderingMode(.palette)
            .foregroundStyle(stroke, fill)
            .padding(8)
            .rotationEffect(.degrees(shape.rotation))
    }

    private func tablePreview(_ table: TableElementModel) -> some View {
        Canvas { context, size in
            let rows = max(1, min(table.rowCount, 5))
            let cols = max(1, min(table.colCount, 5))
            let cellWidth = size.width / CGFloat(cols)
            let cellHeight = size.height / CGFloat(rows)

            if table.showColHeaders {
                context.fill(
                    Path(CGRect(x: 0, y: 0, width: size.width, height: cellHeight)),
                    with: .color(.indigo.opacity(0.16))
                )
            }
            if table.showRowHeaders {
                context.fill(
                    Path(CGRect(x: 0, y: 0, width: cellWidth, height: size.height)),
                    with: .color(.indigo.opacity(0.12))
                )
            }

            var grid = Path()
            for col in 0...cols {
                let x = CGFloat(col) * cellWidth
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 0...rows {
                let y = CGFloat(row) * cellHeight
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.secondary.opacity(0.35)), lineWidth: 0.65)
        }
        .padding(4)
    }

    private func audioPreview(_ audio: AudioElementModel) -> some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<15, id: \.self) { index in
                let phase = Double(index) + audio.duration.truncatingRemainder(dividingBy: 7)
                Capsule()
                    .fill(Color.pink.opacity(0.78))
                    .frame(width: 1.6, height: 5 + abs(sin(phase * 0.82)) * 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fallback(icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(tint)
    }
}

private struct TriangleFold: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private enum LayerBitmapSource {
    case image(fileName: String)
    case pdfThumbnail(fileName: String)
    case pdfPage(fileName: String, pageIndex: Int, crop: PDFNormalizedRect)
    case drawing(id: UUID, version: TimeInterval, data: Data, width: Double, height: Double)

    var cacheKey: String {
        switch self {
        case .image(let fileName): return "image:\(fileName)"
        case .pdfThumbnail(let fileName): return "pdf-thumb:\(fileName)"
        case .pdfPage(let fileName, let page, let crop):
            return "pdf-page:\(fileName):\(page):\(crop.id)"
        case .drawing(let id, let version, let data, let width, let height):
            return "drawing:\(id):\(version):\(data.count):\(Int(width))x\(Int(height))"
        }
    }

    func render() -> PlatformImage? {
        switch self {
        case .image(let fileName):
            return ImageStorageService.thumbnail(fileName: fileName, maxPixelSize: 112)
        case .pdfThumbnail(let fileName):
            let url = PDFStorageService.thumbnailsDirectory.appendingPathComponent(fileName)
            return LayerPreviewRasterizer.downsample(url: url, maxPixelSize: 112)
        case .pdfPage(let fileName, let pageIndex, let crop):
            return PDFPageRenderingService.render(
                fileName: fileName,
                pageIndex: pageIndex,
                crop: crop,
                maxPixels: 112
            )
        case .drawing(_, _, let data, let width, let height):
            guard let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
            let size = CGSize(width: max(1, width), height: max(1, height))
            let scale = min(1, 112 / max(size.width, size.height))
            return drawing.image(from: CGRect(origin: .zero, size: size), scale: scale)
        }
    }
}

private struct LayerBitmapPreview<Fallback: View>: View {
    let source: LayerBitmapSource
    @ViewBuilder let fallback: () -> Fallback
    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image {
                platformImage(image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                fallback()
            }
        }
        .task(id: source.cacheKey) {
            if let cached = LayerPreviewImageCache.shared.image(for: source.cacheKey) {
                image = cached
                return
            }
            let rendered = await Task.detached(priority: .utility) { source.render() }.value
            guard !Task.isCancelled, let rendered else { return }
            LayerPreviewImageCache.shared.insert(rendered, for: source.cacheKey)
            image = rendered
        }
    }
}

private struct RemoteLayerPreview<Fallback: View>: View {
    let urlString: String
    @ViewBuilder let fallback: () -> Fallback
    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image {
                platformImage(image).resizable().aspectRatio(contentMode: .fill)
            } else {
                fallback()
            }
        }
        .task(id: urlString) {
            let key = "remote:\(urlString)"
            if let cached = LayerPreviewImageCache.shared.image(for: key) {
                image = cached
                return
            }
            guard let url = URL(string: urlString) else { return }
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 12
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  !Task.isCancelled,
                  let rendered = LayerPreviewRasterizer.downsample(data: data, maxPixelSize: 112)
            else { return }
            LayerPreviewImageCache.shared.insert(rendered, for: key)
            image = rendered
        }
    }
}

@MainActor
private final class LayerPreviewImageCache {
    static let shared = LayerPreviewImageCache()
    private let cache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 10 * 1024 * 1024
        return cache
    }()

    func image(for key: String) -> PlatformImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: PlatformImage, for key: String) {
        cache.setObject(image, forKey: key as NSString, cost: 112 * 112 * 4)
    }
}

private enum LayerPreviewRasterizer {
    static func downsample(url: URL, maxPixelSize: CGFloat) -> PlatformImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return downsample(source: source, maxPixelSize: maxPixelSize)
    }

    static func downsample(data: Data, maxPixelSize: CGFloat) -> PlatformImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return downsample(source: source, maxPixelSize: maxPixelSize)
    }

    private static func downsample(source: CGImageSource, maxPixelSize: CGFloat) -> PlatformImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #else
        return NSImage(cgImage: cgImage, size: .zero)
        #endif
    }
}

@ViewBuilder
private func platformImage(_ image: PlatformImage) -> Image {
    #if canImport(UIKit)
    Image(uiImage: image)
    #else
    Image(nsImage: image)
    #endif
}
