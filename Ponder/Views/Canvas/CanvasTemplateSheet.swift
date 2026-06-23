import SwiftUI

struct CanvasTemplateSheet: View {
    let templates: [CanvasTemplate]
    var lockedTemplateIDs: Set<String> = []
    let onSelect: (CanvasTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: CanvasTemplateCategory?

    private var filteredTemplates: [CanvasTemplate] {
        guard let selectedCategory else { return templates }
        return templates.filter { $0.category == selectedCategory }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 260), spacing: 12)]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryFilter

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredTemplates) { template in
                            let isLocked = lockedTemplateIDs.contains(template.id)
                            Button {
                                dismiss()
                                onSelect(template)
                            } label: {
                                CanvasTemplateCard(template: template, isLocked: isLocked)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isLocked ? "\(template.title), Pro required" : template.title)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Templates")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }

                ForEach(CanvasTemplateCategory.allCases) { category in
                    categoryButton(title: category.title, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.regularMaterial)
    }

    private func categoryButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

private struct CanvasTemplateCard: View {
    let template: CanvasTemplate
    let isLocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CanvasTemplatePreview(template: template)
                .frame(height: 120)
                .overlay {
                    if isLocked {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.42))
                        Image(systemName: "lock.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.72), in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.7))
                    }
                }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: template.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(template.tint)
                    .frame(width: 32, height: 32)
                    .background(template.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(template.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(template.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 24)
                        .background(Color.black.opacity(0.76), in: Capsule())
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

private struct CanvasTemplatePreview: View {
    let template: CanvasTemplate

    var body: some View {
        GeometryReader { geo in
            let scale = min(
                geo.size.width / max(template.size.width, 1),
                geo.size.height / max(template.size.height, 1)
            )
            let previewSize = CGSize(
                width: template.size.width * scale,
                height: template.size.height * scale
            )
            let origin = CGPoint(
                x: (geo.size.width - previewSize.width) / 2,
                y: (geo.size.height - previewSize.height) / 2
            )

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )

                ForEach(Array(template.items.enumerated()), id: \.offset) { _, item in
                    previewItem(item)
                        .position(previewPosition(for: item, scale: scale, origin: origin))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func previewItem(_ item: CanvasTemplateItem) -> some View {
        switch item {
        case .text(let spec):
            Capsule()
                .fill(item.previewTint.opacity(spec.isBold ? 0.42 : 0.24))
                .frame(width: min(max(CGFloat(spec.text.count) * 4, 34), 98), height: spec.isBold ? 12 : 8)

        case .sticky(let spec):
            RoundedRectangle(cornerRadius: 4)
                .fill(stickyPreviewColor(spec.colorName))
                .frame(width: 34, height: 26)

        case .todo:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 3) {
                        Circle().stroke(item.previewTint, lineWidth: 1.4).frame(width: 6, height: 6)
                        Capsule().fill(item.previewTint.opacity(0.38)).frame(width: 24, height: 4)
                    }
                }
            }
            .padding(5)
            .background(item.previewTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

        case .shape(let spec):
            RoundedRectangle(cornerRadius: spec.kind == .circle ? 18 : 4)
                .fill(item.previewTint.opacity(spec.hasFill ? 0.24 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: spec.kind == .circle ? 18 : 4)
                        .stroke(item.previewTint.opacity(0.62), lineWidth: 1.6)
                )
                .frame(width: spec.kind == .line ? 44 : 34, height: spec.kind == .line ? 4 : 26)
                .rotationEffect(.degrees(spec.rotation))

        case .table:
            Image(systemName: item.previewIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(item.previewTint)
                .frame(width: 38, height: 30)
                .background(item.previewTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private func previewPosition(
        for item: CanvasTemplateItem,
        scale: CGFloat,
        origin: CGPoint
    ) -> CGPoint {
        let center: CGPoint
        switch item {
        case .text(let spec):   center = spec.center
        case .sticky(let spec): center = spec.center
        case .todo(let spec):   center = spec.center
        case .shape(let spec):  center = spec.center
        case .table(let spec):  center = spec.center
        }
        return CGPoint(x: origin.x + center.x * scale, y: origin.y + center.y * scale)
    }

    private func stickyPreviewColor(_ name: String) -> Color {
        switch name {
        case "blue":   return .blue.opacity(0.36)
        case "green":  return .green.opacity(0.36)
        case "pink":   return .pink.opacity(0.34)
        case "orange": return .orange.opacity(0.36)
        default:       return .yellow.opacity(0.46)
        }
    }
}
