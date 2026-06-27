//
//  TodoTaskRow.swift
//  Ponder
//

import SwiftUI
import SwiftData

struct TodoTaskRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var task: TodoTaskModel
    let accentColor: Color
    @ObservedObject var vm: TodoListViewModel
    /// True when the parent todo card is selected — shows inline delete button
    let isListSelected: Bool
    let onOpenDetail: () -> Void
    let onDelete: () -> Void

    @FocusState private var isFocused: Bool
    @State private var remoteSyncTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Checkbox
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    vm.toggleTask(task, context: context)
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(
                            task.isCompleted ? accentColor : Color.secondary.opacity(0.4),
                            lineWidth: 1.5
                        )
                        .frame(width: 20, height: 20)
                    if task.isCompleted {
                        Circle().fill(accentColor).frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            // Title + meta
            VStack(alignment: .leading, spacing: 4) {
                TextField("New task", text: $task.title, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
                    .strikethrough(task.isCompleted, color: .secondary)
                    .focused($isFocused)
                    .onChange(of: task.title) { _, _ in
                        task.updatedAt = Date()
                        try? context.save()
                        scheduleRemoteSync()
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { flushRemoteSync() }
                    }

                if hasMeta {
                    HStack(spacing: 6) {
                        if task.priority != .none {
                            Circle().fill(task.priority.color).frame(width: 6, height: 6)
                        }
                        if let due = task.dueDate {
                            Label(
                                due.formatted(.dateTime.month(.abbreviated).day()),
                                systemImage: "calendar"
                            )
                            .font(.system(size: 10))
                            .foregroundStyle(isOverdue(due) ? .red : .secondary)
                            .labelStyle(.titleAndIcon)
                        }
                        if !task.tags.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "tag.fill").font(.system(size: 8))
                                Text(task.tags.prefix(2).joined(separator: ", "))
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            // Detail button
            Button { onOpenDetail() } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Delete button — visible when the card is selected
            // This is the primary delete UX. Swipe-to-delete is a secondary option on iOS.
            if isListSelected {
                Button { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red.opacity(0.7))
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 4)
        // Swipe-to-delete on iOS as a secondary gesture
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        #endif
        // Context menu as tertiary option (long press)
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { onOpenDetail() } label: {
                Label("Details", systemImage: "info.circle")
            }
        }
        .onDisappear {
            flushRemoteSync()
        }
    }

    private func scheduleRemoteSync() {
        remoteSyncTask?.cancel()
        remoteSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await TodoSyncService.shared.upsertTask(task)
            remoteSyncTask = nil
        }
    }

    private func flushRemoteSync() {
        guard remoteSyncTask != nil else { return }
        remoteSyncTask?.cancel()
        remoteSyncTask = nil
        Task { await TodoSyncService.shared.upsertTask(task) }
    }

    private var hasMeta: Bool {
        task.priority != .none || task.dueDate != nil || !task.tags.isEmpty
    }

    private func isOverdue(_ date: Date) -> Bool {
        !task.isCompleted && date < Calendar.current.startOfDay(for: Date())
    }
}
