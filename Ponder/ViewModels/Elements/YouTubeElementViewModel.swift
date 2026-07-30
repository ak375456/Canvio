//
//  YouTubeElementViewModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class YouTubeElementViewModel: ObservableObject {
    @Published var editingID: UUID? = nil
    @Published var activePlayingID: UUID? = nil
    @Published var stopPlaybackRequestID: UUID? = nil

    func addVideo(canvasID: UUID, urlString: String, title: String = "",
                  center: CGPoint, offset: CGSize, scale: CGFloat,
                  zIndex: Int, context: ModelContext,
                  undoManager: CanvasUndoManager? = nil) -> Bool {
        guard let videoID = Self.extractVideoID(from: urlString) else { return false }

        let canvasX = (center.x - offset.width) / scale
        let canvasY = (center.y - offset.height) / scale
        let element = YouTubeElementModel(
            canvasID: canvasID,
            videoID: videoID,
            originalURL: urlString,
            title: title,
            x: canvasX,
            y: canvasY
        )
        element.zIndex = zIndex
        context.insert(element)
        try? context.save()
        editingID = element.id

        Task { await YouTubeSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<YouTubeElementModel>()).first(where: { $0.id == id }) {
                    Task { await YouTubeSyncService.shared.delete(el) }
                    context.delete(el)
                    try? context.save()
                }
            },
            redo: {
                let el = YouTubeElementModel(
                    canvasID: canvasID,
                    videoID: videoID,
                    originalURL: urlString,
                    title: title,
                    x: canvasX,
                    y: canvasY
                )
                el.id = id
                el.zIndex = zIndex
                context.insert(el)
                try? context.save()
                Task { await YouTubeSyncService.shared.upsert(el) }
            }
        ))

        return true
    }

    func updatePosition(element: YouTubeElementModel, translation: CGSize,
                        boundary: CGSize = .zero, context: ModelContext,
                        undoManager: CanvasUndoManager? = nil) {
        let oldX = element.x
        let oldY = element.y
        let newX = element.x + Double(translation.width)
        let newY = element.y + Double(translation.height)
        let clamped = CanvasBoundaryHelper.clamp(
            x: newX,
            y: newY,
            boundary: boundary,
            elementSize: CGSize(width: element.width, height: element.height)
        )
        element.x = clamped.x
        element.y = clamped.y
        element.updatedAt = Date()
        try? context.save()
        Task { await YouTubeSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<YouTubeElementModel>()).first(where: { $0.id == id }) {
                    el.x = oldX
                    el.y = oldY
                    el.updatedAt = Date()
                    try? context.save()
                    Task { await YouTubeSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<YouTubeElementModel>()).first(where: { $0.id == id }) {
                    el.x = clamped.x
                    el.y = clamped.y
                    el.updatedAt = Date()
                    try? context.save()
                    Task { await YouTubeSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    func updateSize(element: YouTubeElementModel, width: Double, height: Double,
                    context: ModelContext, undoManager: CanvasUndoManager? = nil,
                    previousSize: CGSize? = nil) {
        let oldW = previousSize.map { Double($0.width) } ?? element.width
        let oldH = previousSize.map { Double($0.height) } ?? element.height
        element.width = max(180, min(960, width))
        element.height = max(120, min(720, height))
        element.updatedAt = Date()
        try? context.save()
        Task { await YouTubeSyncService.shared.upsert(element) }

        let id = element.id
        let newW = element.width
        let newH = element.height
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<YouTubeElementModel>()).first(where: { $0.id == id }) {
                    el.width = oldW
                    el.height = oldH
                    el.updatedAt = Date()
                    try? context.save()
                    Task { await YouTubeSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<YouTubeElementModel>()).first(where: { $0.id == id }) {
                    el.width = newW
                    el.height = newH
                    el.updatedAt = Date()
                    try? context.save()
                    Task { await YouTubeSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    @discardableResult
    func duplicate(element: YouTubeElementModel, zIndex: Int,
                   offset: CGSize = CGSize(width: 30, height: 30),
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) -> UUID? {
        let copy = YouTubeElementModel(
            canvasID: element.canvasID,
            videoID: element.videoID,
            originalURL: element.originalURL,
            title: element.title,
            thumbnailURL: element.thumbnailURL,
            x: element.x + Double(offset.width),
            y: element.y + Double(offset.height),
            width: element.width,
            height: element.height
        )
        copy.playbackSeconds = element.playbackSeconds
        copy.zIndex = zIndex
        context.insert(copy)
        try? context.save()
        Task { await YouTubeSyncService.shared.upsert(copy) }

        let id = copy.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<YouTubeElementModel>()).first(where: { $0.id == id }) {
                    Task { await YouTubeSyncService.shared.delete(el) }
                    context.delete(el)
                    try? context.save()
                }
            },
            redo: {
                let el = YouTubeElementModel(
                    canvasID: element.canvasID,
                    videoID: element.videoID,
                    originalURL: element.originalURL,
                    title: element.title,
                    thumbnailURL: element.thumbnailURL,
                    x: element.x + Double(offset.width),
                    y: element.y + Double(offset.height),
                    width: element.width,
                    height: element.height
                )
                el.id = id
                el.playbackSeconds = element.playbackSeconds
                el.zIndex = zIndex
                context.insert(el)
                try? context.save()
                Task { await YouTubeSyncService.shared.upsert(el) }
            }
        ))

        return id
    }

    func delete(element: YouTubeElementModel, context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snap = (
            id: element.id,
            canvasID: element.canvasID,
            videoID: element.videoID,
            originalURL: element.originalURL,
            title: element.title,
            thumbnailURL: element.thumbnailURL,
            x: element.x,
            y: element.y,
            width: element.width,
            height: element.height,
            playbackSeconds: element.playbackSeconds,
            zIndex: element.zIndex,
            groupID: element.groupID,
            isLayerHidden: element.isLayerHidden,
            layerOpacity: element.layerOpacity
        )

        Task { await YouTubeSyncService.shared.delete(element) }
        context.delete(element)
        try? context.save()
        if editingID == snap.id { editingID = nil }

        undoManager?.push(CanvasAction(
            name: "Delete YouTube video",
            undo: {
                let el = YouTubeElementModel(
                    canvasID: snap.canvasID,
                    videoID: snap.videoID,
                    originalURL: snap.originalURL,
                    title: snap.title,
                    thumbnailURL: snap.thumbnailURL,
                    x: snap.x,
                    y: snap.y,
                    width: snap.width,
                    height: snap.height
                )
                el.id = snap.id
                el.playbackSeconds = snap.playbackSeconds
                el.zIndex = snap.zIndex
                el.groupID = snap.groupID
                el.isLayerHidden = snap.isLayerHidden
                el.layerOpacity = snap.layerOpacity
                context.insert(el)
                try? context.save()
                Task { await YouTubeSyncService.shared.upsert(el) }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<YouTubeElementModel>()).first(where: { $0.id == snap.id }) {
                    Task { await YouTubeSyncService.shared.delete(el) }
                    context.delete(el)
                    try? context.save()
                }
            }
        ))
    }

    func stopEditing() { editingID = nil }

    func requestStopPlayback(for id: UUID) {
        stopPlaybackRequestID = id
    }

    func finishStopPlayback(for id: UUID, playbackSeconds: Double,
                            element: YouTubeElementModel, context: ModelContext) {
        element.playbackSeconds = max(0, playbackSeconds)
        element.updatedAt = Date()
        try? context.save()
        if activePlayingID == id { activePlayingID = nil }
        if stopPlaybackRequestID == id { stopPlaybackRequestID = nil }
    }

    static func extractVideoID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil {
            return trimmed
        }

        guard let url = URL(string: trimmed),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let host = (components.host ?? "").lowercased()
        let pathParts = components.path.split(separator: "/").map(String.init)

        if host.contains("youtu.be"), let first = pathParts.first {
            return validVideoID(first)
        }

        if let queryID = components.queryItems?.first(where: { $0.name == "v" })?.value,
           let valid = validVideoID(queryID) {
            return valid
        }

        if let shortsIndex = pathParts.firstIndex(of: "shorts"),
           pathParts.indices.contains(shortsIndex + 1) {
            return validVideoID(pathParts[shortsIndex + 1])
        }

        if let embedIndex = pathParts.firstIndex(of: "embed"),
           pathParts.indices.contains(embedIndex + 1) {
            return validVideoID(pathParts[embedIndex + 1])
        }

        return nil
    }

    private static func validVideoID(_ candidate: String) -> String? {
        let cleaned = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "?&/"))
        guard cleaned.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return cleaned
    }
}
