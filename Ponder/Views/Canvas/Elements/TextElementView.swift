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
    var isCanvasGestureActive: Bool = false

    @State private var dragOffset: CGSize    = .zero
    @State private var isDragging: Bool      = false
    @State private var textSize: CGSize      = .zero
    @State private var rotationAngle: Double = 0
    @State private var resizeDelta: CGFloat  = 0
    @State private var showEditSheet: Bool   = false
    @State private var hasCommittedInline: Bool = false
    @State private var showCardPicker: Bool  = false
    @State private var showTextColorPicker: Bool = false
    @State private var customTextColorDraft: Color = .primary
    @StateObject private var inlineEditing = EditableTextBehavior()
    @FocusState private var inlineFocused: Bool

    private var isSelected: Bool      { vm.editingID == element.id }
    private var isInlineEditing: Bool { vm.inlineEditingID == element.id }
    private let handleSize: CGFloat   = 26

    private let toolbarHeight: CGFloat = 44
    private let cardPickerGap: CGFloat = 8

    var body: some View {
        ZStack {
            if isInlineEditing {
                inlineEditor
            } else {
                textLayer
            }

            if isSelected && !isMultiSelectMode && !isInlineEditing {
                cornerHandles
            }

            if isSelected && !isMultiSelectMode && !isInlineEditing {
                if showCardPicker {
                    cardPickerPanel
                        .scaleEffect(1.0 / canvasScale)
                        .offset(y: -(textSize.height / 2)
                                   - (toolbarHeight / canvasScale)
                                   - (cardPickerGap / canvasScale)
                                   - (estimatedCardPickerHeight / canvasScale / 2))
                        .zIndex(600)
                        .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                        .animation(.spring(duration: 0.22), value: showCardPicker)
                }

                formattingToolbar
                    .offset(y: -(textSize.height / 2) - 44 / canvasScale)
                    .scaleEffect(1.0 / canvasScale)
                    .zIndex(500)
                    .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                    .animation(.spring(duration: 0.22), value: isSelected)
            }
        }
        .rotationEffect(.degrees(rotationAngle), anchor: .center)
        // DragGesture inside SwiftUI's scaleEffect ZStack already reports translation
        // in canvas coordinate space — SwiftUI inverse-maps screen touches through the
        // parent transform automatically. No manual scale correction needed here.
        .position(x: element.x + dragOffset.width,
                  y: element.y + dragOffset.height)
        .gesture(canMove ? moveDragGesture : nil)
        .sheet(isPresented: $showEditSheet) {
            EditTextSheet(element: element, context: context)
                .presentationDetents([.height(480)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
        .popover(isPresented: $showTextColorPicker) {
            customTextColorPanel
        }
        .onChange(of: isInlineEditing) { _, editing in
            if editing {
                inlineEditing.load(element.text, force: true)
                inlineFocused      = true
                hasCommittedInline = false
            }
        }
        .onChange(of: isSelected) { _, selected in
            if !selected {
                showCardPicker = false
                showTextColorPicker = false
            }
        }
    }

    private var estimatedCardPickerHeight: CGFloat {
        element.strokeColorName != "none" ? 260 : 200
    }

    // MARK: - Text layer

    private var textLayer: some View {
        styledText(element.text)
            .multilineTextAlignment(element.textAlignment)
            .padding(element.hasCard ? 16 : 10)
            .fixedSize()
            .background(cardBackground)
            .background(sizeReader)
            .overlay(multiSelectRing)
            .onTapGesture {
                guard !isMultiSelectMode, !isDragging, !isCanvasGestureActive else { return }
                if !isSelected {
                    onExternalTap?()
                    vm.editingID = element.id
                }
            }
            .onTapGesture(count: 2) {
                guard !isMultiSelectMode, !isCanvasGestureActive else { return }
                onExternalTap?()
                vm.editingID       = element.id
                vm.inlineEditingID = element.id
                inlineEditing.load(element.text, force: true)
                inlineFocused      = true
            }
    }

    // MARK: - Card background

    @ViewBuilder
    private var cardBackground: some View {
        let hasBg     = element.bgColorName != "none"
        let hasStroke = element.strokeColorName != "none"

        if hasBg || hasStroke {
            RoundedRectangle(cornerRadius: 8)
                .fill(hasBg
                      ? (vm.cardColorFromName(element.bgColorName) ?? Color.clear)
                      : Color.clear)
                .overlay(
                    hasStroke
                    ? RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            vm.cardColorFromName(element.strokeColorName) ?? Color.clear,
                            lineWidth: element.strokeWidth
                        )
                    : nil
                )
                .shadow(color: .black.opacity(hasBg ? 0.12 : 0), radius: 6, x: 0, y: 3)
        } else if isSelected && !isMultiSelectMode {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                )
        }
    }

    // MARK: - Inline editor

    private var inlineEditor: some View {
        ZStack(alignment: .center) {
            styledText(inlineEditing.draft.isEmpty ? "Tap to type..." : inlineEditing.draft)
                .padding(12).fixedSize().opacity(0).background(sizeReader)

            TextEditor(text: $inlineEditing.draft)
                .font(elementFont)
                .foregroundStyle(vm.colorFromName(element.colorName))
                .multilineTextAlignment(element.textAlignment)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($inlineFocused)
                .frame(minWidth: 160, minHeight: 36)
                .fixedSize()
                .padding(8)
                #if os(macOS)
                .onKeyPress(.escape) { commitInlineEdit(); return .handled }
                #endif
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor,
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                )
        )
        .overlay(alignment: .topTrailing) {
            Button { commitInlineEdit() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    Text("Done").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.accentColor, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .scaleEffect(1.0 / canvasScale)
            .offset(x: 0, y: -36 / canvasScale)
        }
        .overlay(alignment: .bottomLeading) {
            Text(inlineEditing.draft.isEmpty ? "Start typing..." : "")
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor.opacity(0.6))
                .padding(.horizontal, 8).padding(.bottom, -18)
                .scaleEffect(1.0 / canvasScale)
                .allowsHitTesting(false)
        }
        .onChange(of: inlineFocused) { _, focused in
            if !focused && isInlineEditing { commitInlineEdit() }
        }
    }

    private func commitInlineEdit() {
        guard !hasCommittedInline else { return }
        hasCommittedInline = true
        vm.commitInlineText(element: element, text: inlineEditing.draft, context: context)
    }

    // MARK: - Formatting toolbar

    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                formatButton(icon: "bold",      active: element.isBold)      { vm.toggleBold(element: element, context: context) }
                formatButton(icon: "italic",    active: element.isItalic)    { vm.toggleItalic(element: element, context: context) }
                formatButton(icon: "underline", active: element.isUnderline) { vm.toggleUnderline(element: element, context: context) }

                toolbarDivider

                formatButton(icon: "minus", active: false) {
                    vm.adjustFontSize(by: -fontSizeStep, element: element, context: context)
                }
                Text("\(Int(element.fontSize))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary).frame(width: 34)
                formatButton(icon: "plus", active: false) {
                    vm.adjustFontSize(by: fontSizeStep, element: element, context: context)
                }

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
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                toolbarDivider

                ForEach(TextStyle.colorOptions.prefix(6), id: \.name) { option in
                    Button { vm.setColor(option.name, element: element, context: context) } label: {
                        let active = element.colorName == option.name
                        Circle()
                            .fill(option.color)
                            .frame(width: active ? 20 : 16, height: active ? 20 : 16)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        Color.primary.opacity(active ? 0.5 : (option.name == "white" ? 0.18 : 0)),
                                        lineWidth: 1.5
                                    )
                            )
                            .animation(.easeInOut(duration: 0.15), value: element.colorName)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    customTextColorDraft = vm.colorFromName(element.colorName)
                    showCardPicker = false
                    showTextColorPicker = true
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isCustomTextColor ? Color.accentColor : Color.primary)
                        .frame(width: 32, height: 32)
                        .background(
                            isCustomTextColor ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                toolbarDivider

                Button {
                    showTextColorPicker = false
                    withAnimation(.spring(duration: 0.22)) { showCardPicker.toggle() }
                } label: {
                    Image(systemName: element.hasCard ? "rectangle.fill" : "rectangle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(showCardPicker || element.hasCard ? Color.accentColor : Color.primary)
                        .frame(width: 32, height: 32)
                        .background(
                            (showCardPicker || element.hasCard)
                            ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
        )
        .fixedSize(horizontal: true, vertical: true)
    }

    private var customTextColorPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Text Color")
                .font(.headline)

            ColorPicker("Color", selection: $customTextColorDraft, supportsOpacity: false)

            HStack {
                Button("Cancel") {
                    showTextColorPicker = false
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Apply") {
                    let colorName = TextStyle.storageName(for: customTextColorDraft, fallback: element.colorName)
                    vm.setColor(colorName, element: element, context: context)
                    showTextColorPicker = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private var isCustomTextColor: Bool {
        !TextStyle.colorOptions.contains { $0.name == element.colorName }
    }

    // MARK: - Card picker panel

    private var cardPickerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("BACKGROUND")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).tracking(1)
                HStack(spacing: 6) {
                    noneButton(selected: element.bgColorName == "none") {
                        vm.setBgColor("none", element: element, context: context)
                    }
                    ForEach(vm.cardColorOptions, id: \.name) { option in
                        colorDot(option: option, selected: element.bgColorName == option.name) {
                            vm.setBgColor(option.name, element: element, context: context)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("BORDER COLOR")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).tracking(1)
                HStack(spacing: 6) {
                    noneButton(selected: element.strokeColorName == "none") {
                        vm.setStrokeColor("none", element: element, context: context)
                    }
                    ForEach(vm.cardColorOptions, id: \.name) { option in
                        colorDot(option: option, selected: element.strokeColorName == option.name) {
                            vm.setStrokeColor(option.name, element: element, context: context)
                        }
                    }
                }
            }

            if element.strokeColorName != "none" {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BORDER WIDTH")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).tracking(1)
                    HStack(spacing: 8) {
                        ForEach([1.0, 2.0, 3.0, 5.0], id: \.self) { w in
                            Button {
                                vm.setStrokeWidth(w, element: element, context: context)
                            } label: {
                                Text("\(Int(w))pt")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(element.strokeWidth == w ? .white : .primary)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(element.strokeWidth == w
                                                               ? Color.accentColor
                                                               : Color.secondary.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        )
        .fixedSize()
    }

    private func noneButton(selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.clear).frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5))
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).opacity(selected ? 1 : 0))
        }
        .buttonStyle(.plain)
    }

    private func colorDot(option: (name: String, color: Color),
                          selected: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(option.color).frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.1), radius: 2)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).opacity(selected ? 1 : 0))
        }
        .buttonStyle(.plain)
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

    // MARK: - Multi-select ring

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
            tapHandle(icon: "trash",  color: .red,         x: -hw, y: -hh) {
                vm.delete(element: element, context: context)
            }
            tapHandle(icon: "pencil", color: .accentColor, x:  hw, y: -hh) {
                showCardPicker = false
                showEditSheet  = true
            }
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
                    element.fontSize = TextStyle.clampedFontSize(
                        element.fontSize + delta * 0.15
                    )
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
    // DragGesture inside the scaled ZStack returns translation already in
    // canvas coordinates — no division by canvasScale needed here.
    // updatePosition receives raw translation and divides by scale internally.

    private var moveDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard canMove else {
                    isDragging = false
                    dragOffset = .zero
                    return
                }
                isDragging = true
                dragOffset = value.translation
            }
            .onEnded { value in
                guard canMove else {
                    dragOffset = .zero
                    isDragging = false
                    return
                }
                let t      = value.translation
                dragOffset = .zero
                vm.updatePosition(element: element, translation: t,
                                  scale: canvasScale, boundary: canvasBoundary,
                                  context: context)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isDragging = false
                }
            }
    }

    private var canMove: Bool {
        isSelected && !isMultiSelectMode && !isInlineEditing && !isCanvasGestureActive
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
        let size = TextStyle.clampedFontSize(
            element.fontSize + Double(resizeDelta) * 0.15
        )
        var f: Font = element.fontName == "system"
            ? .system(size: size)
            : .custom(element.fontName, size: size)
        if element.isBold   { f = f.bold()   }
        if element.isItalic { f = f.italic() }
        return f
    }

    private var fontSizeStep: Double {
        element.fontSize >= 72 ? 8 : 2
    }
}
