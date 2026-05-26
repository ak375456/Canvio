//
//  PDFElementViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import Combine

@MainActor
class PDFElementViewModel: ObservableObject {
    @Published var editingID: UUID? = nil

    func addPDF(canvasID: UUID, sourceURL: URL, center: CGPoint,
                offset: CGSize, scale: CGFloat, zIndex: Int,
                context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
        do {
            let result = try PDFStorageService.importPDF(from: sourceURL)
            let canvasX = (center.x - offset.width) / scale
            let canvasY = (center.y - offset.height) / scale
            let element = PDFElementModel(canvasID: canvasID,
                                          pdfFileName: result.pdfFileName,
                                          thumbnailFileName: result.thumbnailFileName,
                                          originalName: result.originalName,
                                          pageCount: result.pageCount,
                                          x: canvasX, y: canvasY)
            element.zIndex = zIndex
            context.insert(element); try? context.save()
            editingID = element.id

            Task { await PDFSyncService.shared.upsert(element) }

            let id = element.id
            undoManager?.push(CanvasAction(
                undo: {
                    if let el = try? context.fetch(FetchDescriptor<PDFElementModel>()).first(where: { $0.id == id }) {
                        Task { await PDFSyncService.shared.delete(el) }
                        context.delete(el); try? context.save()
                    }
                },
                redo: {
                    let el = PDFElementModel(canvasID: canvasID,
                                             pdfFileName: result.pdfFileName,
                                             thumbnailFileName: result.thumbnailFileName,
                                             originalName: result.originalName,
                                             pageCount: result.pageCount,
                                             x: canvasX, y: canvasY)
                    el.id = id; el.zIndex = zIndex
                    context.insert(el); try? context.save()
                    Task { await PDFSyncService.shared.upsert(el) }
                }
            ))
        } catch { print("⚠️ Failed to import PDF: \(error)") }
    }

    func updatePosition(element: PDFElementModel, translation: CGSize,
                        scale: CGFloat = 1, boundary: CGSize = .zero,
                        context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldX = element.x, oldY = element.y
        let newX = element.x + Double(translation.width)
        let newY = element.y + Double(translation.height)
        let clamped = CanvasBoundaryHelper.clamp(x: newX, y: newY, boundary: boundary,
                                                  elementSize: CGSize(width: element.width, height: element.height))
        element.x = clamped.x; element.y = clamped.y
        element.updatedAt = Date(); try? context.save()
        Task { await PDFSyncService.shared.upsert(element) }

        let id = element.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<PDFElementModel>()).first(where: { $0.id == id }) {
                    el.x = oldX; el.y = oldY; el.updatedAt = Date(); try? context.save()
                    Task { await PDFSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<PDFElementModel>()).first(where: { $0.id == id }) {
                    el.x = clamped.x; el.y = clamped.y; el.updatedAt = Date(); try? context.save()
                    Task { await PDFSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    @discardableResult
    func duplicate(element: PDFElementModel, zIndex: Int,
                   offset: CGSize = CGSize(width: 30, height: 30),
                   context: ModelContext, undoManager: CanvasUndoManager? = nil) -> UUID? {
        let newPDFName   = "\(UUID().uuidString).pdf"
        let newThumbName = newPDFName.replacingOccurrences(of: ".pdf", with: "_thumb.jpg")
        do {
            try FileManager.default.copyItem(
                at: PDFStorageService.pdfsDirectory.appendingPathComponent(element.pdfFileName),
                to: PDFStorageService.pdfsDirectory.appendingPathComponent(newPDFName))
            try FileManager.default.copyItem(
                at: PDFStorageService.thumbnailsDirectory.appendingPathComponent(element.thumbnailFileName),
                to: PDFStorageService.thumbnailsDirectory.appendingPathComponent(newThumbName))
        } catch { print("⚠️ Failed to copy PDF for duplicate: \(error)"); return nil }

        let copy = PDFElementModel(canvasID: element.canvasID,
                                   pdfFileName: newPDFName, thumbnailFileName: newThumbName,
                                   originalName: element.originalName, pageCount: element.pageCount,
                                   x: element.x + Double(offset.width),
                                   y: element.y + Double(offset.height))
        copy.width = element.width; copy.height = element.height; copy.zIndex = zIndex
        context.insert(copy); try? context.save()
        Task { await PDFSyncService.shared.upsert(copy) }

        let id = copy.id
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<PDFElementModel>()).first(where: { $0.id == id }) {
                    Task { await PDFSyncService.shared.delete(el) }
                    PDFStorageService.delete(pdfFileName: newPDFName, thumbnailFileName: newThumbName)
                    context.delete(el); try? context.save()
                }
            },
            redo: {
                let el = PDFElementModel(canvasID: element.canvasID,
                                         pdfFileName: newPDFName, thumbnailFileName: newThumbName,
                                         originalName: element.originalName, pageCount: element.pageCount,
                                         x: element.x + Double(offset.width),
                                         y: element.y + Double(offset.height))
                el.id = id; el.zIndex = zIndex
                context.insert(el); try? context.save()
                Task { await PDFSyncService.shared.upsert(el) }
            }
        ))
        return id
    }

    func updateSize(element: PDFElementModel, width: Double, height: Double,
                    context: ModelContext, undoManager: CanvasUndoManager? = nil) {
        let oldW = element.width, oldH = element.height
        element.width = max(120, min(800, width)); element.height = max(120, min(800, height))
        element.updatedAt = Date(); try? context.save()
        Task { await PDFSyncService.shared.upsert(element) }

        let id = element.id; let newW = element.width, newH = element.height
        undoManager?.push(CanvasAction(
            undo: {
                if let el = try? context.fetch(FetchDescriptor<PDFElementModel>()).first(where: { $0.id == id }) {
                    el.width = oldW; el.height = oldH; el.updatedAt = Date(); try? context.save()
                    Task { await PDFSyncService.shared.upsert(el) }
                }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<PDFElementModel>()).first(where: { $0.id == id }) {
                    el.width = newW; el.height = newH; el.updatedAt = Date(); try? context.save()
                    Task { await PDFSyncService.shared.upsert(el) }
                }
            }
        ))
    }

    func delete(element: PDFElementModel, context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snap = (id: element.id, canvasID: element.canvasID,
                    pdfFileName: element.pdfFileName, thumbFileName: element.thumbnailFileName,
                    originalName: element.originalName, pageCount: element.pageCount,
                    x: element.x, y: element.y, width: element.width,
                    height: element.height, zIndex: element.zIndex)

        Task { await PDFSyncService.shared.delete(element) }
        context.delete(element); try? context.save()
        if editingID == snap.id { editingID = nil }

        undoManager?.push(CanvasAction(
            undo: {
                let el = PDFElementModel(canvasID: snap.canvasID,
                                         pdfFileName: snap.pdfFileName,
                                         thumbnailFileName: snap.thumbFileName,
                                         originalName: snap.originalName,
                                         pageCount: snap.pageCount,
                                         x: snap.x, y: snap.y)
                el.id = snap.id; el.width = snap.width; el.height = snap.height
                el.zIndex = snap.zIndex
                context.insert(el); try? context.save()
                Task { await PDFSyncService.shared.upsert(el) }
            },
            redo: {
                if let el = try? context.fetch(FetchDescriptor<PDFElementModel>()).first(where: { $0.id == snap.id }) {
                    Task { await PDFSyncService.shared.delete(el) }
                    PDFStorageService.delete(pdfFileName: snap.pdfFileName, thumbnailFileName: snap.thumbFileName)
                    context.delete(el); try? context.save()
                }
            }
        ))
    }

    func stopEditing() { editingID = nil }
}
