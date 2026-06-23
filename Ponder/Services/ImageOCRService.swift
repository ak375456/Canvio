//
//  ImageOCRService.swift
//  Ponder
//

import Foundation
import CoreGraphics
import Vision

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ImageOCRService {
    enum OCRError: Error {
        case imageNotFound
        case unsupportedImage
    }

    static func recognizeText(fileName: String) async throws -> String {
        let url = ImageStorageService.url(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OCRError.imageNotFound
        }

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(url: url, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            return observations
                .sorted { lhs, rhs in
                    let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                    if yDelta > 0.02 {
                        return lhs.boundingBox.midY > rhs.boundingBox.midY
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }

    static func recognizeText(images: [PlatformImage]) async throws -> String {
        let pageTexts = try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    let text = try await recognizeText(image: image)
                    return (index, text)
                }
            }

            var results: [(Int, String)] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        return pageTexts
            .sorted { $0.0 < $1.0 }
            .map { $0.1.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func recognizeText(image: PlatformImage) async throws -> String {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { throw OCRError.unsupportedImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        #elseif canImport(AppKit)
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw OCRError.unsupportedImage
        }
        let orientation = CGImagePropertyOrientation.up
        #endif

        return try await recognizeText(cgImage: cgImage, orientation: orientation)
    }

    private static func recognizeText(cgImage: CGImage, orientation: CGImagePropertyOrientation) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            return observations
                .sorted { lhs, rhs in
                    let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                    if yDelta > 0.02 {
                        return lhs.boundingBox.midY > rhs.boundingBox.midY
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}

#if canImport(UIKit)
private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
#endif
