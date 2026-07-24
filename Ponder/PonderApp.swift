//
//  PonderApp.swift
//  Ponder
//

import SwiftUI
import SwiftData
import CoreText
import Combine

@main
struct PonderApp: App {
    @StateObject private var settings       = AppSettings()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var proManager     = ProManager.shared

    init() {
        AppFontRegistry.registerStoredCustomFonts()
        AuthService.shared.listenToAuthChanges()
    }

    var body: some Scene {
        WindowGroup {
            SyncCoordinatorView()
                .environmentObject(settings)
                .environmentObject(networkMonitor)
                .environmentObject(proManager)
                .preferredColorScheme(settings.theme.colorScheme)
                .onOpenURL { url in
                    AuthService.shared.handleIncomingURL(url)
                }
        }
        .modelContainer(for: [
            CanvasModel.self,
            CanvasPageModel.self,
            TextElementModel.self,
            StickyNoteModel.self,
            TodoListModel.self,
            TodoTaskModel.self,
            ShapeElementModel.self,
            ImageElementModel.self,
            PDFElementModel.self,
            PDFPageElementModel.self,
            PDFHighlightModel.self,
            PDFInkLayerModel.self,
            PDFReadingStateModel.self,
            TableElementModel.self,
            TableCellModel.self,
            AudioElementModel.self,
            YouTubeElementModel.self,
            DrawingElementModel.self,
            ConnectorModel.self,
            SymbolElementModel.self,
            CanvasElementGroupModel.self
        ])
    }
}

private struct SyncCoordinatorView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var pro  = ProManager.shared
    @State private var isFullSyncRunning = false

    private let accountCheckTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ContentView()
            .task { await restoreAndSync() }
            // Full sync whenever app comes to foreground
            .onReceive(
                NotificationCenter.default.publisher(for: {
                    #if os(iOS)
                    return UIApplication.willEnterForegroundNotification
                    #else
                    return NSApplication.willBecomeActiveNotification
                    #endif
                }())
            ) { _ in
                Task { await pro.refreshStatus() }
                guard auth.currentUser != nil else { return }
                Task { await auth.checkAccountStillExists(context: modelContext) }
            }
            // Periodic account validity check
            .onReceive(accountCheckTimer) { _ in
                guard auth.currentUser != nil else { return }
                Task { await auth.checkAccountStillExists(context: modelContext) }
            }
            // ── Trigger reconcile when user logs in ───────────────────
            // This pushes all local canvases + elements that were created
            // before the user had an account up to Supabase.
            .onReceive(AuthService.shared.didSignIn) {
                Task {
                    guard ProManager.shared.isPro else { return }
                    print("🔑 Login detected — reconciling all local data")
                    await fullSyncAfterAuth()
                }
            }
            // ── Trigger reconcile when Pro is purchased ───────────────
            // This pushes all local data that existed before Pro was bought.
            .onChange(of: pro.isPro) { _, isPro in
                guard isPro, auth.currentUser != nil else { return }
                Task {
                    print("⭐ Pro purchased — reconciling all local data")
                    await fullSyncAfterAuth()
                }
            }
    }

    // MARK: - App launch sync

    private func restoreAndSync() async {
        await ProManager.shared.refreshStatus()
        await AuthService.shared.restoreSession()
        guard ProManager.shared.isPro,
              AuthService.shared.currentUser != nil else { return }
        await fullSyncAfterAuth()
    }

    // MARK: - Full sync
    //
    // 1. Flush any queued offline operations
    // 2. Reconcile all local data → Supabase (handles pre-login / pre-Pro data)
    // 3. Pull everything from Supabase → local

    private func fullSyncAfterAuth() async {
        guard ProManager.shared.isPro,
              let currentUserID = AuthService.shared.syncUserID else { return }
        guard !isFullSyncRunning else {
            print("⏭️ Full sync already running — skipped duplicate trigger")
            return
        }
        isFullSyncRunning = true
        defer { isFullSyncRunning = false }

        let discarded = SyncQueue.shared.discardOperationsOwnedByAnotherUser(
            currentUserID: currentUserID
        )
        if discarded > 0 {
            print("🧹 Discarded \(discarded) queued operation(s) from another account")
        }

        // Step 1 — flush offline queue
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

        // Step 2 — push all local data that Supabase doesn't have yet
        await CanvasSyncService.shared.reconcileAllLocalData(context: modelContext)

        // Step 3 — pull everything from Supabase
        await CanvasSyncService.shared.pullAll(context: modelContext)
        await Task.yield()

        let canvases = (try? modelContext.fetch(FetchDescriptor<CanvasModel>())) ?? []
        for canvas in canvases {
            await CanvasPageSyncService.shared.pullAll(canvasID: canvas.id, context: modelContext)
            for contentCanvasID in pageContentCanvasIDs(for: canvas.id) {
                await pullElements(canvasID: contentCanvasID)
            }
        }
    }

    private func pageContentCanvasIDs(for canvasID: UUID) -> [UUID] {
        let pages = (try? modelContext.fetch(FetchDescriptor<CanvasPageModel>())) ?? []
        let ids = pages
            .filter { $0.canvasID == canvasID }
            .map(\.resolvedContentCanvasID)
        return ids.isEmpty ? [canvasID] : Array(Set(ids))
    }

    private func pullElements(canvasID: UUID) async {
        await ElementGroupSyncService.shared.pullAll(canvasID: canvasID, context: modelContext)
        await TextSyncService.shared.pullAll(canvasID: canvasID, context: modelContext)
        await StickyNoteSyncService.shared.pullAll(canvasID: canvasID, context: modelContext)
        await ShapeSyncService.shared.pullAll(canvasID: canvasID, context: modelContext)
        await ConnectorSyncService.shared.pullAll(canvasID: canvasID, context: modelContext)
        await DrawingSyncService.shared.pullAll(canvasID: canvasID, context: modelContext)
        await TodoSyncService.shared.pullAll(canvasID: canvasID, context: modelContext)
        await TableSyncService.shared.pullAll(canvasID: canvasID, context: modelContext)
        await ImageSyncService.shared.pullAll(canvasID: canvasID, context: modelContext)
        await PDFSyncService.shared.pullAll(canvasID: canvasID, context: modelContext)
        await PDFWorkspaceSyncService.shared.pullAll(canvasID: canvasID, context: modelContext)
        await AudioSyncService.shared.pullAll(canvasID: canvasID, context: modelContext)
        await YouTubeSyncService.shared.pullAll(canvasID: canvasID, context: modelContext)
        await SymbolSyncService.shared.pullAll(canvasID: canvasID, context: modelContext)
    }
}
