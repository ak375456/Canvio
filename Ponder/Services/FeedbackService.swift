//
//  FeedbackService.swift
//  Canvio
//

import Foundation
import Supabase
import Auth

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum AppFeedbackCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case improvement
    case bug
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .improvement: return "Improvement"
        case .bug: return "Bug"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .improvement: return "lightbulb"
        case .bug: return "ladybug"
        case .other: return "ellipsis.bubble"
        }
    }
}

struct AppFeedbackAttachment: Sendable {
    let data: Data
    let contentType: String
    let fileExtension: String
}

enum FeedbackSubmissionError: LocalizedError {
    case imageTooLarge
    case uploadFailed
    case submissionFailed

    var errorDescription: String? {
        switch self {
        case .imageTooLarge:
            return "The selected image is larger than 8 MB. Please choose a smaller image."
        case .uploadFailed:
            return "The image could not be uploaded. Please check your connection and try again."
        case .submissionFailed:
            return "Your feedback could not be sent. Please check your connection and try again."
        }
    }
}

private struct AppFeedbackRow: Encodable {
    let id: String
    let category: String
    let message: String
    let image_path: String?
    let platform: String
    let app_version: String
    let build_number: String
    let os_version: String
    let device_model: String
}

/// Keeps the feedback client separate from Canvio account authentication.
/// This prevents a signed-in account token from being attached to feedback requests.
private final class EphemeralFeedbackAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

final class FeedbackService: @unchecked Sendable {
    static let shared = FeedbackService()

    static let maximumImageBytes = 8 * 1024 * 1024

    private let bucket = "feedback-images"
    private let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseService.projectURL,
            supabaseKey: SupabaseService.publishableKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: EphemeralFeedbackAuthStorage(),
                    autoRefreshToken: false,
                    emitLocalSessionAsInitialSession: false
                )
            )
        )
    }

    func submit(
        category: AppFeedbackCategory,
        message: String,
        attachment: AppFeedbackAttachment?
    ) async throws {
        if let attachment, attachment.data.count > Self.maximumImageBytes {
            throw FeedbackSubmissionError.imageTooLarge
        }

        let feedbackID = UUID().uuidString.lowercased()
        var imagePath: String?

        if let attachment {
            let safeExtension = attachment.fileExtension == "png" ? "png" : "jpg"
            let path = "submissions/\(feedbackID)/attachment.\(safeExtension)"

            do {
                try await client.storage
                    .from(bucket)
                    .upload(
                        path,
                        data: attachment.data,
                        options: FileOptions(
                            contentType: attachment.contentType,
                            upsert: false
                        )
                    )
                imagePath = path
            } catch {
                print("⚠️ Feedback image upload failed: \(error.localizedDescription)")
                throw FeedbackSubmissionError.uploadFailed
            }
        }

        let info = Bundle.main.infoDictionary
        let row = AppFeedbackRow(
            id: feedbackID,
            category: category.rawValue,
            message: message,
            image_path: imagePath,
            platform: Self.platformName,
            app_version: info?["CFBundleShortVersionString"] as? String ?? "Unknown",
            build_number: info?["CFBundleVersion"] as? String ?? "Unknown",
            os_version: ProcessInfo.processInfo.operatingSystemVersionString,
            device_model: Self.deviceModel
        )

        do {
            try await client
                .from("app_feedback")
                .insert(row)
                .execute()
        } catch {
            print("⚠️ Feedback submission failed: \(error.localizedDescription)")
            throw FeedbackSubmissionError.submissionFailed
        }
    }

    private static var platformName: String {
        #if os(iOS)
        return "iOS/iPadOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "Apple platform"
        #endif
    }

    private static var deviceModel: String {
        #if canImport(UIKit)
        return UIDevice.current.model
        #elseif canImport(AppKit)
        return "Mac"
        #else
        return "Unknown"
        #endif
    }
}
