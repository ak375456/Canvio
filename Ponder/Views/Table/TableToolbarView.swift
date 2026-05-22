//
//  TableToolbarView.swift
//  Ponder
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TableToolbarView: View {
    let table: TableElementModel
    let cells: [TableCellModel]
    let selectedCell: TableCellModel?
    @ObservedObject var vm: TableElementViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme

    let onDelete: () -> Void
    let onImportCSV: () -> Void
    let onExportCSV: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {

                // MARK: Structure
                group {
                    // Add row
                    toolButton(icon: "arrow.down.to.line", tooltip: "Add Row") {
                        vm.addRow(to: table, cells: cells, context: context)
                    }
                    toolButton(icon: "arrow.right.to.line", tooltip: "Add Col") {
                        vm.addColumn(to: table, cells: cells, context: context)
                    }
                    toolButton(icon: "arrow.up.to.line", tooltip: "Delete Row") {
                        vm.deleteLastRow(from: table, cells: cells, context: context)
                    }
                    toolButton(icon: "arrow.left.to.line", tooltip: "Delete Col") {
                        vm.deleteLastColumn(from: table, cells: cells, context: context)
                    }
                }

                divider

                // MARK: Alignment (only when cell selected)
                if let cell = selectedCell {
                    group {
                        alignButton(cell: cell, alignment: .leading,   icon: "text.alignleft")
                        alignButton(cell: cell, alignment: .center,    icon: "text.aligncenter")
                        alignButton(cell: cell, alignment: .trailing,  icon: "text.alignright")
                    }

                    divider

                    // MARK: Bold
                    Button {
                        vm.toggleBold(cell, context: context)
                    } label: {
                        Image(systemName: "bold")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(cell.isBold ? Color.accentColor : Color.primary.opacity(0.7))
                            .frame(width: 32, height: 28)
                    }
                    .buttonStyle(.plain)

                    divider

                    // MARK: Cell background color
                    cellColorPicker(cell: cell)

                    divider

                    // MARK: Merge / Split
                    if cell.colSpan > 1 {
                        toolButton(icon: "rectangle.split.2x1", tooltip: "Split") {
                            vm.splitCell(cell, cells: cells, context: context)
                        }
                    } else {
                        toolButton(icon: "rectangle.merge", tooltip: "Merge Right") {
                            vm.mergeRight(cell, table: table, cells: cells, context: context)
                        }
                    }

                    divider
                }

                // MARK: CSV
                group {
                    toolButton(icon: "square.and.arrow.down", tooltip: "Import CSV") {
                        onImportCSV()
                    }
                    toolButton(icon: "square.and.arrow.up", tooltip: "Export CSV") {
                        onExportCSV()
                    }
                }

                divider

                // MARK: Delete table
                toolButton(icon: "trash", tooltip: "Delete Table", tint: .red) {
                    onDelete()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .frame(height: 44)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func toolButton(icon: String, tooltip: String,
                            tint: Color = Color.primary.opacity(0.7),
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 28)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func alignButton(cell: TableCellModel, alignment: TextAlignment,
                             icon: String) -> some View {
        Button {
            vm.setCellAlignment(cell, alignment: alignment, context: context)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(cell.alignment == alignment
                                 ? Color.accentColor
                                 : Color.primary.opacity(0.7))
                .frame(width: 32, height: 28)
        }
        .buttonStyle(.plain)
    }

    private func cellColorPicker(cell: TableCellModel) -> some View {
        Menu {
            Button {
                vm.setCellBackground(cell, colorName: "clear", context: context)
            } label: {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Clear")
                }
            }
            ForEach(cellColors, id: \.name) { c in
                Button {
                    vm.setCellBackground(cell, colorName: c.name, context: context)
                } label: {
                    HStack {
                        Circle().fill(c.color).frame(width: 12, height: 12)
                        Text(c.name.capitalized)
                    }
                }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(cellColorValue(cell.backgroundColorName))
                    .frame(width: 18, height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
                    )
                if cell.backgroundColorName == "clear" {
                    Image(systemName: "paintbucket")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.6))
                }
            }
            .frame(width: 32, height: 28)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
    }

    private let cellColors: [(name: String, color: Color)] = [
        ("blue",   .blue.opacity(0.25)),
        ("green",  .green.opacity(0.25)),
        ("yellow", .yellow.opacity(0.35)),
        ("orange", .orange.opacity(0.25)),
        ("red",    .red.opacity(0.25)),
        ("purple", .purple.opacity(0.25)),
        ("gray",   .gray.opacity(0.2)),
    ]

    func cellColorValue(_ name: String) -> Color {
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
