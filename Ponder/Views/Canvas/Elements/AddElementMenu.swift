//
//  AddElementMenu.swift
//  Ponder
//

import SwiftUI

struct AddElementMenu: View {
    let position: CGPoint
    var lockedTools: Set<CanvasTool> = []
    let onSelect: (CanvasTool) -> Void
    let onDismiss: () -> Void

    private var tools: [CanvasTool] {
        #if os(iOS)
        return CanvasTool.allCases
        #else
        return CanvasTool.allCases.filter { $0 != .scanner }
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(tools) { tool in
                let isLocked = lockedTools.contains(tool)
                Button { onSelect(tool) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(tool.tint.opacity(isLocked ? 0.08 : 0.15))
                                .frame(width: 34, height: 34)
                            Image(systemName: tool.icon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(tool.tint)
                                .opacity(isLocked ? 0.45 : 1)

                            if isLocked {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.black.opacity(0.48))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 16, height: 16)
                                    .background(Color.black.opacity(0.78), in: Circle())
                                    .offset(x: 9, y: -9)
                            }
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(isLocked ? "Free limit reached" : tool.subtitle)
                                .font(.caption2)
                                .foregroundStyle(isLocked ? Color.accentColor : Color.secondary)
                        }
                        Spacer()

                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 22)
                                .background(Color.black.opacity(0.76), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isLocked ? "\(tool.title), Pro required" : tool.title)

                if tool != tools.last {
                    Divider().padding(.leading, 58)
                }
            }
        }
        .frame(width: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
        )
        .position(adjustedPosition)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private var adjustedPosition: CGPoint {
        CGPoint(x: max(140, position.x), y: max(120, position.y))
    }
}

enum CanvasTool: String, CaseIterable, Identifiable {
    case text
    case stickyNote
    case todoList
    case templates
    case shape
    case image
    case scanner
    case pdf
    case table
    case audio
    case youtube
    case lasso
    case drawing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text:       return "Text"
        case .stickyNote: return "Sticky Note"
        case .todoList:   return "Todo List"
        case .templates:  return "Templates"
        case .shape:      return "Shape"
        case .image:      return "Image"
        case .scanner:    return "Scanner"
        case .pdf:        return "PDF"
        case .table:      return "Table"
        case .audio:      return "Audio"
        case .youtube:    return "YouTube"
        case .lasso:      return "Lasso"
        case .drawing:    return "Drawing"
        }
    }

    var subtitle: String {
        switch self {
        case .text:       return "Add formatted text"
        case .stickyNote: return "Add a colored note"
        case .todoList:   return "Add a task list"
        case .templates:  return "Add a ready-made layout"
        case .shape:      return "Lines, rectangles, polygons"
        case .image:      return "Add a photo from your library"
        case .scanner:    return "Scan to text or PDF"
        case .pdf:        return "Add a PDF document"
        case .table:      return "Spreadsheet with rows & columns"
        case .audio:      return "Record or import audio"
        case .youtube:    return "Embed a video link"
        case .lasso:      return "Select multiple canvas items"
        case .drawing:    return "Pen, pencil, marker, lasso"
        }
    }

    var icon: String {
        switch self {
        case .text:       return "textformat"
        case .stickyNote: return "note.text"
        case .todoList:   return "checklist"
        case .templates:  return "square.grid.2x2"
        case .shape:      return "square.on.circle"
        case .image:      return "photo"
        case .scanner:    return "doc.viewfinder"
        case .pdf:        return "doc.richtext"
        case .table:      return "tablecells"
        case .audio:      return "waveform"
        case .youtube:    return "play.rectangle.fill"
        case .lasso:      return "lasso"
        case .drawing:    return "pencil.and.scribble"
        }
    }

    var tint: Color {
        switch self {
        case .text:       return .blue
        case .stickyNote: return .orange
        case .todoList:   return .green
        case .templates:  return .indigo
        case .shape:      return .purple
        case .image:      return .cyan
        case .scanner:    return .teal
        case .pdf:        return .red
        case .table:      return .indigo
        case .audio:      return .pink
        case .youtube:    return .red
        case .lasso:      return .blue
        case .drawing:    return .orange
        }
    }
}
