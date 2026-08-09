//
//  ShapePickerSheet.swift
//  Ponder
//

import SwiftUI

struct ShapePickerSheet: View {
    let onPick: (ShapePreset) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose a Shape")
                        .font(.title3.weight(.bold))
                    Text("Basic shapes, lines, flowcharts, and callouts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            .padding(.bottom, 20)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(ShapeCategory.allCases) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.rawValue.uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 96), spacing: 10)],
                                spacing: 10
                            ) {
                                ForEach(ShapePreset.presets(in: category)) { preset in
                                    shapeButton(preset)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
    }

    private func shapeButton(_ preset: ShapePreset) -> some View {
        Button {
            onPick(preset)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(.primary)
                    .frame(height: 30)
                Text(preset.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 32, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color.secondary.opacity(0.11))
            )
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(preset.title)")
    }
}
