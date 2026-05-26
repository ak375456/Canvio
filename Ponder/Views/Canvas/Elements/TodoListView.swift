//
//  TodoListView.swift
//  Ponder
//

import SwiftUI
import SwiftData

struct TodoListView: View {
    @Environment(\.modelContext) private var context
    let list: TodoListModel
    let allTasks: [TodoTaskModel]
    let canvasScale: CGFloat
    let canvasBoundary: CGSize
    @ObservedObject var vm: TodoListViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect: Bool = false
    var onExternalTap: (() -> Void)? = nil
    var isCanvasGestureActive: Bool = false

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool   = false
    @State private var resizeDelta: CGSize = .zero
    @State private var localTitle: String = ""
    @State private var openTaskID: UUID? = nil
    @FocusState private var titleFocused: Bool

    private var isSelected: Bool { vm.editingID == list.id }
    private var accent: Color { colorFor(list.colorName) }
    private var currentSize: CGSize {
        CGSize(width: max(220, list.width + resizeDelta.width),
               height: max(180, list.height + resizeDelta.height))
    }
    private var topLevelTasks: [TodoTaskModel] {
        allTasks.filter { $0.listID == list.id && $0.parentTaskID == nil }
            .sorted { $0.order < $1.order }
    }
    private var completedCount: Int { topLevelTasks.filter { $0.isCompleted }.count }
    private let handleSize: CGFloat = 26

    var body: some View {
        ZStack {
            cardBody
            selectionRing
            if isSelected && !isMultiSelectMode { cornerHandles }
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .position(x: list.x + dragOffset.width, y: list.y + dragOffset.height)
        .gesture(canMove ? moveDragGesture : nil)
        .onAppear { localTitle = list.title }
        .sheet(item: openTaskBinding) { task in
            TodoTaskDetailSheet(task: task, allTasks: allTasks, context: context) { openTaskID = nil }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isMultiSelectMode {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isSelectedInMultiSelect ? Color.blue : Color.white.opacity(0.3),
                    lineWidth: isSelectedInMultiSelect ? 2.5 : 1
                )
                .frame(width: currentSize.width, height: currentSize.height)
                .overlay(alignment: .topTrailing) {
                    if isSelectedInMultiSelect {
                        ZStack {
                            Circle().fill(Color.blue).frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        }.offset(x: 8, y: -8)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isSelectedInMultiSelect)
        }
    }

    private var openTaskBinding: Binding<TodoTaskModel?> {
        Binding(get: { allTasks.first { $0.id == openTaskID } },
                set: { openTaskID = $0?.id })
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            Divider()
            tasksList
            Divider()
            addTaskRow
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(
            isSelected && !isMultiSelectMode
                ? accent.opacity(0.6)
                : Color.secondary.opacity(0.15),
            lineWidth: isSelected && !isMultiSelectMode ? 2 : 1))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
        .onTapGesture {
            // Only select on tap, not after a drag
            guard !isMultiSelectMode, !isDragging, !isCanvasGestureActive else { return }
            if !isSelected { onExternalTap?(); vm.editingID = list.id }
        }
    }

    private var cardHeader: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4).fill(accent).frame(width: 4, height: 22)
            if isSelected && !isMultiSelectMode {
                TextField("List title", text: $localTitle)
                    .font(.headline.weight(.semibold))
                    .focused($titleFocused)
                    .onSubmit {
                        vm.updateTitle(list: list, title: localTitle, context: context)
                        titleFocused = false
                    }
                    .onChange(of: titleFocused) { _, f in
                        if !f { vm.updateTitle(list: list, title: localTitle, context: context) }
                    }
            } else {
                Text(list.title.isEmpty ? "Todo" : list.title)
                    .font(.headline.weight(.semibold))
            }
            Spacer()
            Text("\(completedCount)/\(topLevelTasks.count)")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
            if isSelected && !isMultiSelectMode {
                Menu {
                    ForEach(["blue","purple","green","orange","pink","red","teal"], id: \.self) { name in
                        Button {
                            vm.updateColor(list: list, colorName: name, context: context)
                        } label: {
                            HStack {
                                Circle().fill(colorFor(name)).frame(width: 12, height: 12)
                                Text(name.capitalized)
                            }
                        }
                    }
                } label: { Circle().fill(accent).frame(width: 14, height: 14) }
            }
        }.padding(12)
    }

    private func colorFor(_ name: String) -> Color {
        switch name {
        case "blue":   return .blue;   case "purple": return .purple
        case "green":  return .green;  case "orange": return .orange
        case "pink":   return .pink;   case "red":    return .red
        case "teal":   return .teal;   default:       return .blue
        }
    }

    private var tasksList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sortedTasks) { task in
                    taskRowWithSubtasks(task)
                    Divider().padding(.leading, 42)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func taskRowWithSubtasks(_ task: TodoTaskModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Task row with swipe-to-delete on iOS
            TodoTaskRow(
                task: task,
                accentColor: accent,
                vm: vm,
                isListSelected: isSelected && !isMultiSelectMode,
                onOpenDetail: { openTaskID = task.id },
                onDelete: {
                    vm.deleteTask(
                        task,
                        subtasks: allTasks.filter { $0.parentTaskID == task.id },
                        context: context
                    )
                }
            )
            .padding(.horizontal, 12)

            // Subtasks
            let subs = allTasks.filter { $0.parentTaskID == task.id }
                .sorted { $0.order < $1.order }
            if !subs.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(subs) { sub in
                        HStack(spacing: 8) {
                            Button {
                                sub.isCompleted.toggle()
                                sub.updatedAt = Date()
                                try? context.save()
                                Task { await TodoSyncService.shared.upsertTask(sub) }
                            } label: {
                                Image(systemName: sub.isCompleted
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(sub.isCompleted
                                                     ? accent
                                                     : Color.secondary.opacity(0.5))
                            }.buttonStyle(.plain)

                            Text(sub.title.isEmpty ? "Untitled" : sub.title)
                                .font(.system(size: 12))
                                .strikethrough(sub.isCompleted, color: .secondary)
                                .foregroundStyle(sub.isCompleted
                                                 ? Color.secondary
                                                 : Color.primary.opacity(0.85))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }.padding(.trailing, 12)
                    }
                }
                .padding(.leading, 42).padding(.bottom, 6)
            }
        }
    }

    private var sortedTasks: [TodoTaskModel] {
        topLevelTasks.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            if a.priority.sortOrder != b.priority.sortOrder {
                return a.priority.sortOrder < b.priority.sortOrder
            }
            return a.order < b.order
        }
    }

    private var addTaskRow: some View {
        Button {
            guard !isCanvasGestureActive else { return }
            if !isSelected { vm.editingID = list.id }
            let t = vm.addTask(to: list, existingCount: topLevelTasks.count, context: context)
            openTaskID = t.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16)).foregroundStyle(accent)
                Text("Add task")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var cornerHandles: some View {
        ZStack {
            Button {
                vm.delete(
                    list: list,
                    tasks: allTasks.filter { $0.listID == list.id },
                    context: context
                )
            } label: {
                handleCircle(icon: "trash", color: .red)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .offset(x: -handleSize / 2, y: -handleSize / 2)

            handleCircle(icon: "arrow.up.left.and.arrow.down.right", color: .green)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: handleSize / 2, y: handleSize / 2)
                .gesture(
                    DragGesture()
                        .onChanged { resizeDelta = $0.translation }
                        .onEnded { value in
                            let t = value.translation; resizeDelta = .zero
                            vm.updateSize(
                                list: list,
                                width:  list.width  + t.width,
                                height: list.height + t.height,
                                context: context
                            )
                        }
                )
        }
    }

    private func handleCircle(icon: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color).frame(width: handleSize, height: handleSize)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        }
    }

    // MARK: - Move drag gesture
    // Enabled only after the list is selected.
    // minimumDistance: 8 prevents accidental drags on tap.
    // isDragging flag stops the tap handler firing after drag ends.

    private var moveDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard canMove else {
                    isDragging = false
                    dragOffset = .zero
                    return
                }
                isDragging   = true
                dragOffset   = value.translation
                // Dismiss keyboard if open while dragging
                if titleFocused { titleFocused = false }
            }
            .onEnded { value in
                guard canMove else {
                    dragOffset = .zero
                    isDragging = false
                    return
                }
                let t      = value.translation
                dragOffset = .zero
                vm.updatePosition(
                    list: list, translation: t,
                    scale: canvasScale, boundary: canvasBoundary,
                    context: context
                )
                // Short delay so the tap handler sees isDragging=true and skips
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isDragging = false
                }
            }
    }

    private var canMove: Bool {
        isSelected && !isMultiSelectMode && !isCanvasGestureActive
    }
}
