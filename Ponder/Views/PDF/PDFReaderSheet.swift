//
//  PDFReaderSheet.swift
//  Ponder
//

import SwiftUI
import PDFKit

struct PDFReaderSheet: View {
    let pdfFileName: String
    let originalName: String
    let pageCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(iOS)
        iOSLayout
        #else
        macOSLayout
        #endif
    }

    // MARK: - iOS layout
    private var iOSLayout: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pdfContent
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - macOS layout
    private var macOSLayout: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pdfContent
        }
        .frame(minWidth: 600, idealWidth: 800, maxWidth: .infinity,
               minHeight: 500, idealHeight: 900, maxHeight: .infinity)
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 1) {
                Text(originalName.isEmpty ? "Document" : originalName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(pageCount) page\(pageCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: - PDF content
    @ViewBuilder
    private var pdfContent: some View {
        if let doc = PDFStorageService.loadPDF(fileName: pdfFileName) {
            PDFKitView(document: doc)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.richtext.slash")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(.tertiary)
                Text("PDF not available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - PDFKit wrapper
struct PDFKitView: View {
    let document: PDFDocument

    var body: some View {
        _PDFKitRepresentable(document: document)
            .ignoresSafeArea(edges: .bottom)
    }
}

#if canImport(UIKit)
private struct _PDFKitRepresentable: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageBreakMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view.backgroundColor = UIColor.systemGroupedBackground
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = document
        }
    }
}
#elseif canImport(AppKit)
private struct _PDFKitRepresentable: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor.controlBackgroundColor
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
    }
}
#endif
