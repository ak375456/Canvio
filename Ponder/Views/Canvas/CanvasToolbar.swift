//
//  CanvasToolbar.swift
//  Ponder
//

import SwiftUI

struct CanvasToolbar: View {
    @Binding var showTextSheet: Bool
    let onAddSticky:    () -> Void
    let onAddTodo:      () -> Void
    let onAddShape:     () -> Void
    let onAddImage:     () -> Void
    let onAddPDF:       () -> Void
    let onAddTable:     () -> Void
    let onAddAudio:     () -> Void
    let onAddDrawing:   () -> Void
    let onDrawOnCanvas: () -> Void
    let onAddSymbol:    () -> Void          // ← NEW
    let onConnect:      () -> Void
    var isConnectModeActive: Bool = false
    let isVertical: Bool

    var body: some View {
        Group {
            if isVertical { verticalLayout } else { horizontalLayout }
        }
    }

    private var horizontalLayout: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                toolButton(icon: "textformat",           label: "Text",    tint: .blue)   { showTextSheet = true }
                toolButton(icon: "note.text",            label: "Sticky",  tint: .orange) { onAddSticky() }
                toolButton(icon: "checklist",            label: "Todo",    tint: .green)  { onAddTodo() }
                toolButton(icon: "square.on.circle",     label: "Shape",   tint: .purple) { onAddShape() }
                toolButton(icon: "photo",                label: "Image",   tint: .cyan)   { onAddImage() }
                toolButton(icon: "doc.richtext",         label: "PDF",     tint: .red)    { onAddPDF() }
                toolButton(icon: "tablecells",           label: "Table",   tint: .indigo) { onAddTable() }
                toolButton(icon: "waveform",             label: "Audio",   tint: .pink)   { onAddAudio() }
                toolButton(icon: "square.grid.2x2.fill", label: "Symbols", tint: .mint)   { onAddSymbol() }  // ← NEW
                #if os(iOS)
                toolButton(icon: "pencil.and.scribble",  label: "Drawing", tint: .orange) { onAddDrawing() }
                toolButton(icon: "scribble.variable",    label: "Draw",    tint: Color(red: 0.9, green: 0.5, blue: 0.1)) { onDrawOnCanvas() }
                #endif
                connectButton
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 64)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5), alignment: .top)
    }

    private var verticalLayout: some View {
        VStack(spacing: 0) {
            toolButton(icon: "textformat",           label: "Text",    tint: .blue)   { showTextSheet = true }
            toolButton(icon: "note.text",            label: "Sticky",  tint: .orange) { onAddSticky() }
            toolButton(icon: "checklist",            label: "Todo",    tint: .green)  { onAddTodo() }
            toolButton(icon: "square.on.circle",     label: "Shape",   tint: .purple) { onAddShape() }
            toolButton(icon: "photo",                label: "Image",   tint: .cyan)   { onAddImage() }
            toolButton(icon: "doc.richtext",         label: "PDF",     tint: .red)    { onAddPDF() }
            toolButton(icon: "tablecells",           label: "Table",   tint: .indigo) { onAddTable() }
            toolButton(icon: "waveform",             label: "Audio",   tint: .pink)   { onAddAudio() }
            toolButton(icon: "square.grid.2x2.fill", label: "Symbols", tint: .mint)   { onAddSymbol() }  // ← NEW
            #if os(iOS)
            toolButton(icon: "pencil.and.scribble",  label: "Drawing", tint: .orange) { onAddDrawing() }
            toolButton(icon: "scribble.variable",    label: "Draw",    tint: Color(red: 0.9, green: 0.5, blue: 0.1)) { onDrawOnCanvas() }
            #endif
            connectButton
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private var connectButton: some View {
        Button(action: onConnect) {
            VStack(spacing: 5) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(isConnectModeActive ? Color.white : Color.accentColor)
                    .frame(width: 28, height: 28)
                Text("Connect")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isConnectModeActive ? Color.white : Color.secondary)
            }
            .frame(width: 66, height: 56)
            .background(isConnectModeActive ? Color.accentColor : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isConnectModeActive)
    }

    private func toolButton(icon: String, label: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 66, height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
