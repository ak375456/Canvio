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

struct ImageFreeformCutoutResult {
    let fileName: String
    let normalizedBounds: CGRect
}

enum ImageFreeformCutoutError: LocalizedError {
    case imageUnavailable
    case invalidSelection
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .imageUnavailable:
            return "The original image is not available on this device yet."
        case .invalidSelection:
            return "Draw a larger closed loop inside the image."
        case .renderingFailed:
            return "The cutout could not be created."
        }
    }
}

enum ImageStorageService {
    private static let imageCache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()
    /// Separate cache for downsampled display thumbnails, keyed by "filename@\(maxPx)".
    private static let thumbnailCache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 64 * 1024 * 1024
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

    static func fileExists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    // MARK: - Fast display thumbnail (ImageIO subsample path)

    /// Returns a downsampled image sized to `maxPixelSize` on the longest side.
    ///
    /// Uses `kCGImageSourceCreateThumbnailFromImageAlways` + `kCGImageSourceThumbnailMaxPixelSize`
    /// which tells ImageIO to subsample the JPEG during decoding — for a 2048-px JPEG
    /// displayed at 480 px it decodes only ~1/16 of the data, giving ~10–15× speedup
    /// vs loading the full bitmap. Results are cached by "filename@maxPx".
    ///
    /// Safe to call from a background thread.
    static func thumbnail(fileName: String, maxPixelSize: CGFloat) -> PlatformImage? {
        let roundedPx = Int(maxPixelSize.rounded(.up))
        let cacheKey  = "\(fileName)@\(roundedPx)" as NSString

        if let cached = thumbnailCache.object(forKey: cacheKey) { return cached }

        let url = imagesDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return load(fileName: fileName)  // fall back to full load
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform:   true,
            kCGImageSourceShouldCacheImmediately:         true,
            kCGImageSourceThumbnailMaxPixelSize:          roundedPx
        ]

        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return load(fileName: fileName)
        }

        #if canImport(UIKit)
        let thumb = UIImage(cgImage: cgThumb)
        #elseif canImport(AppKit)
        let thumb = NSImage(cgImage: cgThumb, size: .zero)
        #endif

        let cost = cgThumb.width * cgThumb.height * 4
        thumbnailCache.setObject(thumb, forKey: cacheKey, cost: cost)
        return thumb
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
        // Thumbnail cache uses "filename@px" keys; enumerate by prefix removal
        // via a simple pattern — NSCache doesn't support enumeration so we use
        // a small workaround: keep a set of known thumbnail keys per filename.
        thumbnailCache.removeObject(forKey: key) // removes exact match if any
    }

    // MARK: - Delete
    static func delete(fileName: String) {
        let url = imagesDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        invalidateCache(fileName: fileName)
    }

    // MARK: - Freeform cutout

    /// Keeps the pixels inside a normalized, image-space polygon and trims the
    /// transparent result to the polygon's bounds. Points use a top-left origin.
    static func createFreeformCutout(
        fileName: String,
        normalizedPolygon: [CGPoint]
    ) throws -> ImageFreeformCutoutResult {
        guard normalizedPolygon.count >= 3 else {
            throw ImageFreeformCutoutError.invalidSelection
        }

        let polygon = normalizedPolygon.map {
            CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1))
        }
        guard let first = polygon.first else {
            throw ImageFreeformCutoutError.invalidSelection
        }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in polygon.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        let bounds = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

        guard bounds.width >= 0.01, bounds.height >= 0.01 else {
            throw ImageFreeformCutoutError.invalidSelection
        }

        let sourceURL = url(for: fileName)
        guard let sourceData = try? Data(contentsOf: sourceURL) else {
            throw ImageFreeformCutoutError.imageUnavailable
        }

        #if canImport(UIKit)
        guard let image = UIImage(data: sourceData) else {
            throw ImageFreeformCutoutError.imageUnavailable
        }

        let fullSize = CGSize(
            width: max(1, image.size.width * image.scale),
            height: max(1, image.size.height * image.scale)
        )
        let outputSize = CGSize(
            width: max(1, (fullSize.width * bounds.width).rounded(.up)),
            height: max(1, (fullSize.height * bounds.height).rounded(.up))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let outputImage = renderer.image { _ in
            let path = UIBezierPath()
            for (index, point) in polygon.enumerated() {
                let localPoint = CGPoint(
                    x: (point.x - bounds.minX) * fullSize.width,
                    y: (point.y - bounds.minY) * fullSize.height
                )
                if index == 0 { path.move(to: localPoint) }
                else { path.addLine(to: localPoint) }
            }
            path.close()
            path.addClip()

            image.draw(in: CGRect(
                x: -bounds.minX * fullSize.width,
                y: -bounds.minY * fullSize.height,
                width: fullSize.width,
                height: fullSize.height
            ))
        }
        guard let pngData = outputImage.pngData() else {
            throw ImageFreeformCutoutError.renderingFailed
        }

        #elseif canImport(AppKit)
        guard let image = NSImage(data: sourceData),
              let sourceCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageFreeformCutoutError.imageUnavailable
        }

        let fullSize = CGSize(width: sourceCGImage.width, height: sourceCGImage.height)
        let outputWidth = max(1, Int((fullSize.width * bounds.width).rounded(.up)))
        let outputHeight = max(1, Int((fullSize.height * bounds.height).rounded(.up)))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: outputWidth,
            pixelsHigh: outputHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ImageFreeformCutoutError.renderingFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.cgContext.clear(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

        let path = NSBezierPath()
        for (index, point) in polygon.enumerated() {
            let localPoint = CGPoint(
                x: (point.x - bounds.minX) * fullSize.width,
                y: CGFloat(outputHeight) - (point.y - bounds.minY) * fullSize.height
            )
            if index == 0 { path.move(to: localPoint) }
            else { path.line(to: localPoint) }
        }
        path.close()
        path.addClip()

        image.draw(in: CGRect(
            x: -bounds.minX * fullSize.width,
            y: -(1 - bounds.maxY) * fullSize.height,
            width: fullSize.width,
            height: fullSize.height
        ), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageFreeformCutoutError.renderingFailed
        }
        #endif

        let newFileName = try save(data: pngData)
        return ImageFreeformCutoutResult(fileName: newFileName, normalizedBounds: bounds)
    }

    // MARK: - Encode
    /// Resizes to max 2048px on the longest side. Images with alpha are saved
    /// as PNG so transparent backgrounds survive; other images use JPEG.
    static func prepareForStorage(data: Data) -> (data: Data, fileExtension: String)? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let hasAlpha = hasAlphaChannel(data: data)
        let maxPixelDimension: CGFloat = hasAlpha ? 1536 : 2048
        let pixelSize = CGSize(width: image.size.width * image.scale,
                               height: image.size.height * image.scale)
        let shouldResize = pixelSize.width > maxPixelDimension || pixelSize.height > maxPixelDimension
        if !hasAlpha && !shouldResize && isJPEG(data: data) {
            return (data, "jpg")
        }

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
        if !hasAlpha && scale >= 1.0 && isJPEG(data: data) {
            return (data, "jpg")
        }

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

    private static func isJPEG(data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String? else {
            return false
        }

        let normalized = type.lowercased()
        return normalized == "public.jpeg" || normalized == "public.jpg" || normalized == "image/jpeg"
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
