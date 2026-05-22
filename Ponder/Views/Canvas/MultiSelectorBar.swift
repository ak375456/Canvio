//
//  MultiSelectBar.swift
//  Ponder
//

import SwiftUI

struct MultiSelectBar: View {
    let count: Int
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(count == 0 ? "Tap to select" : "\(count) selected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)

            Divider().frame(height: 20)

            Button(action: onDuplicate) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.square.on.square").font(.system(size: 14, weight: .medium))
                    Text("Duplicate").font(.subheadline.weight(.medium))
                }
                .foregroundStyle(count > 0 ? .blue : Color.secondary)
                .padding(.horizontal, 14).frame(height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(count == 0)

            Divider().frame(height: 20)

            Button(action: onDelete) {
                HStack(spacing: 6) {
                    Image(systemName: "trash").font(.system(size: 14, weight: .medium))
                    Text("Delete").font(.subheadline.weight(.medium))
                }
                .foregroundStyle(count > 0 ? .red : Color.secondary)
                .padding(.horizontal, 14).frame(height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(count == 0)

            Divider().frame(height: 20)

            Button(action: onDone) {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 14).frame(height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: 44)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        .fixedSize()
    }
}
