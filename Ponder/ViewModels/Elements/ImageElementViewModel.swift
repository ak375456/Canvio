//
//  ImageElementViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import Combine

@MainActor
class ImageElementViewModel: ObservableObject {
    @Published var editingID: UUID? = nil

    func addImage(canvasID: UUID, imageData: Data, center: CGPoint,
                  offset: CGSize, scale: CGFloat, zIndex: Int,
                  context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        do {
            let filename = try ImageStorageService.save(data: imageData)
            let canvasX = (center.x - offset.width) / scale
            let canvasY = (center.y - offset.height) / scale
            var width: Double = 240, height: Double = 180
            if let img = ImageStorageService.load(fileName: filename) {
                let s = img.size
                let aspect = s.width / max(1, s.height)
                if aspect > 1 { width = 240; height = 240 / aspect }
                else          { height = 240; width = 240 * aspect }
            }
            let element = ImageElementModel(canvasID: canvasID, imageFileName: filename,
                                            x: canvasX, y: canvasY, width: width, height: height)
            element.zIndex = zIndex
            context.insert(element); try? context.save()
            editingID = element.id

            Task { await ImageSyncService.shared.upsert(element, uploadFile: true) }

            let id = element.id
            undoManager?.push(CanvasAction(
                undo: {
                    if let el = try? context.fetch(FetchDescriptor<ImageElementModel>()).first(where: { $0.id == id }) {
                        Task { await ImageSyncService.shared.delete(el) }
                        context.delete(el); try? context.save()
                    }
                },
                redo: {
                    let el = ImageElementModel(canvasID: canvasID, imageFileName: filename,
                                               x: canvasX, y: canvasY, width: width, height: height)
                    el.id = id; el.zIndex = zIndex
                    context.insert(el); try? context.save()
                    Task { await ImageSyncService.shared.upsert(el, uploadFile: true) }
                }
            ))
        } catch { print("⚠️ Failed to save image: \(error)") }
    }

    func updatePosition(element: ImageElementModel, translation: CGSize,
                        scale: CGFloat = 1, boundary: CGSize = .zero,
                        context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldX = element.x, oldY = element.y
        let newX = element.x + Double(translation.width)
        let newY = element.y + Double(translation.height)
        let clamped = CanvasBoundaryHelper.clamp(x: newX, y: newY, boundary: boundary,
                                                  elementSize: CGSize(width: element.width, height: element.height))
        element.x = clamped.x; element.y = clamped.y
        element.updatedAt = Date(); try? context.save()
        Task { await ImageSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<ImageElementModel>()).first(where: { $0.id == id }) {
                    el.x = oldX; el.y = oldY; el.updatedAt = Date(); try? context.save()
                    Task { await ImageSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<ImageElementModel>()).first(where: { $0.id == id }) {
                    el.x = clamped.x; el.y = clamped.y; el.updatedAt = Date(); try? context.save()
                    Task { await ImageSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    func duplicate(element: ImageElementModel, zIndex: Int,
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let newFileName: String
        do {
            let srcURL = ImageStorageService.url(for: element.imageFileName)
            let ext = srcURL.pathExtension
            let newName = "\(UUID().uuidString).\(ext)"
            let destURL = ImageStorageService.imagesDirectory.appendingPathComponent(newName)
            try FileManager.default.copyItem(at: srcURL, to: destURL)
            newFileName = newName
        } catch {
            print("⚠️ Failed to copy image for duplicate: \(error)")
            return
        }
        let copy = ImageElementModel(canvasID: element.canvasID, imageFileName: newFileName,
                                     x: element.x + 30, y: element.y + 30,
                                     width: element.width, height: element.height)
        copy.cornerRadius = element.cornerRadius; copy.opacity = element.opacity
        copy.zIndex = zIndex
        context.insert(copy); try? context.save()
        Task { await ImageSyncService.shared.upsert(copy, uploadFile: true) }

        let id = copy.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<ImageElementModel>()).first(where: { $0.id == id }) {
                    Task { await ImageSyncService.shared.delete(el) }
                    ImageStorageService.delete(fileName: el.imageFileName)
                    context.delete(el); try? context.save()
                }
            },
            redo: {
                let el = ImageElementModel(canvasID: element.canvasID, imageFileName: newFileName,
                                           x: element.x + 30, y: element.y + 30,
                                           width: element.width, height: element.height)
                el.id = id; el.zIndex = zIndex
                context.insert(el); try? context.save()
                Task { await ImageSyncService.shared.upsert(el, uploadFile: true) }
            }
        ))
    }

    func updateSize(element: ImageElementModel, width: Double, height: Double,
                    context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldW = element.width, oldH = element.height
        element.width = max(40, min(1200, width)); element.height = max(40, min(1200, height))
        element.updatedAt = Date(); try? context.save()
        Task { await ImageSyncService.shared.upsert(element) }

        let id = element.id; let newW = element.width, newH = element.height
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<ImageElementModel>()).first(where: { $0.id == id }) {
                    el.width = oldW; el.height = oldH; el.updatedAt = Date(); try? context.save()
                    Task { await ImageSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<ImageElementModel>()).first(where: { $0.id == id }) {
                    el.width = newW; el.height = newH; el.updatedAt = Date(); try? context.save()
                    Task { await ImageSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    func delete(element: ImageElementModel, context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snap = (id: element.id, canvasID: element.canvasID,
                    fileName: element.imageFileName,
                    x: element.x, y: element.y, width: element.width,
                    height: element.height, zIndex: element.zIndex)

        Task { await ImageSyncService.shared.delete(element) }
        context.delete(element); try? context.save()
        if editingID == snap.id { editingID = nil }

        undoManager?.push(CanvasAction(
            undo: {
                let el = ImageElementModel(canvasID: snap.canvasID, imageFileName: snap.fileName,
                                           x: snap.x, y: snap.y, width: snap.width, height: snap.height)
                el.id = snap.id; el.zIndex = snap.zIndex
                context.insert(el); try? context.save()
                Task { await ImageSyncService.shared.upsert(el, uploadFile: true) }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<ImageElementModel>()).first(where: { $0.id == snap.id }) {
                    Task { await ImageSyncService.shared.delete(el) }
                    ImageStorageService.delete(fileName: snap.fileName)
                    context.delete(el); try? context.save()
                }
            }
        ))
    }

    func stopEditing() { editingID = nil }
}
