//
//  PDFPickerService.swift
//  Ponder
//

import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit

class PDFPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    let onPick: (URL) -> Void
    init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        onPick(url)
    }
}

struct PDFDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> PDFPickerCoordinator {
        PDFPickerCoordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.pdf])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

#elseif canImport(AppKit)
import AppKit

// On macOS we don't use a sheet — we open NSOpenPanel directly.
func openMacOSPDFPicker(onPick: @escaping (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [UTType.pdf]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.title = "Choose a PDF"
    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        onPick(url)
    }
}
#endif
