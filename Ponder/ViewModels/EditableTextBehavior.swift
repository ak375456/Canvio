import Foundation
import Combine

@MainActor
final class EditableTextBehavior: ObservableObject {
    @Published var draft: String = ""

    private let debounceNanoseconds: UInt64
    private var remoteSyncTask: Task<Void, Never>?
    private var hasPendingRemoteSync = false

    init(debounceNanoseconds: UInt64 = 700_000_000) {
        self.debounceNanoseconds = debounceNanoseconds
    }

    func load(_ text: String, force: Bool = false) {
        guard force || draft != text else { return }
        draft = text
    }

    func handleDraftChange(
        localSave: (String) -> Bool,
        remoteSync: @escaping @MainActor () async -> Void
    ) {
        guard localSave(draft) else { return }
        scheduleRemoteSync(remoteSync)
    }

    func commitDraft(
        localSave: (String) -> Bool,
        remoteSync: @escaping @MainActor () async -> Void
    ) {
        let saved = localSave(draft)
        flushRemoteSync(remoteSync, force: saved)
    }

    func scheduleRemoteSync(_ remoteSync: @escaping @MainActor () async -> Void) {
        hasPendingRemoteSync = true
        remoteSyncTask?.cancel()
        remoteSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await remoteSync()
            hasPendingRemoteSync = false
            remoteSyncTask = nil
        }
    }

    func flushRemoteSync(
        _ remoteSync: @escaping @MainActor () async -> Void,
        force: Bool = false
    ) {
        let shouldSync = hasPendingRemoteSync || force
        remoteSyncTask?.cancel()
        remoteSyncTask = nil
        hasPendingRemoteSync = false
        guard shouldSync else { return }

        Task { @MainActor in
            await remoteSync()
        }
    }

    func cancelRemoteSync() {
        remoteSyncTask?.cancel()
        remoteSyncTask = nil
        hasPendingRemoteSync = false
    }
}
