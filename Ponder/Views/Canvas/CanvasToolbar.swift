//
//  CanvasToolbar.swift
//  Ponder
//

import SwiftUI

struct CanvasToolbar: View {
    @Binding var showTextSheet: Bool
    let onAddSticky:    () -> Void
    let onAddTodo:      () -> Void
    let onAddTemplate:  () -> Void
    let onAddShape:     () -> Void
    let onAddImage:     () -> Void
    let onScanOCR:      () -> Void
    let onScanDocument: () -> Void
    let onAddPDF:       () -> Void
    let onAddTable:     () -> Void
    let onAddAudio:     () -> Void
    let onAddYouTube:   () -> Void
    let onAddDrawing:   () -> Void
    let onDrawOnCanvas: () -> Void
    let onWriteTextOnCanvas: () -> Void
    let onAddSymbol:    () -> Void          // ← NEW
    let onConnect:      () -> Void
    var isConnectModeActive: Bool = false
    var showsWriteTextTool = false
    var lockedTools: Set<CanvasTool> = []
    let isVertical: Bool

    @State private var isCollapsed = false

    var body: some View {
        Group {
            if isCollapsed {
                collapsedLayout
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
            } else if isVertical {
                verticalLayout
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            } else {
                horizontalLayout
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isCollapsed)
    }

    private var horizontalLayout: some View {
        HStack(alignment: .center, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    toolbarItems
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(height: 78, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(height: 78, alignment: .center)

            Divider()
                .frame(height: 48)
                .padding(.horizontal, 4)

            collapseButton(systemImage: "chevron.down")
                .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 12)
    }

    private var verticalLayout: some View {
        VStack(spacing: 2) {
            toolbarItems

            Divider()
                .padding(.horizontal, 10)

            collapseButton(systemImage: isVertical ? "chevron.left" : "chevron.down")
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 8)
    }

    @ViewBuilder
    private var collapsedLayout: some View {
        if isVertical {
            collapsedButton
        } else {
            collapsedButton
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var toolbarItems: some View {
        toolButton(icon: "textformat",           label: "Text",    tint: .blue)   { showTextSheet = true }
        toolButton(icon: "note.text",            label: "Sticky",  tint: .orange) { onAddSticky() }
        toolButton(icon: "checklist",            label: "Todo",    tint: .green)  { onAddTodo() }
        toolButton(icon: "square.grid.2x2",      label: "Templates", tint: .indigo) { onAddTemplate() }
        toolButton(icon: "square.on.circle",     label: "Shape",   tint: .purple) { onAddShape() }
        toolButton(icon: "photo",                label: "Image",   tint: .cyan, isLocked: lockedTools.contains(.image))   { onAddImage() }
        #if os(iOS)
        toolButton(icon: "doc.text.viewfinder",  label: "OCR",     tint: .teal)   { onScanOCR() }
        toolButton(icon: "doc.viewfinder",       label: "Scan",    tint: .red)    { onScanDocument() }
        #endif
        toolButton(icon: "doc.richtext",         label: "PDF",     tint: .red)    { onAddPDF() }
        toolButton(icon: "tablecells",           label: "Table",   tint: .indigo, isLocked: lockedTools.contains(.table)) { onAddTable() }
        toolButton(icon: "waveform",             label: "Audio",   tint: .pink, isLocked: lockedTools.contains(.audio))   { onAddAudio() }
        toolButton(icon: "play.rectangle.fill",  label: "YouTube", tint: .red)    { onAddYouTube() }
        toolButton(icon: "square.grid.2x2.fill", label: "Symbols", tint: .mint)   { onAddSymbol() }
        toolButton(icon: "pencil.and.scribble",  label: "Drawing", tint: .orange) { onAddDrawing() }
        toolButton(icon: "scribble.variable",    label: "Draw",    tint: Color(red: 0.9, green: 0.5, blue: 0.1)) {
            onDrawOnCanvas()
        }
        #if os(iOS)
        if showsWriteTextTool {
            toolButton(icon: "textformat.abc.dottedunderline", label: "Write", tint: .blue) {
                onWriteTextOnCanvas()
            }
        }
        #endif
        connectButton
    }

    private var collapsedButton: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isCollapsed = false
            }
        } label: {
            Image(systemName: isVertical ? "chevron.right" : "chevron.up")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 58, height: 58)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expand toolbar")
    }

    private func collapseButton(systemImage: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isCollapsed = true
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.primary)
                .frame(width: 52, height: 56)
                .background(Color.primary.opacity(0.06), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Collapse toolbar")
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
                            isLocked: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(tint)
                        .frame(width: 28, height: 28)
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .opacity(isLocked ? 0.42 : 1)

                if isLocked {
                    lockedScrim(cornerRadius: 10)
                    lockBadge(size: 22, iconSize: 10)
                        .offset(x: -4, y: 3)
                }
            }
            .frame(width: 66, height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLocked ? "\(label), Pro required" : label)
    }

    private func lockedScrim(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.black.opacity(0.34))
    }

    private func lockBadge(size: CGFloat, iconSize: CGFloat) -> some View {
        Image(systemName: "lock.fill")
            .font(.system(size: iconSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.black.opacity(0.78), in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.34), lineWidth: 0.7))
    }
}

struct CompactCanvasToolbar: View {
    @Binding var showTextSheet: Bool
    let onAddSticky:    () -> Void
    let onAddTodo:      () -> Void
    let onAddTemplate:  () -> Void
    let onAddShape:     () -> Void
    let onAddImage:     () -> Void
    let onScanOCR:      () -> Void
    let onScanDocument: () -> Void
    let onAddPDF:       () -> Void
    let onAddTable:     () -> Void
    let onAddAudio:     () -> Void
    let onAddYouTube:   () -> Void
    let onAddDrawing:   () -> Void
    let onDrawOnCanvas: () -> Void
    let onWriteTextOnCanvas: () -> Void
    let onAddSymbol:    () -> Void
    let onConnect:      () -> Void
    var isConnectModeActive: Bool = false
    var showsWriteTextTool = false
    var lockedTools: Set<CanvasTool> = []

    @State private var isCollapsed = false

    private let buttonSize: CGFloat = 42
    private let buttonCornerRadius: CGFloat = 11

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if !isCollapsed {
                    sideButtons(
                        safeTop: geo.safeAreaInsets.top,
                        safeBottom: geo.safeAreaInsets.bottom,
                        height: geo.size.height
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transition(verticalButtonsTransition)
                }

                bottomControls(safeBottom: geo.safeAreaInsets.bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isCollapsed)
        }
    }

    private var horizontalButtonsTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)),
            removal: .move(edge: .trailing).combined(with: .scale(scale: 0.96, anchor: .bottomTrailing))
        )
    }

    private var verticalButtonsTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)),
            removal: .move(edge: .bottom).combined(with: .scale(scale: 0.96, anchor: .bottomTrailing))
        )
    }

    private func bottomControls(safeBottom: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if !isCollapsed {
                bottomButtons
                    .transition(horizontalButtonsTransition)
            } else {
                Spacer(minLength: 0)
            }

            compactCollapseButton(
                icon: isCollapsed ? "chevron.up" : "chevron.down",
                label: isCollapsed ? "Expand toolbar" : "Collapse toolbar"
            ) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    isCollapsed.toggle()
                }
            }
            .layoutPriority(1)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.bottom, max(safeBottom, 8) + 8)
    }

    private var bottomButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                compactButton(icon: "textformat", label: "Text", tint: .blue) { showTextSheet = true }
                compactButton(icon: "note.text", label: "Sticky Note", tint: .orange, action: onAddSticky)
                compactButton(icon: "checklist", label: "Todo List", tint: .green, action: onAddTodo)
                compactButton(icon: "square.grid.2x2", label: "Templates", tint: .indigo, action: onAddTemplate)
                compactButton(icon: "square.on.circle", label: "Shape", tint: .purple, action: onAddShape)
                compactButton(icon: "photo", label: "Image", tint: .cyan, isLocked: lockedTools.contains(.image), action: onAddImage)
                compactButton(icon: "pencil.and.scribble", label: "Drawing", tint: .orange, action: onAddDrawing)
                compactButton(
                    icon: "scribble.variable",
                    label: "Draw on Canvas",
                    tint: Color(red: 0.9, green: 0.5, blue: 0.1),
                    action: onDrawOnCanvas
                )
                #if os(iOS)
                if showsWriteTextTool {
                    compactButton(
                        icon: "textformat.abc.dottedunderline",
                        label: "Write Text",
                        tint: .blue,
                        action: onWriteTextOnCanvas
                    )
                }
                #endif
            }
            .padding(.horizontal, 16)
            .frame(height: buttonSize + 8, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(maxWidth: .infinity)
        .frame(height: buttonSize + 12)
        .clipped()
    }

    private func sideButtons(safeTop: CGFloat, safeBottom: CGFloat, height: CGFloat) -> some View {
        let verticalPadding = safeTop + safeBottom + 176
        let maxHeight = max(buttonSize + 10, height - verticalPadding)

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 9) {
                #if os(iOS)
                compactButton(icon: "doc.text.viewfinder", label: "OCR Scan", tint: .teal, action: onScanOCR)
                compactButton(icon: "doc.viewfinder", label: "Scan Document", tint: .red, action: onScanDocument)
                #endif
                compactButton(icon: "doc.richtext", label: "PDF", tint: .red, action: onAddPDF)
                compactButton(icon: "tablecells", label: "Table", tint: .indigo, isLocked: lockedTools.contains(.table), action: onAddTable)
                compactButton(icon: "waveform", label: "Audio", tint: .pink, isLocked: lockedTools.contains(.audio), action: onAddAudio)
                compactButton(icon: "play.rectangle.fill", label: "YouTube", tint: .red, action: onAddYouTube)
                compactButton(icon: "square.grid.2x2.fill", label: "Symbols", tint: .mint, action: onAddSymbol)
                compactButton(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    label: "Connect",
                    tint: isConnectModeActive ? .white : Color.accentColor,
                    isActive: isConnectModeActive,
                    action: onConnect
                )
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(width: buttonSize + 16, height: maxHeight)
        .padding(.trailing, 12)
        .padding(.top, safeTop + 86)
        .padding(.bottom, max(safeBottom, 8) + 70)
    }

    private func compactButton(
        icon: String,
        label: String,
        tint: Color,
        isActive: Bool = false,
        isLocked: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: buttonSize, height: buttonSize, alignment: .center)
                    .background(
                        isActive ? Color.accentColor : Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: buttonCornerRadius)
                    )
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: buttonCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: buttonCornerRadius)
                            .strokeBorder(isActive ? Color.accentColor : Color.primary.opacity(0.82), lineWidth: 2.4)
                    )
                    .opacity(isLocked ? 0.52 : 1)

                if isLocked {
                    RoundedRectangle(cornerRadius: buttonCornerRadius)
                        .fill(Color.black.opacity(0.48))
                        .frame(width: buttonSize, height: buttonSize)
                    lockBadge(size: 18, iconSize: 8)
                        .offset(x: -3, y: 3)
                }
            }
            .frame(width: buttonSize, height: buttonSize, alignment: .center)
            .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: buttonCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLocked ? "\(label), Pro required" : label)
    }

    private func lockBadge(size: CGFloat, iconSize: CGFloat) -> some View {
        Image(systemName: "lock.fill")
            .font(.system(size: iconSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.black.opacity(0.78), in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.34), lineWidth: 0.7))
    }

    private func compactCollapseButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.primary)
                .frame(width: buttonSize, height: buttonSize, alignment: .center)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: buttonCornerRadius))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: buttonCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: buttonCornerRadius)
                        .strokeBorder(Color.primary.opacity(0.82), lineWidth: 2.4)
                )
                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 5)
                .contentShape(RoundedRectangle(cornerRadius: buttonCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
