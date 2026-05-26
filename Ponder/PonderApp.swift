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
                .environmentObject(proManager)
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
            ConnectorModel.self,
            SymbolElementModel.self     // ← NEW
        ])
    }
}

private struct SyncCoordinatorView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var pro = ProManager.shared

    private let accountCheckTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ContentView()
            .task { await restoreAndSync() }
            .onReceive(accountCheckTimer) { _ in
                guard auth.currentUser != nil else { return }
                Task { await auth.checkAccountStillExists(context: modelContext) }
            }
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
    }

    private func restoreAndSync() async {
        await ProManager.shared.refreshStatus()
        await AuthService.shared.restoreSession()
        guard ProManager.shared.isPro,
              AuthService.shared.currentUser != nil else { return }

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
        await SymbolSyncService.shared.flushQueue()     // ← NEW

        await CanvasSyncService.shared.pullAll(context: modelContext)
        await CanvasSyncService.shared.reconcileLocalToRemote(context: modelContext)
        await Task.yield()

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
            await SymbolSyncService.shared.pullAll(canvasID: canvas.id, context: modelContext)  // ← NEW
        }
    }
}
