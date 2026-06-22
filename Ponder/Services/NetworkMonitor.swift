//
//  NetworkMonitor.swift
//  Ponder
//

import Foundation
import Network
import Combine

@MainActor
final class NetworkMonitor: ObservableObject {

    static let shared = NetworkMonitor()

    @Published var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue   = DispatchQueue(label: "com.ponder.networkmonitor", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                let connected = path.status == .satisfied
                guard self?.isConnected != connected else { return }
                self?.isConnected = connected
                if connected {
                    // Back online — flush all sync queues
                    if let userID = AuthService.shared.syncUserID {
                        let discarded = SyncQueue.shared.discardOperationsOwnedByAnotherUser(
                            currentUserID: userID
                        )
                        if discarded > 0 {
                            print("🧹 Discarded \(discarded) queued operation(s) from another account")
                        }
                    }
                    await CanvasSyncService.shared.flushQueue()
                    await CanvasPageSyncService.shared.flushQueue()
                    await TextSyncService.shared.flushQueue()
                    await StickyNoteSyncService.shared.flushQueue()
                    await ShapeSyncService.shared.flushQueue()
                    await ConnectorSyncService.shared.flushQueue()
                    await DrawingSyncService.shared.flushQueue()
                    await TodoSyncService.shared.flushQueue()
                    await TableSyncService.shared.flushQueue()
                    await ImageSyncService.shared.flushQueue()
                    await PDFSyncService.shared.flushQueue()
                    await PDFWorkspaceSyncService.shared.flushQueue()
                    await AudioSyncService.shared.flushQueue()
                    await YouTubeSyncService.shared.flushQueue()
                    await SymbolSyncService.shared.flushQueue()
                    await ElementGroupSyncService.shared.flushQueue()
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
