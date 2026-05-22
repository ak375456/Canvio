//
//  TableSizePickerSheet.swift
//  Ponder
//

import SwiftUI

struct TableSizePickerSheet: View {
    let onConfirm: (Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var hoveredRow = 0
    @State private var hoveredCol = 0
    @State private var selectedRows = 3
    @State private var selectedCols = 3

    private let maxGrid = 10

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 28) {
                sizeLabel
                gridPicker
                manualEntry
            }
            .padding(24)
            Divider()
            confirmButton
        }
    }

    private var header: some View {
        HStack {
            Text("New Table")
                .font(.title3.weight(.bold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var sizeLabel: some View {
        Text("\(selectedRows) × \(selectedCols)")
            .font(.system(size: 36, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .contentTransition(.numericText())
            .animation(.spring(duration: 0.2), value: selectedRows)
            .animation(.spring(duration: 0.2), value: selectedCols)
    }

    private var gridPicker: some View {
        VStack(spacing: 3) {
            ForEach(1...maxGrid, id: \.self) { r in
                HStack(spacing: 3) {
                    ForEach(1...maxGrid, id: \.self) { c in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(r <= selectedRows && c <= selectedCols
                                  ? Color.accentColor
                                  : Color.secondary.opacity(0.15))
                            .frame(width: 26, height: 22)
                            .onTapGesture {
                                withAnimation(.spring(duration: 0.15)) {
                                    selectedRows = r
                                    selectedCols = c
                                }
                            }
                    }
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private var manualEntry: some View {
        HStack(spacing: 20) {
            stepperField(label: "Rows", value: $selectedRows)
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 40)
            stepperField(label: "Cols", value: $selectedCols)
        }
    }

    private func stepperField(label: String, value: Binding<Int>) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            HStack(spacing: 12) {
                Button {
                    if value.wrappedValue > 1 {
                        withAnimation(.spring(duration: 0.15)) { value.wrappedValue -= 1 }
                    }
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Text("\(value.wrappedValue)")
                    .font(.title3.weight(.semibold))
                    .frame(width: 32)
                    .contentTransition(.numericText())

                Button {
                    if value.wrappedValue < 20 {
                        withAnimation(.spring(duration: 0.15)) { value.wrappedValue += 1 }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var confirmButton: some View {
        Button {
            onConfirm(selectedRows, selectedCols)
            dismiss()
        } label: {
            Text("Create \(selectedRows) × \(selectedCols) Table")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}
