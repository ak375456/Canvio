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
    let tables: [TableElementModel]
    let audioElements: [AudioElementModel]
    let drawings: [DrawingElementModel]        // ← new
    let viewportSize: CGSize
    let canvasOffset: CGSize
    let canvasScale: CGFloat
    let onTapElement: (CGPoint) -> Void
    @Binding var isExpanded: Bool

    private let mapSize = CGSize(width: 130, height: 95)
    private let worldSize: CGFloat = 4000
    private let hitTargetSize: CGFloat = 22

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            toggleButton
            if isExpanded {
                mapBody
                    .frame(width: mapSize.width, height: mapSize.height)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
                    .transition(.scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
            }
        }
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
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var mapBody: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(textElements) { el in
                    dotHit(canvasPoint: CGPoint(x: el.x, y: el.y), color: .blue, mapSize: geo.size, size: 5)
                }
                ForEach(stickyNotes) { note in
                    dotHit(canvasPoint: CGPoint(x: note.x, y: note.y), color: stickyColor(note.colorName), mapSize: geo.size, size: 6)
                }
                ForEach(todoLists) { list in
                    dotHit(canvasPoint: CGPoint(x: list.x, y: list.y), color: .green, mapSize: geo.size, size: 6)
                }
                ForEach(shapes) { shape in
                    dotHit(canvasPoint: CGPoint(x: shape.x, y: shape.y), color: .purple, mapSize: geo.size, size: 5)
                }
                ForEach(images) { img in
                    dotHit(canvasPoint: CGPoint(x: img.x, y: img.y), color: .cyan, mapSize: geo.size, size: 6)
                }
                ForEach(pdfs) { pdf in
                    dotHit(canvasPoint: CGPoint(x: pdf.x, y: pdf.y), color: .red, mapSize: geo.size, size: 6)
                }
                ForEach(tables) { tbl in
                    dotHit(canvasPoint: CGPoint(x: tbl.x, y: tbl.y), color: .indigo, mapSize: geo.size, size: 7)
                }
                ForEach(audioElements) { audio in
                    dotHit(canvasPoint: CGPoint(x: audio.x, y: audio.y), color: .pink, mapSize: geo.size, size: 6)
                }
                ForEach(drawings) { drawing in
                    dotHit(canvasPoint: CGPoint(x: drawing.x, y: drawing.y), color: .orange, mapSize: geo.size, size: 6)
                }
                viewportRect(mapSize: geo.size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func dotHit(canvasPoint: CGPoint, color: Color,
                        mapSize: CGSize, size: CGFloat) -> some View {
        let mapPoint = canvasToMap(canvasPoint, mapSize: mapSize)
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

    private func viewportRect(mapSize: CGSize) -> some View {
        let tl = canvasToMap(CGPoint(
            x: -canvasOffset.width / canvasScale,
            y: -canvasOffset.height / canvasScale
        ), mapSize: mapSize)
        let br = canvasToMap(CGPoint(
            x: (viewportSize.width - canvasOffset.width) / canvasScale,
            y: (viewportSize.height - canvasOffset.height) / canvasScale
        ), mapSize: mapSize)
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

    private func canvasToMap(_ point: CGPoint, mapSize: CGSize) -> CGPoint {
        CGPoint(
            x: ((point.x + worldSize / 2) / worldSize) * mapSize.width,
            y: ((point.y + worldSize / 2) / worldSize) * mapSize.height
        )
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
