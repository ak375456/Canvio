//
//  CanvasExportButton.swift
//  Ponder
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CanvasExportButton: View {
    let canvas:        CanvasModel
    let textElements:  [TextElementModel]
    let stickyNotes:   [StickyNoteModel]
    let todoLists:     [TodoListModel]
    let todoTasks:     [TodoTaskModel]
    let shapes:        [ShapeElementModel]
    let images:        [ImageElementModel]
    let pdfs:          [PDFElementModel]
    let tables:        [TableElementModel]
    let tableCells:    [TableCellModel]
    let audioElements: [AudioElementModel]
    let drawings:      [DrawingElementModel]
    let connectors:    [ConnectorModel]

    @ObservedObject private var pro = ProManager.shared
    @ObservedObject private var auth = AuthService.shared

    // Read current color scheme so export matches what user sees
    @Environment(\.colorScheme) private var colorScheme

    @State private var isExporting    = false
    @State private var exportedImage: ExportedImage? = nil
    @State private var showShareSheet = false
    @State private var showPaywall = false
    @State private var showAuth = false

    var body: some View {
        Button {
            if pro.isPro {
                Task { await export() }
            } else {
                showPaywall = true
            }
        } label: {
            if isExporting {
                ProgressView().scaleEffect(0.8)
            } else {
                Image(systemName: "square.and.arrow.up").fontWeight(.medium)
            }
        }
        .disabled(isExporting)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet {
                if auth.currentUser == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showAuth = true
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
        .sheet(isPresented: $showAuth) {
            AuthView(
                title: "Sign in for Sync",
                subtitle: "Sign in to restore your canvases and sync Canvio Pro across all your devices."
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
        #if os(iOS)
        .sheet(isPresented: $showShareSheet) {
            if let img = exportedImage {
                ShareSheet(items: [img.data as Any], filename: "\(canvas.name).png")
            }
        }
        #endif
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }

        guard let pngData = CanvasExporter.exportPNG(
            canvas:        canvas,
            textElements:  textElements,
            stickyNotes:   stickyNotes,
            todoLists:     todoLists,
            todoTasks:     todoTasks,
            shapes:        shapes,
            images:        images,
            pdfs:          pdfs,
            tables:        tables,
            tableCells:    tableCells,
            audioElements: audioElements,
            drawings:      drawings,
            connectors:    connectors,
            colorScheme:   colorScheme
        ) else { return }

        #if os(iOS)
        exportedImage = ExportedImage(data: pngData)
        showShareSheet = true
        #else
        saveMacOS(data: pngData)
        #endif
    }

    #if os(macOS)
    private func saveMacOS(data: Data) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(canvas.name).png"
        panel.allowedContentTypes  = [.png]
        panel.title = "Export Canvas as PNG"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }
    #endif
}

private struct ExportedImage: Identifiable {
    let id   = UUID()
    let data: Data
}

#if os(iOS)
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items:    [Any]
    let filename: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        if let data = items.first as? Data { try? data.write(to: url) }
        return UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
