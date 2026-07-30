//
//  TodoTaskDetailSheet.swift
//  Ponder
//

import SwiftUI
import SwiftData

struct TodoTaskDetailSheet: View {
    @EnvironmentObject private var canvasHistory: CanvasUndoManager
    @Bindable var task: TodoTaskModel
    let allTasks: [TodoTaskModel]
    let context: ModelContext
    let onClose: () -> Void

    @State private var tagInput: String = ""
    @State private var newSubtaskTitle: String = ""
    @State private var initialTaskState: TodoTaskHistoryState?
    @FocusState private var titleFocused: Bool

    private var hasDueDate: Binding<Bool> {
        Binding(
            get: { task.dueDate != nil },
            set: { newValue in
                if newValue {
                    task.dueDate = task.dueDate ?? Date()
                } else {
                    task.dueDate = nil
                }
                task.updatedAt = Date()
                try? context.save()
                Task { await TodoSyncService.shared.upsertTask(task) }
            }
        )
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { task.dueDate ?? Date() },
            set: {
                task.dueDate = $0
                task.updatedAt = Date()
                try? context.save()
                Task { await TodoSyncService.shared.upsertTask(task) }
            }
        )
    }

    private var subtasks: [TodoTaskModel] {
        allTasks
            .filter { $0.parentTaskID == task.id }
            .sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    titleField
                    prioritySection
                    dueDateSection
                    tagsSection
                    subtasksSection
                }
                .padding(24)
            }
        }
        .onAppear {
            initialTaskState = TodoTaskHistoryState(task)
        }
        .onDisappear {
            if let initialTaskState {
                recordTodoTaskChange(
                    name: "Edit todo details",
                    task: task,
                    from: initialTaskState,
                    context: context,
                    undoManager: canvasHistory
                )
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Text("Task")
                .font(.title3.weight(.bold))
            Spacer()
            Button {
                try? context.save()
                onClose()
            } label: {
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
    }

    // MARK: - Title
    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("TASK")
            TextField("Task title", text: $task.title, axis: .vertical)
                .font(.body)
                .focused($titleFocused)
                .lineLimit(1...4)
                .onChange(of: task.title) { _, _ in
                    task.updatedAt = Date()
                    try? context.save()
                    Task { await TodoSyncService.shared.upsertTask(task) }
                }
            Divider()
        }
    }

    // MARK: - Priority
    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PRIORITY")
            HStack(spacing: 8) {
                ForEach(TodoPriority.allCases) { p in
                    Button {
                        task.priority = p
                        task.updatedAt = Date()
                        try? context.save()
                        Task { await TodoSyncService.shared.upsertTask(task) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(p.color).frame(width: 8, height: 8)
                            Text(p.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(task.priority == p ? .white : .primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(task.priority == p ? Color.accentColor : Color.secondary.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Due date
    private var dueDateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("DUE DATE")
                Spacer()
                Toggle("", isOn: hasDueDate.animation())
                    .labelsHidden()
            }
            if task.dueDate != nil {
                DatePicker(
                    "",
                    selection: dueDateBinding,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
            }
        }
    }

    // MARK: - Tags
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TAGS")
            if !task.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(task.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.caption.weight(.medium))
                            Button {
                                task.tags.removeAll { $0 == tag }
                                task.updatedAt = Date()
                                try? context.save()
                                Task { await TodoSyncService.shared.upsertTask(task) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Add a tag", text: $tagInput)
                    .font(.subheadline)
                    .onSubmit { addTag() }
                Button("Add") { addTag() }
                    .font(.caption.weight(.semibold))
                    .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Divider()
        }
    }

    private func addTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !task.tags.contains(trimmed) else { return }
        task.tags.append(trimmed)
        task.updatedAt = Date()
        try? context.save()
        Task { await TodoSyncService.shared.upsertTask(task) }
        tagInput = ""
    }

    // MARK: - Subtasks
    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SUBTASKS")
            ForEach(subtasks) { sub in
                HStack(spacing: 10) {
                    Button {
                        let oldState = TodoTaskHistoryState(sub)
                        sub.isCompleted.toggle()
                        sub.updatedAt = Date()
                        try? context.save()
                        Task { await TodoSyncService.shared.upsertTask(sub) }
                        recordTodoTaskChange(
                            name: "Toggle subtask",
                            task: sub,
                            from: oldState,
                            context: context,
                            undoManager: canvasHistory
                        )
                    } label: {
                        Image(systemName: sub.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(sub.isCompleted ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)

                    Text(sub.title.isEmpty ? "Untitled" : sub.title)
                        .font(.subheadline)
                        .strikethrough(sub.isCompleted)
                        .foregroundStyle(sub.isCompleted ? .secondary : .primary)

                    Spacer()

                    Button {
                        deleteSubtask(sub)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                TextField("New subtask", text: $newSubtaskTitle)
                    .font(.subheadline)
                    .onSubmit { addSubtask() }
                Button {
                    addSubtask()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let sub = TodoTaskModel(
            listID: task.listID,
            parentTaskID: task.id,
            title: trimmed,
            order: subtasks.count
        )
        context.insert(sub)
        newSubtaskTitle = ""
        try? context.save()
        Task { await TodoSyncService.shared.upsertTask(sub) }
        let snapshot = TodoTaskHistoryState(sub)
        canvasHistory.push(CanvasAction(
            name: "Add subtask",
            undo: {
                guard let values = try? context.fetch(FetchDescriptor<TodoTaskModel>()),
                      let current = values.first(where: { $0.id == snapshot.id }) else { return }
                context.delete(current)
                try? context.save()
                Task { await TodoSyncService.shared.deleteTask(current) }
            },
            redo: {
                let restored = snapshot.makeModel()
                context.insert(restored)
                try? context.save()
                Task { await TodoSyncService.shared.upsertTask(restored) }
            }
        ))
    }

    private func deleteSubtask(_ subtask: TodoTaskModel) {
        let snapshot = TodoTaskHistoryState(subtask)
        Task { await TodoSyncService.shared.deleteTask(subtask) }
        context.delete(subtask)
        try? context.save()
        canvasHistory.push(CanvasAction(
            name: "Delete subtask",
            undo: {
                let restored = snapshot.makeModel()
                context.insert(restored)
                try? context.save()
                Task { await TodoSyncService.shared.upsertTask(restored) }
            },
            redo: {
                guard let values = try? context.fetch(FetchDescriptor<TodoTaskModel>()),
                      let current = values.first(where: { $0.id == snapshot.id }) else { return }
                context.delete(current)
                try? context.save()
                Task { await TodoSyncService.shared.deleteTask(current) }
            }
        ))
    }

    // MARK: - Helpers
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(1)
    }
}

// MARK: - Simple flow layout for tag wrapping
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(in: proposal.width ?? 0, subviews: subviews)
        return CGSize(width: proposal.width ?? result.width, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (frames: [CGRect], width: CGFloat, height: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (frames, width, y + rowHeight)
    }
}
