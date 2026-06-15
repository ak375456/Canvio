//
//  HomeViewModel.swift
//  Ponder
//

import Foundation
import Combine
import SwiftData
import SwiftUI

@MainActor
class HomeViewModel: ObservableObject {
    @Published var showCreateSheet = false
    @Published var newCanvasName = ""
    @Published var newCanvasIconName = "doc.text"
    @Published var newCanvasIconColor = "blue"
    @Published var selectedCanvasForRename: CanvasModel? = nil
    @Published var renameText = ""

    @Published var selectedCanvasSize: CanvasSize = .infinite
    @Published var customWidth:  String = "800"
    @Published var customHeight: String = "600"

    let iconOptions: [CanvasIcon] = [
        CanvasIcon(symbol: "doc.text",         color: "blue"),
        CanvasIcon(symbol: "note.text",        color: "orange"),
        CanvasIcon(symbol: "book.closed",      color: "green"),
        CanvasIcon(symbol: "brain",            color: "purple"),
        CanvasIcon(symbol: "paintbrush",       color: "pink"),
        CanvasIcon(symbol: "chart.bar",        color: "indigo"),
        CanvasIcon(symbol: "map",              color: "teal"),
        CanvasIcon(symbol: "lightbulb",        color: "yellow"),
        CanvasIcon(symbol: "graduationcap",    color: "red"),
        CanvasIcon(symbol: "folder",           color: "brown"),
        CanvasIcon(symbol: "star",             color: "orange"),
        CanvasIcon(symbol: "heart",            color: "pink"),
    ]

    // MARK: - Create

    func createCanvas(context: ModelContext) {
        let trimmed = newCanvasName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let w = Double(customWidth)  ?? 800
        let h = Double(customHeight) ?? 600

        let canvas = CanvasModel(
            name:         trimmed,
            iconName:     newCanvasIconName,
            iconColor:    newCanvasIconColor,
            canvasSize:   selectedCanvasSize,
            customWidth:  w,
            customHeight: h
        )
        context.insert(canvas)

        let pageSize = canvas.defaultPageSize
        let firstPage = CanvasPageModel(
            canvasID: canvas.id,
            contentCanvasID: canvas.id,
            name: "Page 1",
            width: pageSize.width,
            height: pageSize.height
        )
        context.insert(firstPage)
        try? context.save()

        // Sync to Supabase in the background — doesn't block the UI
        Task {
            await CanvasSyncService.shared.upsert(canvas)
            await CanvasPageSyncService.shared.upsert(firstPage)
        }

        showCreateSheet = false
        resetForm()
    }

    // MARK: - Delete

    func deleteCanvas(canvas: CanvasModel, context: ModelContext) {
        // Soft-delete on Supabase first (before local delete so we still have the ID)
        Task { await CanvasSyncService.shared.delete(canvas) }

        context.delete(canvas)
        try? context.save()
    }

    // MARK: - Rename

    func renameCanvas(canvas: CanvasModel, newName: String, context: ModelContext) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        canvas.name      = trimmed
        canvas.updatedAt = Date()   // bump updatedAt for conflict resolution
        try? context.save()

        // Sync the rename to Supabase
        Task { await CanvasSyncService.shared.upsert(canvas) }
    }

    // MARK: - Form helpers

    func resetForm() {
        newCanvasName      = ""
        newCanvasIconName  = "doc.text"
        newCanvasIconColor = "blue"
        selectedCanvasSize = .infinite
        customWidth        = "800"
        customHeight       = "600"
    }

    func colorFromString(_ string: String) -> Color {
        switch string {
        case "blue":   return .blue
        case "orange": return .orange
        case "green":  return .green
        case "purple": return .purple
        case "pink":   return .pink
        case "indigo": return .indigo
        case "teal":   return .teal
        case "yellow": return .yellow
        case "red":    return .red
        case "brown":  return .brown
        default:       return .blue
        }
    }
}

struct CanvasIcon: Identifiable {
    let id     = UUID()
    let symbol: String
    let color:  String
}
