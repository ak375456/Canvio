//
//  ImageStorqgeServices.swift
//  Ponder
//
//  Created by aftab fazal qayum on 12/05/2026.
//

//
//  ImageStorageService.swift
//  Ponder
//

import Foundation
import SwiftUI
import ImageIO

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Platform type alias for convenience
#if canImport(UIKit)
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
typealias PlatformImage = NSImage
#endif

enum ImageStorageService {
    private static let imageCache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()
    private static let alphaCache = NSCache<NSString, NSNumber>()

    // MARK: - Directory
    static var imagesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("CanvasImages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Save
    /// Saves raw data (from PhotosPicker) to disk, compresses it, returns the filename.
    static func save(data: Data) throws -> String {
        let stored = prepareForStorage(data: data) ?? (data: data, fileExtension: "jpg")
        let filename = "\(UUID().uuidString).\(stored.fileExtension)"
        let url = imagesDirectory.appendingPathComponent(filename)
        try stored.data.write(to: url)
        alphaCache.setObject(NSNumber(value: stored.fileExtension == "png"), forKey: filename as NSString)
        return filename
    }

    // MARK: - Load
    static func load(fileName: String) -> PlatformImage? {
        let key = fileName as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }

        let url = imagesDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        #endif
        imageCache.setObject(image, forKey: key, cost: cacheCost(for: image))
        return image
    }

    static func url(for fileName: String) -> URL {
        imagesDirectory.appendingPathComponent(fileName)
    }

    static func contentType(for fileName: String) -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
        }
    }

    static func hasTransparency(fileName: String) -> Bool {
        let key = fileName as NSString
        if let cached = alphaCache.object(forKey: key) {
            return cached.boolValue
        }

        let hasAlpha = (fileName as NSString).pathExtension.lowercased() == "png"
        alphaCache.setObject(NSNumber(value: hasAlpha), forKey: key)
        return hasAlpha
    }

    static func invalidateCache(fileName: String) {
        let key = fileName as NSString
        imageCache.removeObject(forKey: key)
        alphaCache.removeObject(forKey: key)
    }

    // MARK: - Delete
    static func delete(fileName: String) {
        let url = imagesDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        invalidateCache(fileName: fileName)
    }

    // MARK: - Encode
    /// Resizes to max 2048px on the longest side. Images with alpha are saved
    /// as PNG so transparent backgrounds survive; other images use JPEG.
    private static func prepareForStorage(data: Data) -> (data: Data, fileExtension: String)? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let hasAlpha = hasAlphaChannel(data: data)
        let maxPixelDimension: CGFloat = hasAlpha ? 1536 : 2048
        let pixelSize = CGSize(width: image.size.width * image.scale,
                               height: image.size.height * image.scale)
        let shouldResize = pixelSize.width > maxPixelDimension || pixelSize.height > maxPixelDimension
        let outputImage: UIImage

        if shouldResize {
            let scale = maxPixelDimension / max(pixelSize.width, pixelSize.height)
            let newSize = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
            let format = UIGraphicsImageRendererFormat.default()
            format.opaque = !hasAlpha
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            outputImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            outputImage = image
        }

        if hasAlpha {
            guard let png = outputImage.pngData() else { return nil }
            return (png, "png")
        }

        guard let jpeg = outputImage.jpegData(compressionQuality: 0.8) else { return nil }
        return (jpeg, "jpg")

        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        let hasAlpha = hasAlphaChannel(data: data)
        let maxPixelDimension: CGFloat = hasAlpha ? 1536 : 2048
        let sourceCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let pixelSize = sourceCGImage.map { CGSize(width: CGFloat($0.width), height: CGFloat($0.height)) } ?? image.size
        let scale = min(1.0, maxPixelDimension / max(pixelSize.width, pixelSize.height))
        let newSize = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        (hasAlpha ? NSColor.clear : NSColor.white).setFill()
        NSRect(origin: .zero, size: newSize).fill()
        image.draw(in: CGRect(origin: .zero, size: newSize))
        newImage.unlockFocus()
        guard let cgImage = newImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        if hasAlpha {
            guard let png = bitmapRep.representation(using: .png, properties: [:]) else { return nil }
            return (png, "png")
        }
        guard let jpeg = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        return (jpeg, "jpg")
        #endif
    }

    private static func hasAlphaChannel(data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return false
        }

        switch cgImage.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }

    private static func cacheCost(for image: PlatformImage) -> Int {
        #if canImport(UIKit)
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        #elseif canImport(AppKit)
        let pixels = image.size.width * image.size.height
        #endif
        return max(1, Int(pixels * 4))
    }
}
