//
//  AudioStorageService.swift
//  Ponder
//

import Foundation
import AVFoundation

enum AudioStorageService {

    // MARK: - Directory
    static var audioDirectory: URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let dir = docs.appendingPathComponent("CanvasAudio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
        }
        return dir
    }

    // MARK: - Save from security-scoped URL (import)
    static func importAudio(from sourceURL: URL) throws -> (
        fileName: String,
        originalName: String,
        duration: Double
    ) {
        let ext = sourceURL.pathExtension.lowercased()
        let fileName = "\(UUID().uuidString).\(ext)"
        let destURL = audioDirectory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        let duration = audioDuration(url: destURL)
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        return (fileName, originalName, duration)
    }

    // MARK: - Save recorded file (already in temp dir)
    static func saveRecording(from tempURL: URL) throws -> (
        fileName: String,
        duration: Double
    ) {
        let fileName = "\(UUID().uuidString).m4a"
        let destURL = audioDirectory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: tempURL, to: destURL)
        let duration = audioDuration(url: destURL)
        return (fileName, duration)
    }

    // MARK: - Load
    static func url(for fileName: String) -> URL {
        audioDirectory.appendingPathComponent(fileName)
    }

    // MARK: - Delete
    static func delete(fileName: String) {
        let url = audioDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Duration
    static func audioDuration(url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        return CMTimeGetSeconds(duration)
    }
}
