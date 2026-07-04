//
//  CanvasPagesPanel.swift
//  Ponder
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct CanvasPagesPanel: View {
    let pages: [CanvasPageModel]
    let activePageID: UUID?
    let viewportSize: CGSize
    let isAddLocked: Bool
    @Binding var isExpanded: Bool
    let onSelect: (CanvasPageModel) -> Void
    let onAdd: () -> Void
    let onRename: (CanvasPageModel) -> Void
    let onDuplicate: (CanvasPageModel) -> Void
    let onDelete: (CanvasPageModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                expandedPanel
            } else {
                collapsedButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 12)
        .padding(.top, 12)
        .zIndex(86)
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(pages) { page in
                        row(for: page)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: max(160, min(330, viewportSize.height - 180)))
        }
        .frame(width: min(230, max(184, viewportSize.width - 28)))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Pages")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
            Spacer()
            Button(action: onAdd) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))

                    if isAddLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Color.accentColor, in: Circle())
                            .offset(x: 5, y: 5)
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAddLocked ? "Unlock more pages" : "Add page")

            Button {
                withAnimation(.spring(duration: 0.24)) { isExpanded = false }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse pages")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
    }

    private var collapsedButton: some View {
        Button {
            withAnimation(.spring(duration: 0.24)) { isExpanded = true }
        } label: {
            Label("Pages", systemImage: "rectangle.on.rectangle.angled")
                .font(.caption.weight(.bold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func row(for page: CanvasPageModel) -> some View {
        let isSelected = page.id == activePageID

        return Button {
            onSelect(page)
        } label: {
            HStack(spacing: 10) {
                thumbnail(for: page, isSelected: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(page.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(Int(page.width)) x \(Int(page.height))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.11) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onRename(page) } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button { onDuplicate(page) } label: {
                Label(isAddLocked ? "New Same Size (Pro)" : "New Same Size",
                      systemImage: "plus.square.on.square")
            }

            Button(role: .destructive) { onDelete(page) } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(pages.count <= 1)
        }
    }

    private func thumbnail(for page: CanvasPageModel, isSelected: Bool) -> some View {
        let ratio = max(0.35, min(1.8, CGFloat(page.width / max(page.height, 1))))
        let maxW: CGFloat = 42
        let maxH: CGFloat = 38
        let width = ratio >= 1 ? maxW : maxH * ratio
        let height = ratio >= 1 ? maxW / ratio : maxH

        return ZStack {
            thumbnailContent(for: page)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.16),
                            lineWidth: isSelected ? 1.6 : 1
                        )
                )
        }
        .frame(width: maxW, height: maxH)
    }

    @ViewBuilder
    private func thumbnailContent(for page: CanvasPageModel) -> some View {
        if let data = page.thumbnailData, let image = thumbnailImage(from: data) {
            image
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                pageFillColor
                Image(systemName: "doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.65))
            }
        }
    }

    private func thumbnailImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}

private var pageFillColor: Color {
    #if os(iOS)
    return Color(uiColor: .secondarySystemBackground)
    #elseif os(macOS)
    return Color(nsColor: .windowBackgroundColor)
    #else
    return Color.white
    #endif
}
