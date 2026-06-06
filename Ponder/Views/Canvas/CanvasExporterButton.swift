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
    let youtubeElements: [YouTubeElementModel]
    let drawings:      [DrawingElementModel]
    let symbols:       [SymbolElementModel]
    let connectors:    [ConnectorModel]
    let currentViewportRect: CGRect?

    @ObservedObject private var pro = ProManager.shared
    @ObservedObject private var auth = AuthService.shared

    // Read current color scheme so export matches what user sees
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings

    @State private var isExporting    = false
    @State private var exportedFile: ExportedFile? = nil
    @State private var showPaywall = false
    @State private var showAuth = false

    var body: some View {
        VStack(spacing: 10) {
            pngExportButton
            pdfExportControl
        }
        .disabled(isExporting)
        .sheet(item: $exportedFile) { file in
            #if os(iOS)
            ShareSheet(items: [file.data as Any], filename: file.filename)
            #else
            EmptyView()
            #endif
        }
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
                subtitle: "Sign in to restore your canvases and sync Canvio Pro across all your devices.",
                onSignedIn: {
                    showAuth = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
    }

    private var pngExportButton: some View {
        Button {
            if pro.isPro {
                Task { await export(.png) }
            } else {
                showPaywall = true
            }
        } label: {
            exportRow(
                title: "Export as PNG",
                subtitle: "Save a high-quality image of your canvas to share with others.",
                icon: "photo",
                showsProgress: isExporting
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pdfExportControl: some View {
        if pro.isPro {
            Menu {
                Button {
                    Task { await export(.pdf(.allContent)) }
                } label: {
                    Label("All Content", systemImage: "rectangle.expand.vertical")
                }

                Button {
                    if let currentViewportRect {
                        Task { await export(.pdf(.currentViewport(currentViewportRect))) }
                    }
                } label: {
                    Label("Current View", systemImage: "viewfinder")
                }
                .disabled(currentViewportRect == nil)
            } label: {
                exportRow(
                    title: "Export as PDF",
                    subtitle: "Create a single-page PDF from all content or the current view.",
                    icon: "doc.richtext",
                    showsProgress: isExporting
                )
            }
            .buttonStyle(.plain)
        } else {
            Button {
                showPaywall = true
            } label: {
                exportRow(
                    title: "Export as PDF",
                    subtitle: "Create a single-page PDF from all content or the current view.",
                    icon: "doc.richtext",
                    showsProgress: isExporting
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func export(_ request: ExportRequest) async {
        isExporting = true
        defer { isExporting = false }

        let youtubeThumbnails = await CanvasExporter.loadYouTubeThumbnails(for: youtubeElements)

        let result: ExportResult?
        switch request {
        case .png:
            guard let data = CanvasExporter.exportPNG(
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
                youtubeElements: youtubeElements,
                drawings:      drawings,
                symbols:       symbols,
                youtubeThumbnails: youtubeThumbnails,
                connectors:    connectors,
                colorScheme:   colorScheme,
                gridStyle:     settings.effectiveGridStyle,
                backgroundMode: settings.canvasBackgroundMode,
                backgroundPalette: settings.canvasBackgroundPalette
            ) else { return }
            result = ExportResult(
                data: data,
                filename: "\(exportBaseName).png",
                contentType: .png,
                saveTitle: "Export Canvas as PNG"
            )

        case .pdf(let scope):
            guard let data = CanvasExporter.exportPDF(
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
                youtubeElements: youtubeElements,
                drawings:      drawings,
                symbols:       symbols,
                youtubeThumbnails: youtubeThumbnails,
                connectors:    connectors,
                colorScheme:   colorScheme,
                gridStyle:     settings.effectiveGridStyle,
                backgroundMode: settings.canvasBackgroundMode,
                backgroundPalette: settings.canvasBackgroundPalette,
                exportScope:   scope
            ) else { return }
            result = ExportResult(
                data: data,
                filename: "\(exportBaseName).pdf",
                contentType: .pdf,
                saveTitle: "Export Canvas as PDF"
            )
        }

        guard let result else { return }

        #if os(iOS)
        exportedFile = ExportedFile(data: result.data, filename: result.filename)
        #else
        saveMacOS(data: result.data, filename: result.filename,
                  contentType: result.contentType, title: result.saveTitle)
        #endif
    }

    private func exportRow(
        title: String,
        subtitle: String,
        icon: String,
        showsProgress: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.primary)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.primary)

                    if !pro.isPro {
                        Text("PRO")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .foregroundStyle(Color.white)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)

            if showsProgress {
                ProgressView().scaleEffect(0.9)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var exportBaseName: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = canvas.name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Canvas" : cleaned
    }

    #if os(macOS)
    private func saveMacOS(data: Data, filename: String, contentType: UTType, title: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes  = [contentType]
        panel.title = title
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }
    #endif
}

private enum ExportRequest {
    case png
    case pdf(CanvasExportScope)
}

private struct ExportResult {
    let data: Data
    let filename: String
    let contentType: UTType
    let saveTitle: String
}

private struct ExportedFile: Identifiable {
    let id   = UUID()
    let data: Data
    let filename: String
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
