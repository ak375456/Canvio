//
//  TextElementView.swift
//  Ponder
//

import SwiftUI
import SwiftData

struct TextElementView: View {
    @Environment(\.modelContext) private var context
    let element: TextElementModel
    let canvasScale: CGFloat
    let canvasBoundary: CGSize
    @ObservedObject var vm: TextElementViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect: Bool = false
    var onExternalTap: (() -> Void)? = nil

    @State private var dragOffset: CGSize    = .zero
    @State private var textSize: CGSize      = .zero
    @State private var rotationAngle: Double = 0
    @State private var resizeDelta: CGFloat  = 0
    @State private var showEditSheet: Bool   = false
    @State private var inlineText: String    = ""
    @FocusState private var inlineFocused: Bool

    private var isSelected: Bool      { vm.editingID == element.id }
    private var isInlineEditing: Bool { vm.inlineEditingID == element.id }
    private let handleSize: CGFloat   = 26

    var body: some View {
        ZStack {
            // ── Main content ──────────────────────────────────────────
            if isInlineEditing {
                inlineEditor
            } else {
                textLayer
            }

            // ── Corner handles ────────────────────────────────────────
            if isSelected && !isMultiSelectMode && !isInlineEditing {
                cornerHandles
            }

            // ── Formatting toolbar ────────────────────────────────────
            // Placed INSIDE the ZStack so it's positioned relative to
            // the element center. Using .overlay after .position() would
            // expand to fill the full parent canvas — never do that.
            if isSelected && !isMultiSelectMode && !isInlineEditing {
                formattingToolbar
                    .offset(y: -(textSize.height / 2) - 44 / canvasScale)
                    .scaleEffect(1.0 / canvasScale)
                    .zIndex(500)
                    .transition(
                        .scale(scale: 0.85, anchor: .bottom)
                        .combined(with: .opacity)
                    )
                    .animation(.spring(duration: 0.22), value: isSelected)
            }
        }
        .rotationEffect(.degrees(rotationAngle), anchor: .center)
        .position(x: element.x + dragOffset.width, y: element.y + dragOffset.height)
        .gesture(isMultiSelectMode ? nil : moveDragGesture)
        .sheet(isPresented: $showEditSheet) {
            EditTextSheet(element: element, context: context)
                .presentationDetents([.height(480)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
        .onChange(of: isInlineEditing) { _, editing in
            if editing {
                inlineText    = element.text
                inlineFocused = true
            }
        }
    }

    // MARK: - Text layer (display mode)

    private var textLayer: some View {
        styledText(element.text)
            .padding(10)
            .fixedSize()
            .background(selectionBackground)
            .background(sizeReader)
            .overlay(multiSelectRing)
            .onTapGesture {
                guard !isMultiSelectMode else { return }
                onExternalTap?()
                vm.editingID = isSelected ? nil : element.id
            }
            .onTapGesture(count: 2) {
                guard !isMultiSelectMode else { return }
                onExternalTap?()
                vm.editingID       = element.id
                vm.inlineEditingID = element.id
                inlineText         = element.text
                inlineFocused      = true
            }
    }

    // MARK: - Inline editor

    private var inlineEditor: some View {
        ZStack(alignment: .topLeading) {
            // Hidden size-tracker keeps the ZStack from collapsing
            styledText(inlineText.isEmpty ? " " : inlineText)
                .padding(10)
                .fixedSize()
                .opacity(0)
                .background(sizeReader)

            TextEditor(text: $inlineText)
                .font(elementFont)
                .foregroundStyle(vm.colorFromName(element.colorName))
                .multilineTextAlignment(element.textAlignment)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($inlineFocused)
                .frame(minWidth: 120, minHeight: 36)
                .fixedSize()
                .padding(6)
                #if os(macOS)
                .onKeyPress(.return) {
                    commitInlineEdit()
                    return .handled
                }
                #endif
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                )
        )
        // Done button — floats above the editor box, counter-scaled.
        // Works on both iOS and macOS — no toolbar placement API needed.
        .overlay(alignment: .topTrailing) {
            Button { commitInlineEdit() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .scaleEffect(1.0 / canvasScale)
            .offset(x: 0, y: -36 / canvasScale)
        }
        .onChange(of: inlineFocused) { _, focused in
            if !focused { commitInlineEdit() }
        }
    }

    private func commitInlineEdit() {
        let trimmed = inlineText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            vm.delete(element: element, context: context)
        } else {
            element.text      = trimmed
            element.updatedAt = Date()
            try? context.save()
        }
        vm.inlineEditingID = nil
    }

    // MARK: - Formatting toolbar

    private var formattingToolbar: some View {
        HStack(spacing: 2) {
            formatButton(icon: "bold",      active: element.isBold)      { vm.toggleBold(element: element, context: context) }
            formatButton(icon: "italic",    active: element.isItalic)    { vm.toggleItalic(element: element, context: context) }
            formatButton(icon: "underline", active: element.isUnderline) { vm.toggleUnderline(element: element, context: context) }

            toolbarDivider

            formatButton(icon: "minus", active: false) { vm.adjustFontSize(by: -2, element: element, context: context) }
            Text("\(Int(element.fontSize))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            formatButton(icon: "plus", active: false) { vm.adjustFontSize(by: 2, element: element, context: context) }

            toolbarDivider

            Button {
                let next: TextAlignment
                switch element.textAlignment {
                case .leading:    next = .center
                case .center:     next = .trailing
                case .trailing:   next = .leading
                @unknown default: next = .leading
                }
                vm.setAlignment(next, element: element, context: context)
            } label: {
                Image(systemName: alignmentIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            toolbarDivider

            ForEach(TextStyle.colorOptions.prefix(6), id: \.name) { option in
                Button { vm.setColor(option.name, element: element, context: context) } label: {
                    let active = element.colorName == option.name
                    Circle()
                        .fill(option.color)
                        .frame(width: active ? 20 : 16, height: active ? 20 : 16)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(active ? 0.5 : 0), lineWidth: 1.5))
                        .animation(.easeInOut(duration: 0.15), value: element.colorName)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
        )
        .fixedSize()
    }

    private func formatButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Color.white : Color.primary)
                .frame(width: 32, height: 32)
                .background(active ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
    }

    private var alignmentIcon: String {
        switch element.textAlignment {
        case .leading:    return "text.alignleft"
        case .center:     return "text.aligncenter"
        case .trailing:   return "text.alignright"
        @unknown default: return "text.alignleft"
        }
    }

    // MARK: - Selection background & rings

    private var selectionBackground: some View {
        Group {
            if isSelected && !isMultiSelectMode {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                    )
            }
        }
    }

    @ViewBuilder
    private var multiSelectRing: some View {
        if isMultiSelectMode {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isSelectedInMultiSelect ? Color.blue : Color.white.opacity(0.3),
                    lineWidth: isSelectedInMultiSelect ? 2.5 : 1
                )
                .overlay(alignment: .topTrailing) {
                    if isSelectedInMultiSelect {
                        ZStack {
                            Circle().fill(Color.blue).frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        }.offset(x: 8, y: -8)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isSelectedInMultiSelect)
        }
    }

    private var sizeReader: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear  { textSize = geo.size }
                .onChange(of: geo.size) { _, s in textSize = s }
        }
    }

    // MARK: - Corner handles

    private var cornerHandles: some View {
        let hw = textSize.width  / 2
        let hh = textSize.height / 2
        return ZStack {
            tapHandle(icon: "trash",  color: .red,         x: -hw, y: -hh) { vm.delete(element: element, context: context) }
            tapHandle(icon: "pencil", color: .accentColor, x:  hw, y: -hh) { showEditSheet = true }
            rotateHandle(x: -hw, y: hh)
            resizeHandle(x:  hw, y: hh)
        }
    }

    private func tapHandle(icon: String, color: Color, x: CGFloat, y: CGFloat,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) { handleAppearance(icon: icon, color: color) }
            .buttonStyle(.plain).offset(x: x, y: y)
    }

    private func rotateHandle(x: CGFloat, y: CGFloat) -> some View {
        handleAppearance(icon: "arrow.trianglehead.2.clockwise", color: .orange)
            .offset(x: x, y: y)
            .gesture(DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    let sx = element.x * canvasScale
                    let sy = element.y * canvasScale
                    rotationAngle = atan2(value.location.y - sy,
                                         value.location.x - sx) * 180 / .pi + 45
                }
                .onEnded { _ in })
    }

    private func resizeHandle(x: CGFloat, y: CGFloat) -> some View {
        handleAppearance(icon: "arrow.up.left.and.arrow.down.right", color: .green)
            .offset(x: x, y: y)
            .gesture(DragGesture()
                .onChanged { value in
                    resizeDelta = (value.translation.width + value.translation.height) / 2
                }
                .onEnded { value in
                    let delta = (value.translation.width + value.translation.height) / 2
                    element.fontSize = max(10, min(72, element.fontSize + delta * 0.15))
                    resizeDelta = 0
                    try? context.save()
                })
    }

    private func handleAppearance(icon: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color).frame(width: handleSize, height: handleSize)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        }
    }

    // MARK: - Move gesture

    private var moveDragGesture: some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                let t = value.translation; dragOffset = .zero
                vm.updatePosition(element: element, translation: t,
                                  scale: canvasScale, boundary: canvasBoundary,
                                  context: context)
            }
    }

    // MARK: - Text rendering

    @ViewBuilder
    private func styledText(_ string: String) -> some View {
        if element.isUnderline {
            Text(underlinedString(string))
                .font(elementFont)
                .foregroundStyle(vm.colorFromName(element.colorName))
                .multilineTextAlignment(element.textAlignment)
                .lineLimit(nil)
        } else {
            Text(string)
                .font(elementFont)
                .foregroundStyle(vm.colorFromName(element.colorName))
                .multilineTextAlignment(element.textAlignment)
                .lineLimit(nil)
        }
    }

    private func underlinedString(_ string: String) -> AttributedString {
        var attr = AttributedString(string)
        attr.underlineStyle = .single
        return attr
    }

    private var elementFont: Font {
        let size = max(10, min(72, element.fontSize + Double(resizeDelta) * 0.15))
        var f: Font = element.fontName == "system"
            ? .system(size: size)
            : .custom(element.fontName, size: size)
        if element.isBold   { f = f.bold()   }
        if element.isItalic { f = f.italic() }
        return f
    }
}
