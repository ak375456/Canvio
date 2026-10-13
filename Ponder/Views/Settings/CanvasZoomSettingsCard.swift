import SwiftUI

struct CanvasZoomSettingsCard: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var pro = ProManager.shared
    let onUnlock: () -> Void

    private var configuration: CanvasZoomConfiguration {
        CanvasZoomConfiguration(expansion: settings.canvasZoomExpansion, isPro: pro.isPro)
    }

    private var rangeTitle: String {
        configuration.expansion == 1 ? "Standard" : "\(configuration.expansion.formatted())× range"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text("Extended zoom")
                            .font(.subheadline.weight(.semibold))
                        Text("PRO")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    Text("Zoom farther out for more canvas, or closer in for fine details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack {
                Text("Zoom range")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(rangeTitle)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(configuration.expansion > 1 ? Color.accentColor : Color.secondary)
            }

            Slider(
                value: Binding(
                    get: { configuration.expansion },
                    set: { value in
                        guard pro.isPro else { onUnlock(); return }
                        settings.canvasZoomExpansion = value
                    }
                ),
                in: CanvasZoomConfiguration.expansionRange,
                step: 0.25
            )
            .tint(.accentColor)
            .disabled(!pro.isPro)
            .accessibilityLabel("Canvas zoom range")
            .accessibilityValue(rangeTitle)
            .accessibilityHint("Move right to zoom farther out and in. Standard turns extended zoom off.")
            .overlay {
                if !pro.isPro {
                    Button(action: onUnlock) {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Unlock extended canvas zoom with Pro")
                }
            }

            HStack {
                Text("Standard")
                Spacer()
                Text("Extended")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                zoomLimitLabel("Zoom out", scale: configuration.minimumScale)
                Spacer(minLength: 0)
                zoomLimitLabel("Zoom in", scale: configuration.maximumScale)
            }
            .padding(10)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))

            if pro.isPro {
                HStack {
                    Text("Standard keeps the usual zoom limits.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Reset") { settings.canvasZoomExpansion = 1 }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .disabled(configuration.expansion == 1)
                        .accessibilityLabel("Reset canvas zoom range to standard")
                }
            } else {
                Button(action: onUnlock) {
                    Label("Unlock extended zoom", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func zoomLimitLabel(_ title: String, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int((scale * 100).rounded()))%")
                .font(.subheadline.monospacedDigit().weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}
