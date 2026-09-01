//
//  LayersSheet.swift
//  Ponder
//

import SwiftUI
import SwiftData

struct LayerRowItem: Identifiable {
    let id: UUID
    let element: any LayerableElement
    let title: String
    let icon: String
    let tint: Color
    var isHidden: Bool
    var opacity: Double

    init(element: any LayerableElement) {
        id = element.id
        self.element = element
        title = element.layerTitle
        icon = element.layerIcon
        tint = element.layerTint
        isHidden = element.isLayerHidden
        opacity = min(1, max(0.05, element.layerOpacity))
    }
}

private struct LayerGroupRowItem: Identifiable {
    let group: CanvasElementGroupModel
    var members: [LayerRowItem]

    var id: UUID { group.id }
    var title: String { group.name }
}

private enum LayerStackIdentity: Hashable {
    case layer(UUID)
    case group(UUID)
}

private enum LayerStackItem: Identifiable {
    case layer(LayerRowItem)
    case group(LayerGroupRowItem)

    var id: LayerStackIdentity {
        switch self {
        case .layer(let item):
            return .layer(item.id)
        case .group(let group):
            return .group(group.id)
        }
    }
}

private enum LayerGroupVisibility: Equatable {
    case visible
    case hidden
    case mixed
}

private struct LayerVisibilityState: Equatable {
    let id: UUID
    let isHidden: Bool
}

private struct LayerOpacityState: Equatable {
    let id: UUID
    let opacity: Double
}

struct LayersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var canvasHistory: CanvasUndoManager

    let allElements: [any LayerableElement]
    let elementGroups: [CanvasElementGroupModel]
    @ObservedObject var vm: LayersViewModel
    let onSelectElement: (UUID) -> Void
    let onSelectGroup: (UUID) -> Void

    /// A compact hierarchy snapshot keeps ordering work out of the canvas view.
    /// Group child views are only built while their folder is expanded.
    @State private var orderedStackItems: [LayerStackItem] = []
    @State private var expandedGroupIDs: Set<UUID> = []
    @State private var opacityStartValues: [UUID: Double] = [:]
    @State private var groupOpacityStartStates: [UUID: [LayerOpacityState]] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if orderedStackItems.isEmpty {
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
                Text("Groups move as one layer · top of list = front")
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
            ForEach(orderedStackItems) { item in
                stackRow(item, topLevelIndex: nil)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove(perform: handleTopLevelMove)
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
        #else
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(Array(orderedStackItems.enumerated()), id: \.element.id) { index, item in
                    stackRow(item, topLevelIndex: index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        #endif
    }

    @ViewBuilder
    private func stackRow(_ item: LayerStackItem, topLevelIndex: Int?) -> some View {
        switch item {
        case .layer(let layer):
            standaloneLayerRow(layer, topLevelIndex: topLevelIndex)
        case .group(let group):
            groupRow(group, topLevelIndex: topLevelIndex)
        }
    }

    private func standaloneLayerRow(
        _ item: LayerRowItem,
        topLevelIndex: Int?
    ) -> some View {
        HStack(spacing: 12) {
            layerSelectionButton(item, showsPreview: true)
            layerControls(for: item)
            topLevelMoveControls(index: topLevelIndex)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, topLevelIndex == nil ? 4 : 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func groupRow(
        _ group: LayerGroupRowItem,
        topLevelIndex: Int?
    ) -> some View {
        let expanded = expandedGroupIDs.contains(group.id)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    onSelectGroup(group.id)
                    withAnimation(.easeInOut(duration: 0.16)) {
                        if expanded {
                            expandedGroupIDs.remove(group.id)
                        } else {
                            expandedGroupIDs.insert(group.id)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                            Image(systemName: "folder.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(width: 42, height: 38)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("\(group.members.count) layers")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.title), \(group.members.count) layers")
                .accessibilityHint(expanded ? "Collapse group" : "Expand group")

                groupVisibilityButton(group)
                topLevelMoveControls(index: topLevelIndex)
            }
            .padding(.horizontal, topLevelIndex == nil ? 10 : 12)
            .padding(.vertical, 8)

            groupOpacityControl(group)
                .padding(.leading, 48)
                .padding(.trailing, 12)
                .padding(.bottom, 8)

            if expanded {
                Divider()
                    .padding(.leading, 46)

                ForEach(Array(group.members.enumerated()), id: \.element.id) { index, member in
                    compactGroupMemberRow(
                        member,
                        groupID: group.id,
                        index: index,
                        count: group.members.count
                    )

                    if index < group.members.count - 1 {
                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(expanded ? 0.075 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func compactGroupMemberRow(
        _ item: LayerRowItem,
        groupID: UUID,
        index: Int,
        count: Int
    ) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 9) {
                Color.clear.frame(width: 22, height: 1)
                layerSelectionButton(item, showsPreview: false)

                Button {
                    toggleVisibility(item.id)
                } label: {
                    Image(systemName: item.isHidden ? "eye.slash" : "eye")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(item.isHidden ? Color.secondary : Color.accentColor)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isHidden ? "Show \(item.title)" : "Hide \(item.title)")

                memberMoveControls(groupID: groupID, index: index, count: count)

                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, height: 28)
                    .contentShape(Rectangle())
                    .draggable(groupMemberDragPayload(groupID: groupID, memberID: item.id))
            }

            compactOpacityControl(item)
                .padding(.leading, 63)
                .padding(.trailing, 2)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .opacity(item.isHidden ? 0.55 : 1)
        .dropDestination(for: String.self) { payloads, _ in
            guard let payload = payloads.first,
                  let movingID = groupMemberID(from: payload, expectedGroupID: groupID) else {
                return false
            }
            moveGroupMember(groupID: groupID, memberID: movingID, to: item.id)
            return true
        }
    }

    private func layerSelectionButton(
        _ item: LayerRowItem,
        showsPreview: Bool
    ) -> some View {
        Button {
            onSelectElement(item.id)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                if showsPreview {
                    LayerPreviewView(element: item.element)
                        .opacity(item.isHidden ? 0.35 : 1)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(item.tint.opacity(0.12))
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(item.tint)
                    }
                    .frame(width: 32, height: 30)
                }

                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(item.isHidden ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func topLevelMoveControls(index: Int?) -> some View {
        #if os(macOS)
        if let index {
            Button {
                moveTopLevelItem(at: index, by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(index == 0)

            Button {
                moveTopLevelItem(at: index, by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(index == orderedStackItems.count - 1)
        }
        #else
        EmptyView()
        #endif
    }

    private func memberMoveControls(groupID: UUID, index: Int, count: Int) -> some View {
        HStack(spacing: 1) {
            Button {
                moveGroupMember(groupID: groupID, at: index, by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .accessibilityLabel("Move layer forward in group")

            Button {
                moveGroupMember(groupID: groupID, at: index, by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(index == count - 1)
            .accessibilityLabel("Move layer backward in group")
        }
    }

    private func handleTopLevelMove(from source: IndexSet, to destination: Int) {
        orderedStackItems.move(fromOffsets: source, toOffset: destination)
        persistHierarchyOrder()
    }

    private func moveTopLevelItem(at index: Int, by delta: Int) {
        let newIndex = index + delta
        guard newIndex >= 0, newIndex < orderedStackItems.count else { return }
        let item = orderedStackItems.remove(at: index)
        orderedStackItems.insert(item, at: newIndex)
        persistHierarchyOrder()
    }

    private func moveGroupMember(groupID: UUID, at index: Int, by delta: Int) {
        guard let stackIndex = orderedStackItems.firstIndex(where: {
            if case .group(let group) = $0 { return group.id == groupID }
            return false
        }),
        case .group(var group) = orderedStackItems[stackIndex] else { return }

        let newIndex = index + delta
        guard index >= 0, index < group.members.count,
              newIndex >= 0, newIndex < group.members.count else { return }

        let member = group.members.remove(at: index)
        group.members.insert(member, at: newIndex)
        orderedStackItems[stackIndex] = .group(group)
        persistHierarchyOrder()
    }

    private func moveGroupMember(groupID: UUID, memberID: UUID, to targetID: UUID) {
        guard memberID != targetID,
              let stackIndex = orderedStackItems.firstIndex(where: {
                  if case .group(let group) = $0 { return group.id == groupID }
                  return false
              }),
              case .group(var group) = orderedStackItems[stackIndex],
              let sourceIndex = group.members.firstIndex(where: { $0.id == memberID }),
              let targetIndex = group.members.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        group.members.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        )
        orderedStackItems[stackIndex] = .group(group)
        persistHierarchyOrder()
    }

    private func groupMemberDragPayload(groupID: UUID, memberID: UUID) -> String {
        "ponder-group-member|\(groupID.uuidString)|\(memberID.uuidString)"
    }

    private func groupMemberID(from payload: String, expectedGroupID: UUID) -> UUID? {
        let components = payload.split(separator: "|", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == "ponder-group-member",
              UUID(uuidString: String(components[1])) == expectedGroupID else { return nil }
        return UUID(uuidString: String(components[2]))
    }

    /// Flattens folders only when an order is committed. This keeps group members
    /// contiguous in the canvas stack without adding a second persisted z-index.
    private func persistHierarchyOrder() {
        let topToBottom: [any LayerableElement] = orderedStackItems.flatMap { item in
            switch item {
            case .layer(let layer):
                [layer.element]
            case .group(let group):
                group.members.map(\.element)
            }
        }

        vm.reorder(
            Array(topToBottom.reversed()),
            context: context,
            undoManager: canvasHistory
        )
    }

    private func rebuildOrderedItems() {
        let sortedElements = allElements.sorted {
            if $0.zIndex == $1.zIndex { return $0.id.uuidString < $1.id.uuidString }
            return $0.zIndex > $1.zIndex
        }
        let groupsByID = Dictionary(uniqueKeysWithValues: elementGroups.map { ($0.id, $0) })

        var membersByGroup: [UUID: [LayerRowItem]] = [:]
        var standaloneItems: [UUID: LayerRowItem] = [:]

        for element in sortedElements {
            let item = LayerRowItem(element: element)
            if let groupID = element.groupID, groupsByID[groupID] != nil {
                membersByGroup[groupID, default: []].append(item)
            } else {
                standaloneItems[element.id] = item
            }
        }

        var emittedGroupIDs = Set<UUID>()
        var hierarchy: [LayerStackItem] = []

        for element in sortedElements {
            if let groupID = element.groupID,
               let group = groupsByID[groupID],
               let members = membersByGroup[groupID],
               emittedGroupIDs.insert(groupID).inserted {
                hierarchy.append(.group(LayerGroupRowItem(group: group, members: members)))
            } else if let item = standaloneItems[element.id] {
                hierarchy.append(.layer(item))
            }
        }

        orderedStackItems = hierarchy
        expandedGroupIDs.formIntersection(Set(membersByGroup.keys))
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
                        if editing {
                            if let element = layerItem(withID: item.id)?.element {
                                opacityStartValues[item.id] = element.layerOpacity
                            }
                        } else {
                            persistOpacity(item.id)
                        }
                    }
                )
                .frame(width: 68)
                .disabled(item.isHidden)
                .opacity(item.isHidden ? 0.35 : 1)
                .accessibilityLabel("\(item.title) opacity")
            }
        }
    }

    private func compactOpacityControl(_ item: LayerRowItem) -> some View {
        HStack(spacing: 7) {
            Text("Opacity")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            Slider(
                value: opacityBinding(for: item.id),
                in: 0.05...1,
                step: 0.05,
                onEditingChanged: { editing in
                    if editing {
                        opacityStartValues[item.id] = item.element.layerOpacity
                    } else {
                        persistOpacity(item.id)
                    }
                }
            )

            Text("\(Int((item.opacity * 100).rounded()))%")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
        .disabled(item.isHidden)
        .opacity(item.isHidden ? 0.35 : 1)
        .accessibilityLabel("\(item.title) opacity")
    }

    private func groupOpacityControl(_ group: LayerGroupRowItem) -> some View {
        let opacity = groupOpacity(group)

        return HStack(spacing: 8) {
            Text("Group opacity")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            Slider(
                value: groupOpacityBinding(for: group),
                in: 0.05...1,
                step: 0.05,
                onEditingChanged: { editing in
                    if editing {
                        groupOpacityStartStates[group.id] = group.members.map {
                            LayerOpacityState(id: $0.id, opacity: $0.element.layerOpacity)
                        }
                    } else {
                        persistGroupOpacity(group.id)
                    }
                }
            )

            Text("\(Int((opacity * 100).rounded()))%")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
        .accessibilityLabel("\(group.title) opacity")
    }

    private func groupOpacity(_ group: LayerGroupRowItem) -> Double {
        group.members.map(\.opacity).max() ?? 1
    }

    private func groupVisibilityButton(_ group: LayerGroupRowItem) -> some View {
        let visibility = groupVisibility(group)
        let hidesGroup = visibility != .hidden

        return Button {
            setVisibility(
                ids: group.members.map(\.id),
                hidden: hidesGroup,
                undoName: hidesGroup ? "Hide group" : "Show group"
            )
        } label: {
            Image(systemName: visibility == .hidden ? "eye.slash" : "eye")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(visibility == .visible ? Color.accentColor : Color.secondary)
                .opacity(visibility == .mixed ? 0.6 : 1)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hidesGroup ? "Hide \(group.title)" : "Show \(group.title)")
    }

    private func groupVisibility(_ group: LayerGroupRowItem) -> LayerGroupVisibility {
        let hiddenCount = group.members.lazy.filter(\.isHidden).count
        if hiddenCount == 0 { return .visible }
        if hiddenCount == group.members.count { return .hidden }
        return .mixed
    }

    private func toggleVisibility(_ id: UUID) {
        guard let item = layerItem(withID: id) else { return }
        let newValue = !item.isHidden
        setVisibility(
            ids: [id],
            hidden: newValue,
            undoName: newValue ? "Hide layer" : "Show layer"
        )
    }

    private func setVisibility(ids: [UUID], hidden: Bool, undoName: String) {
        let before = ids.compactMap { id -> LayerVisibilityState? in
            guard let item = layerItem(withID: id) else { return nil }
            return LayerVisibilityState(id: id, isHidden: item.element.isLayerHidden)
        }

        let after = before.map { LayerVisibilityState(id: $0.id, isHidden: hidden) }
        guard before != after else { return }

        applyVisibilityState(after)
        canvasHistory.recordChange(name: undoName, from: before, to: after) { state in
            applyVisibilityState(state)
        }
    }

    private func applyVisibilityState(_ state: [LayerVisibilityState]) {
        var changed: [any LayerableElement] = []

        for item in state {
            guard let element = CanvasElementHistoryLookup.element(
                withID: item.id,
                context: context
            ) else { continue }
            guard element.isLayerHidden != item.isHidden else {
                updateLayerItem(item.id) { $0.isHidden = item.isHidden }
                continue
            }
            element.isLayerHidden = item.isHidden
            element.updatedAt = Date()
            changed.append(element)
            updateLayerItem(item.id) { $0.isHidden = item.isHidden }
        }

        guard !changed.isEmpty else { return }
        try? context.save()
        Task {
            for element in changed {
                await CanvasElementSyncRouter.upsert(element)
            }
        }
    }

    private func opacityBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { layerItem(withID: id)?.opacity ?? 1 },
            set: { value in
                guard let item = layerItem(withID: id) else { return }
                let clamped = min(1, max(0.05, value))
                item.element.layerOpacity = clamped
                updateLayerItem(id) { $0.opacity = clamped }
            }
        )
    }

    private func groupOpacityBinding(for group: LayerGroupRowItem) -> Binding<Double> {
        Binding(
            get: { groupOpacity(group) },
            set: { value in
                let baseline = groupOpacityStartStates[group.id] ?? group.members.map {
                    LayerOpacityState(id: $0.id, opacity: $0.element.layerOpacity)
                }
                let baselineOpacity = baseline.map(\.opacity).max() ?? 1
                let clamped = min(1, max(0.05, value))
                let ratio = clamped / max(0.05, baselineOpacity)

                for state in baseline {
                    guard let item = layerItem(withID: state.id) else { continue }
                    let next = min(1, max(0.05, state.opacity * ratio))
                    item.element.layerOpacity = next
                    updateLayerItem(state.id) { $0.opacity = next }
                }
            }
        )
    }

    private func persistGroupOpacity(_ groupID: UUID) {
        guard let before = groupOpacityStartStates.removeValue(forKey: groupID) else { return }
        let after = before.compactMap { state -> LayerOpacityState? in
            guard let item = layerItem(withID: state.id) else { return nil }
            return LayerOpacityState(id: state.id, opacity: item.element.layerOpacity)
        }
        guard before != after else { return }

        let beforeByID = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.opacity) })
        let changed = after.compactMap { state -> (any LayerableElement)? in
            guard beforeByID[state.id] != state.opacity else { return nil }
            return layerItem(withID: state.id)?.element
        }
        guard !changed.isEmpty else { return }

        let now = Date()
        for element in changed {
            element.updatedAt = now
        }
        try? context.save()
        Task {
            for element in changed {
                await CanvasElementSyncRouter.upsert(element)
            }
        }

        canvasHistory.recordChange(
            name: "Change group opacity",
            from: before,
            to: after,
            coalescingKey: "group-opacity-\(groupID)"
        ) { state in
            applyOpacityState(state)
        }
    }

    private func applyOpacityState(_ state: [LayerOpacityState]) {
        var changed: [any LayerableElement] = []
        let now = Date()

        for item in state {
            guard let element = CanvasElementHistoryLookup.element(
                withID: item.id,
                context: context
            ) else { continue }
            updateLayerItem(item.id) { $0.opacity = item.opacity }
            guard element.layerOpacity != item.opacity else { continue }
            element.layerOpacity = item.opacity
            element.updatedAt = now
            changed.append(element)
        }

        guard !changed.isEmpty else { return }
        try? context.save()
        Task {
            for element in changed {
                await CanvasElementSyncRouter.upsert(element)
            }
        }
    }

    private func persistOpacity(_ id: UUID) {
        guard let item = layerItem(withID: id) else { return }
        let element = item.element
        let oldValue = opacityStartValues.removeValue(forKey: id) ?? element.layerOpacity
        let newValue = element.layerOpacity
        element.updatedAt = Date()
        try? context.save()
        Task { await CanvasElementSyncRouter.upsert(element) }
        canvasHistory.recordChange(
            name: "Change layer opacity",
            from: oldValue,
            to: newValue,
            coalescingKey: "layer-opacity-\(id)"
        ) { value in
            guard let current = CanvasElementHistoryLookup.element(
                withID: id,
                context: context
            ) else { return }
            current.layerOpacity = value
            current.updatedAt = Date()
            try? context.save()
            updateLayerItem(id) { $0.opacity = value }
            Task { await CanvasElementSyncRouter.upsert(current) }
        }
    }

    private func layerItem(withID id: UUID) -> LayerRowItem? {
        for item in orderedStackItems {
            switch item {
            case .layer(let layer) where layer.id == id:
                return layer
            case .group(let group):
                if let member = group.members.first(where: { $0.id == id }) {
                    return member
                }
            default:
                continue
            }
        }
        return nil
    }

    private func updateLayerItem(
        _ id: UUID,
        mutate: (inout LayerRowItem) -> Void
    ) {
        for index in orderedStackItems.indices {
            switch orderedStackItems[index] {
            case .layer(var layer) where layer.id == id:
                mutate(&layer)
                orderedStackItems[index] = .layer(layer)
                return
            case .group(var group):
                guard let memberIndex = group.members.firstIndex(where: { $0.id == id }) else {
                    continue
                }
                mutate(&group.members[memberIndex])
                orderedStackItems[index] = .group(group)
                return
            default:
                continue
            }
        }
    }
}
