//
//  AudioElementViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import Combine

@MainActor
class AudioElementViewModel: ObservableObject {
    @Published var editingID: UUID? = nil

    func addAudio(canvasID: UUID, audioFileName: String, originalName: String,
                  duration: Double, center: CGPoint, offset: CGSize, scale: CGFloat,
                  zIndex: Int, context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let canvasX = (center.x - offset.width) / scale
        let canvasY = (center.y - offset.height) / scale
        let element = AudioElementModel(canvasID: canvasID, audioFileName: audioFileName,
                                        originalName: originalName, duration: duration,
                                        x: canvasX, y: canvasY)
        element.zIndex = zIndex
        context.insert(element); try? context.save()
        editingID = element.id

        Task { await AudioSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<AudioElementModel>()).first(where: { $0.id == id }) {
                    Task { await AudioSyncService.shared.delete(el) }
                    context.delete(el); try? context.save()
                }
            },
            redo: {
                let el = AudioElementModel(canvasID: canvasID, audioFileName: audioFileName,
                                           originalName: originalName, duration: duration,
                                           x: canvasX, y: canvasY)
                el.id = id; el.zIndex = zIndex
                context.insert(el); try? context.save()
                Task { await AudioSyncService.shared.upsert(el) }
            }
        ))
    }

    func updatePosition(element: AudioElementModel, translation: CGSize,
                        scale: CGFloat = 1, boundary: CGSize = .zero,
                        context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldX = element.x, oldY = element.y
        let newX = element.x + Double(translation.width)
        let newY = element.y + Double(translation.height)
        let clamped = CanvasBoundaryHelper.clamp(x: newX, y: newY, boundary: boundary,
                                                  elementSize: CGSize(width: element.width, height: element.height))
        element.x = clamped.x; element.y = clamped.y
        element.updatedAt = Date(); try? context.save()
        Task { await AudioSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<AudioElementModel>()).first(where: { $0.id == id }) {
                    el.x = oldX; el.y = oldY; el.updatedAt = Date(); try? context.save()
                    Task { await AudioSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<AudioElementModel>()).first(where: { $0.id == id }) {
                    el.x = clamped.x; el.y = clamped.y; el.updatedAt = Date(); try? context.save()
                    Task { await AudioSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    func duplicate(element: AudioElementModel, zIndex: Int,
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let srcURL = AudioStorageService.url(for: element.audioFileName)
        let ext = srcURL.pathExtension
        let newFileName = "\(UUID().uuidString).\(ext)"
        let destURL = AudioStorageService.audioDirectory.appendingPathComponent(newFileName)
        do { try FileManager.default.copyItem(at: srcURL, to: destURL) }
        catch { print("⚠️ Failed to copy audio: \(error)"); return }

        let copy = AudioElementModel(canvasID: element.canvasID, audioFileName: newFileName,
                                     originalName: element.originalName, duration: element.duration,
                                     x: element.x + 30, y: element.y + 30)
        copy.zIndex = zIndex
        context.insert(copy); try? context.save()
        Task { await AudioSyncService.shared.upsert(copy) }

        let id = copy.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<AudioElementModel>()).first(where: { $0.id == id }) {
                    Task { await AudioSyncService.shared.delete(el) }
                    AudioStorageService.delete(fileName: newFileName)
                    context.delete(el); try? context.save()
                }
            },
            redo: {
                let el = AudioElementModel(canvasID: element.canvasID, audioFileName: newFileName,
                                           originalName: element.originalName, duration: element.duration,
                                           x: element.x + 30, y: element.y + 30)
                el.id = id; el.zIndex = zIndex
                context.insert(el); try? context.save()
                Task { await AudioSyncService.shared.upsert(el) }
            }
        ))
    }

    func delete(element: AudioElementModel, context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snap = (id: element.id, canvasID: element.canvasID,
                    audioFileName: element.audioFileName, originalName: element.originalName,
                    duration: element.duration, x: element.x, y: element.y, zIndex: element.zIndex)

        Task { await AudioSyncService.shared.delete(element) }
        context.delete(element); try? context.save()
        if editingID == snap.id { editingID = nil }

        undoManager?.push(CanvasAction(
            undo: {
                let el = AudioElementModel(canvasID: snap.canvasID, audioFileName: snap.audioFileName,
                                           originalName: snap.originalName, duration: snap.duration,
                                           x: snap.x, y: snap.y)
                el.id = snap.id; el.zIndex = snap.zIndex
                context.insert(el); try? context.save()
                Task { await AudioSyncService.shared.upsert(el) }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<AudioElementModel>()).first(where: { $0.id == snap.id }) {
                    Task { await AudioSyncService.shared.delete(el) }
                    AudioStorageService.delete(fileName: snap.audioFileName)
                    context.delete(el); try? context.save()
                }
            }
        ))
    }

    func stopEditing() { editingID = nil }
}
