//
//  PDFStorageService.swift
//  Ponder
//

import Foundation
import PDFKit
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum PDFStorageService {

    // MARK: - Directories
    static var pdfsDirectory: URL {
        directory(named: "CanvasPDFs")
    }

    static var thumbnailsDirectory: URL {
        directory(named: "CanvasPDFThumbs")
    }

    private static func directory(named name: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Import PDF from a security-scoped URL
    /// Call this from within a security scope (after startAccessingSecurityScopedResource)
    static func importPDF(from sourceURL: URL) throws -> (
        pdfFileName: String,
        thumbnailFileName: String,
        originalName: String,
        pageCount: Int
    ) {
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let pdfFileName = "\(UUID().uuidString).pdf"
        let destURL = pdfsDirectory.appendingPathComponent(pdfFileName)

        // Copy the file
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        // Open with PDFKit to get page count + render thumbnail
        guard let doc = PDFDocument(url: destURL) else {
            throw PDFError.cannotOpen
        }
        let pageCount = doc.pageCount

        // Render first page as thumbnail
        let thumbName = try renderThumbnail(doc: doc, pdfFileName: pdfFileName)

        return (pdfFileName, thumbName, originalName, pageCount)
    }

    #if canImport(UIKit)
    static func importScannedImages(_ images: [UIImage], originalName: String) throws -> (
        pdfFileName: String,
        thumbnailFileName: String,
        originalName: String,
        pageCount: Int
    ) {
        guard !images.isEmpty else { throw PDFError.noPages }

        let pdfFileName = "\(UUID().uuidString).pdf"
        let destURL = pdfsDirectory.appendingPathComponent(pdfFileName)
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        try renderer.writePDF(to: destURL) { context in
            for image in images {
                context.beginPage()
                UIColor.white.setFill()
                context.cgContext.fill(pageBounds)

                let imageSize = image.size
                let scale = min(pageBounds.width / max(1, imageSize.width),
                                pageBounds.height / max(1, imageSize.height))
                let drawSize = CGSize(width: imageSize.width * scale,
                                      height: imageSize.height * scale)
                let drawRect = CGRect(
                    x: (pageBounds.width - drawSize.width) / 2,
                    y: (pageBounds.height - drawSize.height) / 2,
                    width: drawSize.width,
                    height: drawSize.height
                )
                image.draw(in: drawRect)
            }
        }

        guard let doc = PDFDocument(url: destURL) else {
            throw PDFError.cannotOpen
        }
        let thumbName = try renderThumbnail(doc: doc, pdfFileName: pdfFileName)
        return (pdfFileName, thumbName, originalName, doc.pageCount)
    }
    #endif

    // MARK: - Render thumbnail for page 1
    @discardableResult
    static func renderThumbnail(doc: PDFDocument, pdfFileName: String) throws -> String {
        guard let page = doc.page(at: 0) else { throw PDFError.noPages }

        let pageRect = page.bounds(for: .mediaBox)

        // Target 1200px on the longest side for crisp rendering
        let targetLong: CGFloat = 1200
        let scale = targetLong / max(pageRect.width, pageRect.height)
        let thumbSize = CGSize(
            width: ceil(pageRect.width * scale),
            height: ceil(pageRect.height * scale)
        )

        let thumbFileName = pdfFileName.replacingOccurrences(of: ".pdf", with: "_thumb.jpg")
        let thumbURL = thumbnailsDirectory.appendingPathComponent(thumbFileName)

        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: thumbSize)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: thumbSize))
            ctx.cgContext.translateBy(x: 0, y: thumbSize.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        if let data = image.jpegData(compressionQuality: 0.92) {
            try data.write(to: thumbURL)
        }

        #elseif canImport(AppKit)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let cgContext = CGContext(
            data: nil,
            width: Int(thumbSize.width),
            height: Int(thumbSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { throw PDFError.cannotOpen }

        // White background
        cgContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        cgContext.fill(CGRect(origin: .zero, size: thumbSize))

        // Scale to fill the target size
        cgContext.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: cgContext)

        guard let cgImage = cgContext.makeImage() else { throw PDFError.cannotOpen }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        if let data = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: NSNumber(value: 0.92)]
        ) {
            try data.write(to: thumbURL)
        }
        #endif

        return thumbFileName
    }

    // MARK: - Load
    static func loadPDF(fileName: String) -> PDFDocument? {
        let url = pdfsDirectory.appendingPathComponent(fileName)
        return PDFDocument(url: url)
    }

    static func loadThumbnail(fileName: String) -> PlatformImage? {
        let url = thumbnailsDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        #if canImport(UIKit)
        return UIImage(data: data)
        #else
        return NSImage(data: data)
        #endif
    }

    // MARK: - Delete
    static func delete(pdfFileName: String, thumbnailFileName: String) {
        try? FileManager.default.removeItem(at: pdfsDirectory.appendingPathComponent(pdfFileName))
        try? FileManager.default.removeItem(at: thumbnailsDirectory.appendingPathComponent(thumbnailFileName))
    }

    // MARK: - Error
    enum PDFError: Error {
        case cannotOpen
        case noPages
    }
}
