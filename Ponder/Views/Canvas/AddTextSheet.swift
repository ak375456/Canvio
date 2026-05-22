//
//  AddTextSheet.swift
//  Ponder
//

import SwiftUI

struct AddTextSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (TextStyle) -> Void

    @State private var text: String          = ""
    @State private var selectedColor: String = "primary"
    @State private var selectedFont: String  = "system"
    @State private var fontSize: Double      = 16
    @State private var isBold: Bool          = false
    @State private var isItalic: Bool        = false
    @State private var isUnderline: Bool     = false
    @State private var alignment: TextAlignment = .leading
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    textField
                    fontRow
                    fontSizeRow
                    fontStyleRow
                    alignmentRow
                    colorRow
                }
                .padding(24)
            }
            Divider()
            addButton
        }
        .onAppear { focused = true }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Text("Add Text").font(.title3.weight(.bold))
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundStyle(.secondary).symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)
    }

    // MARK: - Text Field
    // FIX: TextEditor preserves newlines on paste; TextField collapses them to spaces.
    private var textField: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("TEXT")
            TextEditor(text: $text)
                .font(previewFont)
                .frame(minHeight: 80, maxHeight: 200)
                .scrollContentBackground(.hidden)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .focused($focused)
            Divider()
        }
    }

    private var previewFont: Font {
        let base: Font = selectedFont == "system"
            ? .system(size: fontSize)
            : .custom(selectedFont, size: fontSize)
        var f = base
        if isBold   { f = f.bold() }
        if isItalic { f = f.italic() }
        return f
    }

    // MARK: - Font Picker
    private var fontRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("FONT")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AppFont.allFonts) { font in fontChip(font: font) }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func fontChip(font: AppFont) -> some View {
        let isSelected = selectedFont == font.name
        return Button { selectedFont = font.name } label: {
            Text(font.displayName)
                .font(font.name == "system"
                      ? .system(size: 15, weight: .medium)
                      : .custom(font.name, size: 16))
                .foregroundStyle(isSelected ? .white : Color.primary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Font Size
    private var fontSizeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                label("FONT SIZE"); Spacer()
                Text("\(Int(fontSize))pt").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button { fontSize = max(10, fontSize - 2) } label: {
                    Image(systemName: "minus.circle").font(.title3).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
                Slider(value: $fontSize, in: 10...72, step: 1).tint(.accentColor)
                Button { fontSize = min(72, fontSize + 2) } label: {
                    Image(systemName: "plus.circle").font(.title3).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: - Font Style
    private var fontStyleRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("STYLE")
            HStack(spacing: 10) {
                styleToggle(title: "Bold",      icon: "bold",      isOn: $isBold)
                styleToggle(title: "Italic",    icon: "italic",    isOn: $isItalic)
                styleToggle(title: "Underline", icon: "underline", isOn: $isUnderline)
            }
        }
    }

    private func styleToggle(title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(title).font(.subheadline.weight(.medium))
            }
            .foregroundStyle(isOn.wrappedValue ? .white : Color.primary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(isOn.wrappedValue ? Color.accentColor : Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Alignment
    private var alignmentRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("ALIGNMENT")
            HStack(spacing: 10) {
                alignButton(.leading,  icon: "text.alignleft",   title: "Left")
                alignButton(.center,   icon: "text.aligncenter", title: "Center")
                alignButton(.trailing, icon: "text.alignright",  title: "Right")
            }
        }
    }

    private func alignButton(_ value: TextAlignment, icon: String, title: String) -> some View {
        let active = alignment == value
        return Button { alignment = value } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(title).font(.subheadline.weight(.medium))
            }
            .foregroundStyle(active ? .white : Color.primary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(active ? Color.accentColor : Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Color
    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("COLOR")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(TextStyle.colorOptions, id: \.name) { option in
                        Button { selectedColor = option.name } label: {
                            ZStack {
                                Circle().fill(option.color).frame(width: 32, height: 32)
                                if selectedColor == option.name {
                                    Circle().strokeBorder(Color.primary.opacity(0.4), lineWidth: 2)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Add Button
    private var addButton: some View {
        Button {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onAdd(TextStyle(
                text: trimmed, fontSize: fontSize,
                isBold: isBold, isItalic: isItalic,
                colorName: selectedColor, fontName: selectedFont
            ))
            isPresented = false
        } label: {
            let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Text("Add to Canvas")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(empty ? Color.secondary.opacity(0.2) : Color.accentColor)
                .foregroundStyle(empty ? Color.secondary : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
    }
}

// MARK: - italic helper (keep for compatibility)
extension Font {
    func italic(_ active: Bool) -> Font { active ? self.italic() : self }
}
