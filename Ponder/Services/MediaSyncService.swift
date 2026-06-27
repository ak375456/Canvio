//
//  MediaSyncService.swift
//  Ponder
//
//  Handles Supabase Storage uploads and downloads for images, PDFs, and audio.
//  Files are stored at: {userID}/{type}/{filename}
//  e.g. "abc-123/images/photo.jpg"
//

import Foundation
import Supabase

enum MediaAssetBundle {
    case image(fileName: String)
    case pdfFile(fileName: String)
    case pdf(pdfFileName: String, thumbnailFileName: String)
    case audio(fileName: String)
}

private struct MediaAssetDescriptor {
    let localURL: URL
    let storagePath: String
    let contentType: String
    let availableNotification: Notification.Name?
    let notificationObject: String?
    let invalidateCache: (() -> Void)?
}

@MainActor
final class MediaSyncService {

    static let shared = MediaSyncService()

    private let supabase  = SupabaseService.shared.client
    private let network   = NetworkMonitor.shared
    private let bucket    = "ponder-files"

    private init() {}

    // MARK: - Storage paths

    private func userID() -> String? {
        AuthService.shared.syncUserID?.lowercased()
    }

    func imagePath(for fileName: String) -> String {
        guard let uid = userID() else { return "unknown/images/\(fileName)" }
        return "\(uid)/images/\(fileName)"
    }

    func pdfPath(for fileName: String) -> String {
        guard let uid = userID() else { return "unknown/pdfs/\(fileName)" }
        return "\(uid)/pdfs/\(fileName)"
    }

    func pdfThumbPath(for fileName: String) -> String {
        guard let uid = userID() else { return "unknown/pdfthumbs/\(fileName)" }
        return "\(uid)/pdfthumbs/\(fileName)"
    }

    func audioPath(for fileName: String) -> String {
        guard let uid = userID() else { return "unknown/audio/\(fileName)" }
        return "\(uid)/audio/\(fileName)"
    }

    private func assets(for bundle: MediaAssetBundle) -> [MediaAssetDescriptor] {
        switch bundle {
        case .image(let fileName):
            return [
                MediaAssetDescriptor(
                    localURL: ImageStorageService.url(for: fileName),
                    storagePath: imagePath(for: fileName),
                    contentType: ImageStorageService.contentType(for: fileName),
                    availableNotification: .imageFileDidBecomeAvailable,
                    notificationObject: fileName,
                    invalidateCache: {
                        ImageStorageService.invalidateCache(fileName: fileName)
                    }
                )
            ]

        case .pdfFile(let fileName):
            return [
                MediaAssetDescriptor(
                    localURL: PDFStorageService.pdfsDirectory.appendingPathComponent(fileName),
                    storagePath: pdfPath(for: fileName),
                    contentType: "application/pdf",
                    availableNotification: .pdfFileDidBecomeAvailable,
                    notificationObject: fileName,
                    invalidateCache: nil
                )
            ]

        case .pdf(let pdfFileName, let thumbnailFileName):
            return [
                MediaAssetDescriptor(
                    localURL: PDFStorageService.pdfsDirectory.appendingPathComponent(pdfFileName),
                    storagePath: pdfPath(for: pdfFileName),
                    contentType: "application/pdf",
                    availableNotification: .pdfFileDidBecomeAvailable,
                    notificationObject: pdfFileName,
                    invalidateCache: nil
                ),
                MediaAssetDescriptor(
                    localURL: PDFStorageService.thumbnailsDirectory.appendingPathComponent(thumbnailFileName),
                    storagePath: pdfThumbPath(for: thumbnailFileName),
                    contentType: "image/jpeg",
                    availableNotification: nil,
                    notificationObject: nil,
                    invalidateCache: nil
                )
            ]

        case .audio(let fileName):
            let ext = (fileName as NSString).pathExtension.lowercased()
            return [
                MediaAssetDescriptor(
                    localURL: AudioStorageService.url(for: fileName),
                    storagePath: audioPath(for: fileName),
                    contentType: ext == "mp3" ? "audio/mpeg" : "audio/mp4",
                    availableNotification: nil,
                    notificationObject: nil,
                    invalidateCache: nil
                )
            ]
        }
    }

    private func performWithRetry(
        _ label: String,
        maxAttempts: Int = 3,
        operation: () async throws -> Void
    ) async -> Bool {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                try await operation()
                return true
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 300_000_000)
                }
            }
        }

        if let lastError {
            print("MediaSync failed [\(label)]: \(lastError.localizedDescription)")
        }
        return false
    }

    private func publishAvailability(for asset: MediaAssetDescriptor) {
        asset.invalidateCache?()
        if let notification = asset.availableNotification {
            NotificationCenter.default.post(name: notification, object: asset.notificationObject)
        }
    }

    // MARK: - Asset bundles

    @discardableResult
    func uploadBundle(_ bundle: MediaAssetBundle) async -> Bool {
        var succeeded = true
        for asset in assets(for: bundle) {
            let uploaded = await uploadAsset(asset)
            succeeded = succeeded && uploaded
        }
        return succeeded
    }

    @discardableResult
    func downloadBundleIfNeeded(_ bundle: MediaAssetBundle) async -> Bool {
        var succeeded = true
        for asset in assets(for: bundle) {
            let available = await downloadAssetIfNeeded(asset)
            succeeded = succeeded && available
        }
        return succeeded
    }

    @discardableResult
    func deleteBundle(_ bundle: MediaAssetBundle) async -> Bool {
        var succeeded = true
        for asset in assets(for: bundle) {
            let deleted = await deleteAsset(asset)
            succeeded = succeeded && deleted
        }
        return succeeded
    }

    // MARK: - Upload helpers

    @discardableResult
    private func uploadAsset(_ asset: MediaAssetDescriptor) async -> Bool {
        await uploadFile(
            localURL: asset.localURL,
            storagePath: asset.storagePath,
            contentType: asset.contentType
        )
    }

    /// Upload a local file to Supabase Storage. Skips if not connected.
    @discardableResult
    func uploadFile(localURL: URL, storagePath: String, contentType: String) async -> Bool {
        guard network.isConnected else { return false }

        let data: Data
        do {
            data = try await Task.detached(priority: .utility) {
                try Data(contentsOf: localURL)
            }.value
        } catch {
            print("⚠️ MediaSync: cannot read local file \(localURL.lastPathComponent)")
            return false
        }

        return await performWithRetry("upload \(storagePath)") {
            try await supabase.storage
                .from(bucket)
                .upload(storagePath, data: data, options: FileOptions(contentType: contentType, upsert: true))
        }
    }

    /// Upload raw Data directly (used when we already have data in memory).
    @discardableResult
    func uploadData(_ data: Data, storagePath: String, contentType: String) async -> Bool {
        guard network.isConnected else { return false }
        return await performWithRetry("upload \(storagePath)") {
            try await supabase.storage
                .from(bucket)
                .upload(storagePath, data: data, options: FileOptions(contentType: contentType, upsert: true))
        }
    }

    // MARK: - Download helpers

    @discardableResult
    private func downloadAssetIfNeeded(_ asset: MediaAssetDescriptor) async -> Bool {
        let available = await downloadFile(
            storagePath: asset.storagePath,
            destinationURL: asset.localURL
        )
        if available {
            publishAvailability(for: asset)
        }
        return available
    }

    /// Download a file from Storage and save to a local URL.
    /// Returns true if successful, false if skipped or failed.
    @discardableResult
    func downloadFile(storagePath: String, destinationURL: URL) async -> Bool {
        // Skip if already exists locally — no redundant downloads
        if FileManager.default.fileExists(atPath: destinationURL.path) { return true }
        guard network.isConnected else { return false }
        return await performWithRetry("download \(storagePath)") {
            let data = try await supabase.storage
                .from(bucket)
                .download(path: storagePath)
            try data.write(to: destinationURL)
        }
    }

    // MARK: - Delete from storage

    @discardableResult
    private func deleteAsset(_ asset: MediaAssetDescriptor) async -> Bool {
        await deleteFile(storagePath: asset.storagePath)
    }

    @discardableResult
    func deleteFile(storagePath: String) async -> Bool {
        guard network.isConnected else { return false }
        return await performWithRetry("delete \(storagePath)") {
            try await supabase.storage
                .from(bucket)
                .remove(paths: [storagePath])
        }
    }

}
