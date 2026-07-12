//
//  LayersSheet.swift
//  Ponder
//

import SwiftUI
import SwiftData

struct LayerRowItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let icon: String
    let tint: Color
    var isHidden: Bool
    var opacity: Double
}

struct LayersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let allElements: [any LayerableElement]
    @ObservedObject var vm: LayersViewModel
    let onSelectElement: (UUID) -> Void

    @State private var orderedItems: [LayerRowItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if orderedItems.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .onAppear { rebuildOrderedItems() }
        .frame(minWidth: 320, minHeight: 400)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Layers")
                    .font(.title3.weight(.bold))
                Text("Top of list = front of canvas")
                    .font(.caption2)
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
        .padding(.bottom, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.3.layers.3d.slash")
                .font(.system(size: 38, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("Nothing on the canvas yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    private var content: some View {
        #if os(iOS)
        List {
            ForEach(orderedItems) { item in
                row(item)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove(perform: handleMove)
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
        #else
        // macOS: manual list with up/down arrows since edit mode is unavailable
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                    macRow(item: item, index: index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        #endif
    }

    private func row(_ item: LayerRowItem) -> some View {
        HStack(spacing: 12) {
            Button {
                onSelectElement(item.id)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    preview(for: item).opacity(item.isHidden ? 0.35 : 1)
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(item.isHidden ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            layerControls(for: item)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    #if os(macOS)
    private func macRow(item: LayerRowItem, index: Int) -> some View {
        HStack(spacing: 12) {
            Button {
                onSelectElement(item.id)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    preview(for: item).opacity(item.isHidden ? 0.35 : 1)
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(item.isHidden ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            layerControls(for: item)

            // Up / Down arrows for reorder on macOS
            Button {
                moveItem(at: index, by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(index == 0)

            Button {
                moveItem(at: index, by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(index == orderedItems.count - 1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func moveItem(at index: Int, by delta: Int) {
        let newIndex = index + delta
        guard newIndex >= 0, newIndex < orderedItems.count else { return }
        let item = orderedItems.remove(at: index)
        orderedItems.insert(item, at: newIndex)
        persistOrder()
    }
    #endif

    private func handleMove(from source: IndexSet, to destination: Int) {
        orderedItems.move(fromOffsets: source, toOffset: destination)
        persistOrder()
    }

    private func persistOrder() {
        let bottomToTop = Array(orderedItems.reversed())
        let elementsInOrder = bottomToTop.compactMap { item in
            allElements.first { $0.id == item.id }
        }
        vm.reorder(elementsInOrder, context: context)
    }

    private func rebuildOrderedItems() {
        let sorted = allElements.sorted { $0.zIndex > $1.zIndex }
        orderedItems = sorted.map { el in
            LayerRowItem(
                id: el.id,
                title: el.layerTitle,
                icon: el.layerIcon,
                tint: el.layerTint,
                isHidden: el.isLayerHidden,
                opacity: min(1, max(0.05, el.layerOpacity))
            )
        }
    }

    private func layerControls(for item: LayerRowItem) -> some View {
        HStack(spacing: 7) {
            Button {
                toggleVisibility(item.id)
            } label: {
                Image(systemName: item.isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.isHidden ? Color.secondary : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isHidden ? "Show \(item.title)" : "Hide \(item.title)")

            VStack(spacing: 1) {
                Text("\(Int((item.opacity * 100).rounded()))%")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Slider(
                    value: opacityBinding(for: item.id),
                    in: 0.05...1,
                    step: 0.05,
                    onEditingChanged: { editing in
                        if !editing { persistOpacity(item.id) }
                    }
                )
                .frame(width: 68)
                .disabled(item.isHidden)
                .opacity(item.isHidden ? 0.35 : 1)
                .accessibilityLabel("\(item.title) opacity")
            }
        }
    }

    private func toggleVisibility(_ id: UUID) {
        guard let index = orderedItems.firstIndex(where: { $0.id == id }),
              let element = allElements.first(where: { $0.id == id }) else { return }
        orderedItems[index].isHidden.toggle()
        element.isLayerHidden = orderedItems[index].isHidden
        element.updatedAt = Date()
        try? context.save()
    }

    private func opacityBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { orderedItems.first(where: { $0.id == id })?.opacity ?? 1 },
            set: { value in
                guard let index = orderedItems.firstIndex(where: { $0.id == id }),
                      let element = allElements.first(where: { $0.id == id }) else { return }
                let clamped = min(1, max(0.05, value))
                orderedItems[index].opacity = clamped
                element.layerOpacity = clamped
            }
        )
    }

    private func persistOpacity(_ id: UUID) {
        guard let element = allElements.first(where: { $0.id == id }) else { return }
        element.updatedAt = Date()
        try? context.save()
    }

    @ViewBuilder
    private func preview(for item: LayerRowItem) -> some View {
        if let element = allElements.first(where: { $0.id == item.id }) {
            LayerPreviewView(element: element)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(item.tint.opacity(0.15))
                Image(systemName: item.icon).foregroundStyle(item.tint)
            }
            .frame(width: 54, height: 46)
        }
    }
}
