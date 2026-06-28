//
//  TableCellView.swift
//  Ponder
//

import SwiftUI
import SwiftData

struct TableCellView: View {
    @Bindable var cell: TableCellModel
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let fontSize: CGFloat
    let isSelected: Bool
    let isEditing: Bool
    let isHeader: Bool
    let colorScheme: ColorScheme
    @Environment(\.modelContext) private var context
    @FocusState private var focused: Bool
    @StateObject private var textEditing = EditableTextBehavior()

    var body: some View {
        ZStack {
            cellBackground

            if isEditing {
                TextField("", text: $textEditing.draft, axis: .vertical)
                    .font(.system(size: fontSize, weight: cell.isBold ? .semibold : .regular))
                    .foregroundStyle(adaptiveTextColor)
                    .multilineTextAlignment(textAlign)
                    .focused($focused)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .onChange(of: textEditing.draft) { _, _ in
                        textEditing.handleDraftChange(
                            localSave: saveCellValue,
                            remoteSync: syncCell
                        )
                    }
                    .onAppear {
                        textEditing.load(cell.value)
                        focused = true
                    }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused {
                            textEditing.flushRemoteSync(syncCell)
                        }
                    }
            } else {
                Text(cell.value)
                    .font(.system(size: fontSize, weight: cell.isBold ? .semibold : .regular))
                    .foregroundStyle(adaptiveTextColor)
                    .multilineTextAlignment(textAlign)
                    .lineLimit(3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: frameAlignment
                    )
            }
        }
        .frame(
            width: cellWidth * CGFloat(max(1, cell.colSpan)),
            height: cellHeight
        )
        .border(Color.secondary.opacity(isHeader ? 0.35 : 0.2), width: 0.5)
        .overlay(
            Rectangle()
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.clear,
                    lineWidth: 1.5
                )
        )
        .onChange(of: isEditing) { _, editing in
            if editing {
                textEditing.load(cell.value, force: true)
                focused = true
            } else {
                focused = false
                textEditing.commitDraft(
                    localSave: saveCellValue,
                    remoteSync: syncCell
                )
            }
        }
        .onChange(of: cell.value) { _, newValue in
            if !isEditing {
                textEditing.load(newValue)
            }
        }
        .onDisappear {
            textEditing.flushRemoteSync(syncCell)
        }
    }

    private func saveCellValue(_ value: String) -> Bool {
        guard cell.value != value else { return false }
        cell.value = value
        cell.updatedAt = Date()
        try? context.save()
        return true
    }

    private func syncCell() async {
        await TableSyncService.shared.upsertCell(cell)
    }

    private var cellBackground: some View {
        Group {
            if isHeader {
                Color.secondary.opacity(colorScheme == .dark ? 0.25 : 0.12)
            } else if cell.backgroundColorName != "clear" {
                colorFromName(cell.backgroundColorName)
            } else {
                Color.clear
            }
        }
    }

    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var textAlign: TextAlignment {
        switch cell.alignmentRaw {
        case "center":   return .center
        case "trailing": return .trailing
        default:         return .leading
        }
    }

    private var frameAlignment: Alignment {
        switch cell.alignmentRaw {
        case "center":   return .center
        case "trailing": return .trailing
        default:         return .leading
        }
    }

    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "blue":   return .blue.opacity(0.25)
        case "green":  return .green.opacity(0.25)
        case "yellow": return .yellow.opacity(0.35)
        case "orange": return .orange.opacity(0.25)
        case "red":    return .red.opacity(0.25)
        case "purple": return .purple.opacity(0.25)
        case "gray":   return .gray.opacity(0.2)
        default:       return .clear
        }
    }
}
