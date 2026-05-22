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

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ImageStorageService {

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
        let compressed = compress(data: data) ?? data
        let filename = "\(UUID().uuidString).jpg"
        let url = imagesDirectory.appendingPathComponent(filename)
        try compressed.write(to: url)
        return filename
    }

    // MARK: - Load
    static func load(fileName: String) -> PlatformImage? {
        let url = imagesDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #endif
    }

    static func url(for fileName: String) -> URL {
        imagesDirectory.appendingPathComponent(fileName)
    }

    // MARK: - Delete
    static func delete(fileName: String) {
        let url = imagesDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Compress
    /// Resizes to max 2048px on longest side, JPEG 0.8 quality.
    private static func compress(data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let maxDim: CGFloat = 2048
        let size = image.size
        if size.width <= maxDim && size.height <= maxDim {
            return image.jpegData(compressionQuality: 0.8)
        }
        let scale = maxDim / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        let maxDim: CGFloat = 2048
        let size = image.size
        let scale = min(1.0, maxDim / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: newSize))
        newImage.unlockFocus()
        guard let cgImage = newImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        #endif
    }
}

// Platform type alias for convenience
#if canImport(UIKit)
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
typealias PlatformImage = NSImage
#endif
