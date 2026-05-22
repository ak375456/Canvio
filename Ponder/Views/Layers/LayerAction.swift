//
//  LayerActions.swift
//  Ponder
//

import SwiftUI

struct LayerActionsButtons: View {
    let onForward: () -> Void
    let onBackward: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onBackward) {
                Image(systemName: "square.2.layers.3d.bottom.filled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)

            Button(action: onForward) {
                Image(systemName: "square.2.layers.3d.top.filled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
    }
}
