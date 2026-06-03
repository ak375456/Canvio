//
//  AddElementMenu.swift
//  Ponder
//

import SwiftUI

struct AddElementMenu: View {
    let position: CGPoint
    let onSelect: (CanvasTool) -> Void
    let onDismiss: () -> Void

    private var tools: [CanvasTool] {
        #if os(iOS)
        return CanvasTool.allCases
        #else
        return CanvasTool.allCases.filter { $0 != .ocrScan }
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(tools) { tool in
                Button { onSelect(tool) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(tool.tint.opacity(0.15))
                                .frame(width: 34, height: 34)
                            Image(systemName: tool.icon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(tool.tint)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(tool.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

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
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
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
    case shape
    case image
    case ocrScan
    case documentScan
    case pdf
    case table
    case audio
    case youtube
    case drawing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text:       return "Text"
        case .stickyNote: return "Sticky Note"
        case .todoList:   return "Todo List"
        case .shape:      return "Shape"
        case .image:      return "Image"
        case .ocrScan:    return "OCR Scan"
        case .documentScan: return "Scan Document"
        case .pdf:        return "PDF"
        case .table:      return "Table"
        case .audio:      return "Audio"
        case .youtube:    return "YouTube"
        case .drawing:    return "Drawing"
        }
    }

    var subtitle: String {
        switch self {
        case .text:       return "Add formatted text"
        case .stickyNote: return "Add a colored note"
        case .todoList:   return "Add a task list"
        case .shape:      return "Lines, rectangles, polygons"
        case .image:      return "Add a photo from your library"
        case .ocrScan:    return "Scan a page into editable text"
        case .documentScan: return "Place scanned pages as a PDF"
        case .pdf:        return "Add a PDF document"
        case .table:      return "Spreadsheet with rows & columns"
        case .audio:      return "Record or import audio"
        case .youtube:    return "Embed a video link"
        case .drawing:    return "Pen, pencil, marker, lasso"
        }
    }

    var icon: String {
        switch self {
        case .text:       return "textformat"
        case .stickyNote: return "note.text"
        case .todoList:   return "checklist"
        case .shape:      return "square.on.circle"
        case .image:      return "photo"
        case .ocrScan:    return "doc.text.viewfinder"
        case .documentScan: return "doc.viewfinder"
        case .pdf:        return "doc.richtext"
        case .table:      return "tablecells"
        case .audio:      return "waveform"
        case .youtube:    return "play.rectangle.fill"
        case .drawing:    return "pencil.and.scribble"
        }
    }

    var tint: Color {
        switch self {
        case .text:       return .blue
        case .stickyNote: return .orange
        case .todoList:   return .green
        case .shape:      return .purple
        case .image:      return .cyan
        case .ocrScan:    return .teal
        case .documentScan: return .red
        case .pdf:        return .red
        case .table:      return .indigo
        case .audio:      return .pink
        case .youtube:    return .red
        case .drawing:    return .orange
        }
    }
}
