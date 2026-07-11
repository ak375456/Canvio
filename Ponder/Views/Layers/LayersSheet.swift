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
            preview(for: item)
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectElement(item.id)
            dismiss()
        }
    }

    #if os(macOS)
    private func macRow(item: LayerRowItem, index: Int) -> some View {
        HStack(spacing: 12) {
            preview(for: item)
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()

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
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectElement(item.id)
            dismiss()
        }
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
            LayerRowItem(id: el.id, title: el.layerTitle, icon: el.layerIcon, tint: el.layerTint)
        }
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
