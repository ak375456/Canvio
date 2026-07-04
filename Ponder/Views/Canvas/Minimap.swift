//
//  Minimap.swift
//  Ponder
//

import SwiftUI

struct Minimap: View {
    let textElements: [TextElementModel]
    let stickyNotes: [StickyNoteModel]
    let todoLists: [TodoListModel]
    let shapes: [ShapeElementModel]
    let images: [ImageElementModel]
    let pdfs: [PDFElementModel]
    let pdfPages: [PDFPageElementModel]
    let tables: [TableElementModel]
    let audioElements: [AudioElementModel]
    let youtubeElements: [YouTubeElementModel]
    let drawings: [DrawingElementModel]        // ← new
    let symbols: [SymbolElementModel]
    let viewportSize: CGSize
    let canvasOffset: CGSize
    let canvasScale: CGFloat
    let onTapElement: (CGPoint) -> Void
    @Binding var isExpanded: Bool
    var isNavigationActive: Bool = false

    private let mapSize = CGSize(width: 130, height: 95)
    private let hitTargetSize: CGFloat = 22
    private let mapPaddingRatio: CGFloat = 0.12
    private let minimumWorldSize = CGSize(width: 800, height: 580)

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            toggleButton
            if isExpanded {
                Group {
                    if isNavigationActive {
                        restingMapBody
                    } else {
                        mapBody
                    }
                }
                    .frame(width: mapSize.width, height: mapSize.height)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .transition(.scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
            }
        }
    }

    private var restingMapBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.035))
            Image(systemName: "map.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.22))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var toggleButton: some View {
        Button {
            withAnimation(.spring(duration: 0.25)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "map.fill" : "map")
                    .font(.system(size: 11, weight: .semibold))
                if !isExpanded { Text("Map").font(.caption2.weight(.semibold)) }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var mapBody: some View {
        GeometryReader { geo in
            let worldBounds = mapWorldBounds(for: geo.size)
            ZStack {
                ForEach(textElements) { el in
                    dotHit(canvasPoint: CGPoint(x: el.x, y: el.y), color: .blue, mapSize: geo.size, worldBounds: worldBounds, size: 5)
                }
                ForEach(stickyNotes) { note in
                    dotHit(canvasPoint: CGPoint(x: note.x, y: note.y), color: stickyColor(note.colorName), mapSize: geo.size, worldBounds: worldBounds, size: 6)
                }
                ForEach(todoLists) { list in
                    dotHit(canvasPoint: CGPoint(x: list.x, y: list.y), color: .green, mapSize: geo.size, worldBounds: worldBounds, size: 6)
                }
                ForEach(shapes) { shape in
                    dotHit(canvasPoint: CGPoint(x: shape.x, y: shape.y), color: .purple, mapSize: geo.size, worldBounds: worldBounds, size: 5)
                }
                ForEach(images) { img in
                    dotHit(canvasPoint: CGPoint(x: img.x, y: img.y), color: .cyan, mapSize: geo.size, worldBounds: worldBounds, size: 6)
                }
                ForEach(pdfs) { pdf in
                    dotHit(canvasPoint: CGPoint(x: pdf.x, y: pdf.y), color: .red, mapSize: geo.size, worldBounds: worldBounds, size: 6)
                }
                ForEach(pdfPages) { page in
                    dotHit(canvasPoint: CGPoint(x: page.x, y: page.y), color: .red.opacity(0.75), mapSize: geo.size, worldBounds: worldBounds, size: 5)
                }
                ForEach(tables) { tbl in
                    dotHit(canvasPoint: CGPoint(x: tbl.x, y: tbl.y), color: .indigo, mapSize: geo.size, worldBounds: worldBounds, size: 7)
                }
                ForEach(audioElements) { audio in
                    dotHit(canvasPoint: CGPoint(x: audio.x, y: audio.y), color: .pink, mapSize: geo.size, worldBounds: worldBounds, size: 6)
                }
                ForEach(youtubeElements) { video in
                    dotHit(canvasPoint: CGPoint(x: video.x, y: video.y), color: .red, mapSize: geo.size, worldBounds: worldBounds, size: 6)
                }
                ForEach(drawings) { drawing in
                    dotHit(canvasPoint: CGPoint(x: drawing.x, y: drawing.y), color: .orange, mapSize: geo.size, worldBounds: worldBounds, size: 6)
                }
                ForEach(symbols) { symbol in
                    dotHit(canvasPoint: CGPoint(x: symbol.x, y: symbol.y), color: .cyan, mapSize: geo.size, worldBounds: worldBounds, size: 5)
                }
                viewportRect(mapSize: geo.size, worldBounds: worldBounds)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func dotHit(canvasPoint: CGPoint, color: Color,
                        mapSize: CGSize, worldBounds: CGRect, size: CGFloat) -> some View {
        let mapPoint = canvasToMap(canvasPoint, mapSize: mapSize, worldBounds: worldBounds)
        return Button { onTapElement(canvasPoint) } label: {
            ZStack {
                Color.clear
                    .frame(width: hitTargetSize, height: hitTargetSize)
                    .contentShape(Rectangle())
                Circle().fill(color).frame(width: size, height: size)
            }
        }
        .buttonStyle(.plain)
        .position(mapPoint)
    }

    private func viewportRect(mapSize: CGSize, worldBounds: CGRect) -> some View {
        let tl = canvasToMap(CGPoint(
            x: -canvasOffset.width / canvasScale,
            y: -canvasOffset.height / canvasScale
        ), mapSize: mapSize, worldBounds: worldBounds)
        let br = canvasToMap(CGPoint(
            x: (viewportSize.width - canvasOffset.width) / canvasScale,
            y: (viewportSize.height - canvasOffset.height) / canvasScale
        ), mapSize: mapSize, worldBounds: worldBounds)
        let rect = CGRect(x: tl.x, y: tl.y,
                         width: max(8, br.x - tl.x),
                         height: max(8, br.y - tl.y))
        return Rectangle()
            .strokeBorder(Color.accentColor.opacity(0.85), lineWidth: 1.5)
            .background(Rectangle().fill(Color.accentColor.opacity(0.1)))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    private func canvasToMap(_ point: CGPoint, mapSize: CGSize, worldBounds: CGRect) -> CGPoint {
        return CGPoint(
            x: ((point.x - worldBounds.minX) / worldBounds.width) * mapSize.width,
            y: ((point.y - worldBounds.minY) / worldBounds.height) * mapSize.height
        )
    }

    private func mapWorldBounds(for mapSize: CGSize) -> CGRect {
        var bounds = viewportCanvasRect

        for rect in elementRects {
            bounds = bounds.union(rect)
        }

        if bounds.isNull || bounds.isEmpty {
            bounds = CGRect(origin: .zero, size: minimumWorldSize)
        }

        bounds = expand(bounds, minimumSize: minimumWorldSize)

        let padded = bounds.insetBy(
            dx: -bounds.width * mapPaddingRatio,
            dy: -bounds.height * mapPaddingRatio
        )

        return fit(bounds: padded, toAspectRatio: mapSize.width / max(mapSize.height, 1))
    }

    private var viewportCanvasRect: CGRect {
        CGRect(
            x: -canvasOffset.width / canvasScale,
            y: -canvasOffset.height / canvasScale,
            width: viewportSize.width / canvasScale,
            height: viewportSize.height / canvasScale
        )
    }

    private var elementRects: [CGRect] {
        var rects: [CGRect] = []

        rects += textElements.map { centeredRect(x: $0.x, y: $0.y, width: max(160, $0.fontSize * 4), height: max(40, $0.fontSize * 2)) }
        rects += stickyNotes.map { centeredRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        rects += todoLists.map { centeredRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        rects += shapes.map { centeredRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        rects += images.map { centeredRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        rects += pdfs.map { centeredRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        rects += pdfPages.map { centeredRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        rects += tables.map { centeredRect(x: $0.x, y: $0.y, width: $0.totalWidth, height: $0.totalHeight) }
        rects += audioElements.map { centeredRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        rects += youtubeElements.map { centeredRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        rects += drawings.map { centeredRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        rects += symbols.map { centeredRect(x: $0.x, y: $0.y, width: $0.fontSize, height: $0.fontSize) }
        return rects
    }

    private func centeredRect(x: Double, y: Double, width: Double, height: Double) -> CGRect {
        CGRect(
            x: CGFloat(x) - CGFloat(width) / 2,
            y: CGFloat(y) - CGFloat(height) / 2,
            width: max(CGFloat(width), 1),
            height: max(CGFloat(height), 1)
        )
    }

    private func expand(_ rect: CGRect, minimumSize: CGSize) -> CGRect {
        let width = max(rect.width, minimumSize.width)
        let height = max(rect.height, minimumSize.height)

        return CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func fit(bounds: CGRect, toAspectRatio aspectRatio: CGFloat) -> CGRect {
        guard aspectRatio > 0 else { return bounds }

        let currentRatio = bounds.width / max(bounds.height, 1)

        if currentRatio > aspectRatio {
            let height = bounds.width / aspectRatio
            return CGRect(
                x: bounds.minX,
                y: bounds.midY - height / 2,
                width: bounds.width,
                height: height
            )
        } else {
            let width = bounds.height * aspectRatio
            return CGRect(
                x: bounds.midX - width / 2,
                y: bounds.minY,
                width: width,
                height: bounds.height
            )
        }
    }

    private func stickyColor(_ name: String) -> Color {
        switch name {
        case "yellow": return Color(red: 0.95, green: 0.78, blue: 0.20)
        case "orange": return Color(red: 0.95, green: 0.55, blue: 0.20)
        case "pink":   return Color(red: 0.92, green: 0.45, blue: 0.62)
        case "blue":   return Color(red: 0.30, green: 0.65, blue: 0.95)
        case "green":  return Color(red: 0.45, green: 0.75, blue: 0.35)
        default:       return .gray
        }
    }
}
