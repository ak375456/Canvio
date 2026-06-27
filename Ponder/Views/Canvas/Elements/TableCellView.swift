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
    @State private var remoteSyncTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            cellBackground

            if isEditing {
                TextField("", text: $cell.value, axis: .vertical)
                    .font(.system(size: fontSize, weight: cell.isBold ? .semibold : .regular))
                    .foregroundStyle(adaptiveTextColor)
                    .multilineTextAlignment(textAlign)
                    .focused($focused)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .onChange(of: cell.value) { _, _ in
                        cell.updatedAt = Date()
                        try? context.save()
                        scheduleRemoteSync()
                    }
                    .onAppear { focused = true }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { flushRemoteSync() }
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
            if !editing {
                focused = false
                cell.updatedAt = Date()
                try? context.save()
                flushRemoteSync()
            }
        }
        .onDisappear {
            flushRemoteSync()
        }
    }

    private func scheduleRemoteSync() {
        remoteSyncTask?.cancel()
        remoteSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await TableSyncService.shared.upsertCell(cell)
            remoteSyncTask = nil
        }
    }

    private func flushRemoteSync() {
        guard remoteSyncTask != nil else { return }
        remoteSyncTask?.cancel()
        remoteSyncTask = nil
        Task { await TableSyncService.shared.upsertCell(cell) }
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
