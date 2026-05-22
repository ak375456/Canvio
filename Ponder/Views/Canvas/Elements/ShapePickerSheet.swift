//
//  ShapePickerSheet.swift
//  Ponder
//

import SwiftUI

struct ShapePickerSheet: View {
    let onPick: (ShapeKind) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Choose a Shape")
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
            .padding(.bottom, 20)

            Divider()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                ForEach(ShapeKind.allCases) { kind in
                    Button {
                        onPick(kind)
                        dismiss()
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: kind.icon)
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(.primary)
                            Text(kind.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.secondary.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)

            Spacer()
        }
    }
}
