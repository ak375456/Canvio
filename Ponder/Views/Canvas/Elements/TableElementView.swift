//
//  TableElementView.swift
//  Ponder
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TableElementView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var table: TableElementModel
    let allCells: [TableCellModel]
    let canvasScale: CGFloat
    let canvasBoundary: CGSize
    @ObservedObject var vm: TableElementViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect: Bool = false
    let onImportCSV: () -> Void
    let onExportCSV: () -> Void
    var onExternalTap: (() -> Void)? = nil
    var onMultiSelectTap: (() -> Void)? = nil
    var isCanvasGestureActive: Bool = false

    @State private var dragOffset: CGSize = .zero
    @State private var rotationAngle: Double = 0
    @State private var hasLoadedRotation = false
    @State private var resizeStartCellWidth: Double = 0
    @State private var resizeStartCellHeight: Double = 0

    private var isTableSelected: Bool { vm.selectedTableID == table.id }
    private var tableCells: [TableCellModel] { allCells.filter { $0.tableID == table.id } }
    private var selectedCell: TableCellModel? {
        guard let id = vm.selectedCellID else { return nil }
        return tableCells.first { $0.id == id }
    }

    private let handleSize: CGFloat = 28
    private let handleHitSize: CGFloat = 52

    private var rowHeaderWidth: CGFloat { table.showRowHeaders ? 36 : 0 }
    private var colHeaderHeight: CGFloat {
        table.showColHeaders ? max(28, CGFloat(table.cellHeight) * 0.6) : 0
    }
    private var totalWidth: CGFloat {
        rowHeaderWidth + CGFloat(table.cellWidth) * CGFloat(table.colCount)
    }
    private var totalHeight: CGFloat {
        colHeaderHeight + CGFloat(table.cellHeight) * CGFloat(table.rowCount)
    }
    private var adaptiveFontSize: CGFloat {
        let size = CGFloat(table.cellHeight) * 0.32
        return max(10, min(18, size))
    }

    var body: some View {
        ZStack {
            tableContent
            selectionRing

            if isTableSelected && !isMultiSelectMode {
                TableToolbarView(
                    table: table, cells: tableCells, selectedCell: selectedCell, vm: vm,
                    onDelete: { vm.delete(table: table, cells: tableCells, context: context) },
                    onImportCSV: onImportCSV, onExportCSV: onExportCSV
                )
                .fixedSize(horizontal: true, vertical: false)
                .offset(y: -(totalHeight / 2) - 30)

                Button { vm.stopAll() } label: { handleCircle(icon: "xmark", color: .gray) }
                    .buttonStyle(.plain)
                    .offset(x: -(totalWidth / 2), y: -(totalHeight / 2))

                resizeHandle
            }

            if isMultiSelectMode {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isCanvasGestureActive else { return }
                        onMultiSelectTap?()
                    }
            }
        }
        .frame(width: totalWidth, height: totalHeight)
        .rotationEffect(.degrees(rotationAngle), anchor: .center)
        .position(x: table.x + dragOffset.width, y: table.y + dragOffset.height)
        .gesture(canMove ? moveDragGesture : nil)
        .onAppear {
            if !hasLoadedRotation { rotationAngle = table.rotation; hasLoadedRotation = true }
        }
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isMultiSelectMode {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isSelectedInMultiSelect ? Color.blue : Color.white.opacity(0.3),
                    lineWidth: isSelectedInMultiSelect ? 2.5 : 1
                )
                .frame(width: totalWidth, height: totalHeight)
                .overlay(alignment: .topTrailing) {
                    if isSelectedInMultiSelect {
                        ZStack {
                            Circle().fill(Color.blue).frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        }.offset(x: 8, y: -8)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isSelectedInMultiSelect)
        }
    }

    private var resizeHandle: some View {
        ZStack {
            Color.clear.frame(width: handleHitSize, height: handleHitSize).contentShape(Rectangle())
            handleCircle(icon: "arrow.up.left.and.arrow.down.right", color: .green)
        }
        .offset(x: totalWidth / 2, y: totalHeight / 2)
        .gesture(resizeGesture)
    }

    private var tableContent: some View {
        VStack(spacing: 0) {
            if table.showColHeaders {
                HStack(spacing: 0) {
                    if table.showRowHeaders { cornerCell }
                    ForEach(0..<table.colCount, id: \.self) { c in colHeaderCell(text: colLabel(c)) }
                }
            }
            ForEach(0..<table.rowCount, id: \.self) { r in
                HStack(spacing: 0) {
                    if table.showRowHeaders { rowHeaderCell(text: "\(r + 1)") }
                    ForEach(0..<table.colCount, id: \.self) { c in cellView(row: r, col: c) }
                }
            }
        }
        .background(Color(colorScheme == .dark ? .black : .white).opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isTableSelected && !isMultiSelectMode
                        ? Color.accentColor.opacity(0.7)
                        : Color.secondary.opacity(0.3),
                    lineWidth: isTableSelected && !isMultiSelectMode ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isMultiSelectMode, !isCanvasGestureActive else { return }
            if !isTableSelected { onExternalTap?(); vm.selectTable(id: table.id) }
            else { vm.stopEditing() }
        }
    }

    private var cornerCell: some View {
        Color.secondary.opacity(colorScheme == .dark ? 0.25 : 0.12)
            .frame(width: rowHeaderWidth, height: colHeaderHeight)
            .border(Color.secondary.opacity(0.25), width: 0.5)
    }

    private func colHeaderCell(text: String) -> some View {
        Text(text)
            .font(.system(size: adaptiveFontSize * 0.85, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: CGFloat(table.cellWidth), height: colHeaderHeight)
            .background(Color.secondary.opacity(colorScheme == .dark ? 0.2 : 0.1))
            .border(Color.secondary.opacity(0.25), width: 0.5)
    }

    private func rowHeaderCell(text: String) -> some View {
        Text(text)
            .font(.system(size: adaptiveFontSize * 0.85, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: rowHeaderWidth, height: CGFloat(table.cellHeight))
            .background(Color.secondary.opacity(colorScheme == .dark ? 0.2 : 0.1))
            .border(Color.secondary.opacity(0.25), width: 0.5)
    }

    @ViewBuilder
    private func cellView(row: Int, col: Int) -> some View {
        if let cell = tableCells.first(where: { $0.row == row && $0.col == col }) {
            if cell.isMerged {
                Color.clear.frame(width: 0, height: 0)
            } else {
                TappableTableCell(
                    cell: cell,
                    cellWidth: CGFloat(table.cellWidth),
                    cellHeight: CGFloat(table.cellHeight),
                    fontSize: adaptiveFontSize,
                    isSelected: vm.selectedCellID == cell.id,
                    isEditing: vm.editingCellID == cell.id,
                    isMultiSelectMode: isMultiSelectMode,
                    isCanvasGestureActive: isCanvasGestureActive,
                    colorScheme: colorScheme,
                    onSingleTap: { handleSingleTap(cell: cell) },
                    onDoubleTap: { handleDoubleTap(cell: cell) }
                )
            }
        }
    }

    private func colLabel(_ col: Int) -> String {
        var result = ""
        var n = col
        repeat {
            result = String(UnicodeScalar(65 + (n % 26))!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }

    private func handleSingleTap(cell: TableCellModel) {
        guard !isMultiSelectMode, !isCanvasGestureActive else { return }
        if !isTableSelected { vm.selectTable(id: table.id) }
        else { if vm.editingCellID != cell.id { vm.selectCell(id: cell.id) } }
    }

    private func handleDoubleTap(cell: TableCellModel) {
        guard !isMultiSelectMode, !isCanvasGestureActive else { return }
        if !isTableSelected { vm.selectTable(id: table.id) }
        vm.startEditing(id: cell.id)
    }

    private func handleCircle(icon: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color).frame(width: handleSize, height: handleSize)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
        }
    }

    private var resizeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if resizeStartCellWidth == 0 {
                    resizeStartCellWidth = table.cellWidth
                    resizeStartCellHeight = table.cellHeight
                }
                let dw = Double(value.translation.width) / Double(table.colCount)
                let dh = Double(value.translation.height) / Double(table.rowCount)
                table.cellWidth  = max(40, min(300, resizeStartCellWidth + dw))
                table.cellHeight = max(28, min(150, resizeStartCellHeight + dh))
            }
            .onEnded { _ in
                table.cellWidth  = max(40, min(300, table.cellWidth))
                table.cellHeight = max(28, min(150, table.cellHeight))
                table.updatedAt = Date()
                try? context.save()
                // Sync table resize to Supabase
                Task { await TableSyncService.shared.upsertTable(table) }
                resizeStartCellWidth = 0
                resizeStartCellHeight = 0
            }
    }

    private var moveDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard canMove else {
                    dragOffset = .zero
                    return
                }
                if vm.editingCellID == nil { dragOffset = value.translation }
            }
            .onEnded { value in
                guard canMove else {
                    dragOffset = .zero
                    return
                }
                if vm.editingCellID == nil {
                    let t = value.translation; dragOffset = .zero
                    vm.updatePosition(table: table, translation: t,
                                      scale: canvasScale, boundary: canvasBoundary, context: context)
                } else {
                    dragOffset = .zero
                }
            }
    }

    private var canMove: Bool {
        isTableSelected && !isMultiSelectMode && !isCanvasGestureActive
    }

    private struct TappableTableCell: View {
        @Bindable var cell: TableCellModel
        let cellWidth: CGFloat
        let cellHeight: CGFloat
        let fontSize: CGFloat
        let isSelected: Bool
        let isEditing: Bool
        let isMultiSelectMode: Bool
        let isCanvasGestureActive: Bool
        let colorScheme: ColorScheme
        let onSingleTap: () -> Void
        let onDoubleTap: () -> Void

        @State private var tapTimer: Timer? = nil
        @State private var tapCount = 0

        var body: some View {
            TableCellView(
                cell: cell, cellWidth: cellWidth, cellHeight: cellHeight,
                fontSize: fontSize, isSelected: isSelected, isEditing: isEditing,
                isHeader: false, colorScheme: colorScheme
            )
            .contentShape(Rectangle())
            .simultaneousGesture(
                isMultiSelectMode ? nil :
                TapGesture(count: 1).onEnded {
                    guard !isCanvasGestureActive else { return }
                    tapCount += 1
                    if tapCount == 1 {
                        tapTimer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: false) { _ in
                            DispatchQueue.main.async {
                                if tapCount == 1 { onSingleTap() }
                                tapCount = 0; tapTimer = nil
                            }
                        }
                    } else if tapCount >= 2 {
                        tapTimer?.invalidate(); tapTimer = nil; tapCount = 0
                        onDoubleTap()
                    }
                }
            )
        }
    }
}
