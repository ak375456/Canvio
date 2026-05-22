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

@MainActor
final class MediaSyncService {

    static let shared = MediaSyncService()

    private let supabase  = SupabaseService.shared.client
    private let network   = NetworkMonitor.shared
    private let bucket    = "ponder-files"

    private init() {}

    // MARK: - Storage paths

    private func userID() -> String? {
        AuthService.shared.currentUser?.id.uuidString.lowercased()
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

    // MARK: - Upload helpers

    /// Upload a local file to Supabase Storage. Skips if not connected.
    func uploadFile(localURL: URL, storagePath: String, contentType: String) async {
        guard network.isConnected else { return }
        guard let data = try? Data(contentsOf: localURL) else {
            print("⚠️ MediaSync: cannot read local file \(localURL.lastPathComponent)")
            return
        }
        do {
            try await supabase.storage
                .from(bucket)
                .upload(storagePath, data: data, options: FileOptions(contentType: contentType, upsert: true))
        } catch {
            print("⚠️ MediaSync upload failed [\(storagePath)]: \(error.localizedDescription)")
        }
    }

    /// Upload raw Data directly (used when we already have data in memory).
    func uploadData(_ data: Data, storagePath: String, contentType: String) async {
        guard network.isConnected else { return }
        do {
            try await supabase.storage
                .from(bucket)
                .upload(storagePath, data: data, options: FileOptions(contentType: contentType, upsert: true))
        } catch {
            print("⚠️ MediaSync upload failed [\(storagePath)]: \(error.localizedDescription)")
        }
    }

    // MARK: - Download helpers

    /// Download a file from Storage and save to a local URL.
    /// Returns true if successful, false if skipped or failed.
    @discardableResult
    func downloadFile(storagePath: String, destinationURL: URL) async -> Bool {
        guard network.isConnected else { return false }
        // Skip if already exists locally — no redundant downloads
        if FileManager.default.fileExists(atPath: destinationURL.path) { return true }
        do {
            let data = try await supabase.storage
                .from(bucket)
                .download(path: storagePath)
            try data.write(to: destinationURL)
            return true
        } catch {
            print("⚠️ MediaSync download failed [\(storagePath)]: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Delete from storage

    func deleteFile(storagePath: String) async {
        guard network.isConnected else { return }
        do {
            try await supabase.storage
                .from(bucket)
                .remove(paths: [storagePath])
        } catch {
            print("⚠️ MediaSync delete failed [\(storagePath)]: \(error.localizedDescription)")
        }
    }

    // MARK: - Image convenience

    func uploadImage(fileName: String) async {
        let localURL = ImageStorageService.url(for: fileName)
        await uploadFile(localURL: localURL, storagePath: imagePath(for: fileName), contentType: "image/jpeg")
    }

    func downloadImageIfNeeded(fileName: String) async {
        let destURL = ImageStorageService.url(for: fileName)
        await downloadFile(storagePath: imagePath(for: fileName), destinationURL: destURL)
    }

    func deleteImage(fileName: String) async {
        await deleteFile(storagePath: imagePath(for: fileName))
    }

    // MARK: - PDF convenience

    func uploadPDF(pdfFileName: String, thumbnailFileName: String) async {
        let pdfURL   = PDFStorageService.pdfsDirectory.appendingPathComponent(pdfFileName)
        let thumbURL = PDFStorageService.thumbnailsDirectory.appendingPathComponent(thumbnailFileName)
        await uploadFile(localURL: pdfURL,   storagePath: pdfPath(for: pdfFileName),       contentType: "application/pdf")
        await uploadFile(localURL: thumbURL, storagePath: pdfThumbPath(for: thumbnailFileName), contentType: "image/jpeg")
    }

    func downloadPDFIfNeeded(pdfFileName: String, thumbnailFileName: String) async {
        let pdfDest   = PDFStorageService.pdfsDirectory.appendingPathComponent(pdfFileName)
        let thumbDest = PDFStorageService.thumbnailsDirectory.appendingPathComponent(thumbnailFileName)
        await downloadFile(storagePath: pdfPath(for: pdfFileName),           destinationURL: pdfDest)
        await downloadFile(storagePath: pdfThumbPath(for: thumbnailFileName), destinationURL: thumbDest)
    }

    func deletePDF(pdfFileName: String, thumbnailFileName: String) async {
        await deleteFile(storagePath: pdfPath(for: pdfFileName))
        await deleteFile(storagePath: pdfThumbPath(for: thumbnailFileName))
    }

    // MARK: - Audio convenience

    func uploadAudio(fileName: String) async {
        let localURL = AudioStorageService.url(for: fileName)
        let ext = (fileName as NSString).pathExtension.lowercased()
        let contentType = ext == "mp3" ? "audio/mpeg" : "audio/mp4"
        await uploadFile(localURL: localURL, storagePath: audioPath(for: fileName), contentType: contentType)
    }

    func downloadAudioIfNeeded(fileName: String) async {
        let destURL = AudioStorageService.url(for: fileName)
        await downloadFile(storagePath: audioPath(for: fileName), destinationURL: destURL)
    }

    func deleteAudio(fileName: String) async {
        await deleteFile(storagePath: audioPath(for: fileName))
    }
}
