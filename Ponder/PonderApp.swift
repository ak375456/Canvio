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

    init() {
        registerCustomFonts()
        AuthService.shared.listenToAuthChanges()
    }

    private func registerCustomFonts() {
        guard let resourcePath = Bundle.main.resourcePath else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) else { return }
        let ttfFiles = files.filter { $0.lowercased().hasSuffix(".ttf") }
        for file in ttfFiles {
            let url = URL(fileURLWithPath: resourcePath).appendingPathComponent(file)
            var error: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    var body: some Scene {
        WindowGroup {
            SyncCoordinatorView()
                .environmentObject(settings)
                .environmentObject(networkMonitor)
                .preferredColorScheme(settings.theme.colorScheme)
        }
        .modelContainer(for: [
            CanvasModel.self,
            TextElementModel.self,
            StickyNoteModel.self,
            TodoListModel.self,
            TodoTaskModel.self,
            ShapeElementModel.self,
            ImageElementModel.self,
            PDFElementModel.self,
            TableElementModel.self,
            TableCellModel.self,
            AudioElementModel.self,
            DrawingElementModel.self,
            ConnectorModel.self
        ])
    }
}

private struct SyncCoordinatorView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var auth = AuthService.shared

    // Check account validity every 60 seconds while the app is open
    private let accountCheckTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ContentView()
            .task {
                await restoreAndSync()
            }
            // Periodic check: did someone delete the account from another device?
            .onReceive(accountCheckTimer) { _ in
                guard auth.currentUser != nil else { return }
                Task {
                    await auth.checkAccountStillExists(context: modelContext)
                }
            }
            // Also check immediately when app comes back to foreground
            .onReceive(
                NotificationCenter.default.publisher(
                    for: {
                        #if os(iOS)
                        return UIApplication.willEnterForegroundNotification
                        #else
                        return NSApplication.willBecomeActiveNotification
                        #endif
                    }()
                )
            ) { _ in
                guard auth.currentUser != nil else { return }
                Task {
                    await auth.checkAccountStillExists(context: modelContext)
                }
            }
    }

    private func restoreAndSync() async {
        // Step 1 — Restore session (also validates account still exists)
        await AuthService.shared.restoreSession()

        // Step 2 — Only sync if logged in
        guard AuthService.shared.currentUser != nil else { return }

        // Step 3 — Flush all queued offline operations
        await CanvasSyncService.shared.flushQueue()
        await TextSyncService.shared.flushQueue()
        await StickyNoteSyncService.shared.flushQueue()
        await ShapeSyncService.shared.flushQueue()
        await ConnectorSyncService.shared.flushQueue()
        await DrawingSyncService.shared.flushQueue()
        await TodoSyncService.shared.flushQueue()
        await TableSyncService.shared.flushQueue()
        await ImageSyncService.shared.flushQueue()
        await PDFSyncService.shared.flushQueue()
        await AudioSyncService.shared.flushQueue()

        // Step 4 — Pull canvases from Supabase → SwiftData
        await CanvasSyncService.shared.pullAll(context: modelContext)

        // Step 5 — Reconcile: push any local canvases missing from Supabase
        await CanvasSyncService.shared.reconcileLocalToRemote(context: modelContext)

        // Step 6 — Yield so SwiftData makes new records visible
        await Task.yield()

        // Step 7 — Pull all element types for every canvas
        let canvases = (try? modelContext.fetch(FetchDescriptor<CanvasModel>())) ?? []
        for canvas in canvases {
            await TextSyncService.shared.pullAll(canvasID: canvas.id, context: modelContext)
            await StickyNoteSyncService.shared.pullAll(canvasID: canvas.id, context: modelContext)
            await ShapeSyncService.shared.pullAll(canvasID: canvas.id, context: modelContext)
            await ConnectorSyncService.shared.pullAll(canvasID: canvas.id, context: modelContext)
            await DrawingSyncService.shared.pullAll(canvasID: canvas.id, context: modelContext)
            await TodoSyncService.shared.pullAll(canvasID: canvas.id, context: modelContext)
            await TableSyncService.shared.pullAll(canvasID: canvas.id, context: modelContext)
            await ImageSyncService.shared.pullAll(canvasID: canvas.id, context: modelContext)
            await PDFSyncService.shared.pullAll(canvasID: canvas.id, context: modelContext)
            await AudioSyncService.shared.pullAll(canvasID: canvas.id, context: modelContext)
        }
    }
}
