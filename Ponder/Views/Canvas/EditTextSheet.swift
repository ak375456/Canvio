//
//  EditTextSheet.swift
//  Ponder
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct EditTextSheet: View {
    @EnvironmentObject private var settings: AppSettings
    let element: TextElementModel
    let context: ModelContext

    @State private var selectedColor: String    = "primary"
    @State private var selectedFont: String     = "system"
    @State private var fontSize: Double         = 16
    @State private var isBold: Bool             = false
    @State private var isItalic: Bool           = false
    @State private var isUnderline: Bool        = false
    @State private var alignment: TextAlignment = .leading
    @State private var bgColorName: String      = "none"
    @State private var strokeColorName: String  = "none"
    @State private var strokeWidth: Double      = 2.0
    @State private var isImportingFont: Bool    = false
    @State private var fontImportError: String?
    @State private var showPaywall: Bool        = false
    @StateObject private var textEditing        = EditableTextBehavior()
    @ObservedObject private var pro             = ProManager.shared
    @ObservedObject private var customFontStore = CustomFontStore.shared
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

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
                    cardRow
                }
                .padding(24)
            }
            Divider()
            saveButton
        }
        .onAppear {
            textEditing.load(element.text)
            selectedColor  = element.colorName
            selectedFont   = element.fontName
            fontSize       = element.fontSize
            isBold         = element.isBold
            isItalic       = element.isItalic
            isUnderline    = element.isUnderline
            alignment      = element.textAlignment
            bgColorName    = element.bgColorName
            strokeColorName = element.strokeColorName
            strokeWidth    = element.strokeWidth
            focused        = true
        }
        .fileImporter(
            isPresented: $isImportingFont,
            allowedContentTypes: supportedFontTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFontImport(result)
        }
        .alert(
            "Font Import Failed",
            isPresented: Binding(
                get: { fontImportError != nil },
                set: { if !$0 { fontImportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { fontImportError = nil }
        } message: {
            Text(fontImportError ?? "")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isImportingFont = true
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Text("Edit Text").font(.title3.weight(.bold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundStyle(.secondary).symbolRenderingMode(.hierarchical)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)
    }

    // MARK: - Text Field
    private var textField: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("TEXT")
            PastePreservingTextEditor(
                text: $textEditing.draft,
                fontName: selectedFont,
                fontSize: fontSize,
                isBold: isBold,
                isItalic: isItalic,
                isFocused: focused
            )
                .frame(minHeight: 80, maxHeight: 200)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            Divider()
        }
    }

    private var previewFont: Font {
        let base: Font = selectedFont == "system"
            ? .system(size: fontSize)
            : .custom(selectedFont, size: fontSize)
        var f = base
        if isBold   { f = f.bold()   }
        if isItalic { f = f.italic() }
        return f
    }

    // MARK: - Font
    private var fontRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    label("FONT")
                    Text("Add your custom fonts (.ttf)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                importFontButton
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(customFontStore.allFonts) { fontChip(font: $0) }
                }
                    .padding(.vertical, 2)
            }
        }
    }

    private func fontChip(font: AppFont) -> some View {
        let isSelected = selectedFont == font.name
        return Button { selectedFont = font.name } label: {
            Text(font.displayName)
                .font(font.name == "system" ? .system(size: 15, weight: .medium) : .custom(font.name, size: 16))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : Color.primary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12)))
        }.buttonStyle(.plain)
    }

    private var importFontButton: some View {
        Button {
            if pro.isPro {
                isImportingFont = true
            } else {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("Import")
                    .font(.subheadline.weight(.semibold))
                if !pro.isPro {
                    Text("PRO")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Font Size
    private var fontSizeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                label("FONT SIZE"); Spacer()
                fontSizePresetMenu
            }
            HStack(spacing: 12) {
                Button { fontSize = max(10, fontSize - 2) } label: {
                    Image(systemName: "minus.circle").font(.title3).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
                Slider(
                    value: $fontSize,
                    in: TextStyle.minimumFontSize...TextStyle.maximumFontSize,
                    step: 1
                )
                .tint(.accentColor)
                Button { fontSize = TextStyle.clampedFontSize(fontSize + fontSizeStep) } label: {
                    Image(systemName: "plus.circle").font(.title3).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: - Style
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
        }.buttonStyle(.plain)
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
        }.buttonStyle(.plain)
    }

    // MARK: - Text Color
    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("TEXT COLOR")
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
                        }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 2)
            }
        }
    }

    // MARK: - Card
    private var cardRow: some View {
        VStack(alignment: .leading, spacing: 16) {
            label("CARD")

            // Background
            VStack(alignment: .leading, spacing: 8) {
                Text("Background").font(.subheadline.weight(.medium))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button { bgColorName = "none" } label: {
                            ZStack {
                                Circle().fill(Color.clear).frame(width: 32, height: 32)
                                    .overlay(Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5))
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                                if bgColorName == "none" {
                                    Circle().strokeBorder(Color.accentColor, lineWidth: 2).frame(width: 36, height: 36)
                                }
                            }
                        }.buttonStyle(.plain)

                        ForEach(cardColorOptions, id: \.name) { option in
                            Button { bgColorName = option.name } label: {
                                ZStack {
                                    Circle().fill(option.color).frame(width: 32, height: 32)
                                        .shadow(color: .black.opacity(0.1), radius: 2)
                                    if bgColorName == option.name {
                                        Circle().strokeBorder(Color.accentColor, lineWidth: 2).frame(width: 36, height: 36)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 2)
                }
            }

            // Border color
            VStack(alignment: .leading, spacing: 8) {
                Text("Border Color").font(.subheadline.weight(.medium))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button { strokeColorName = "none" } label: {
                            ZStack {
                                Circle().fill(Color.clear).frame(width: 32, height: 32)
                                    .overlay(Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5))
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                                if strokeColorName == "none" {
                                    Circle().strokeBorder(Color.accentColor, lineWidth: 2).frame(width: 36, height: 36)
                                }
                            }
                        }.buttonStyle(.plain)

                        ForEach(cardColorOptions, id: \.name) { option in
                            Button { strokeColorName = option.name } label: {
                                ZStack {
                                    Circle().fill(option.color).frame(width: 32, height: 32)
                                        .shadow(color: .black.opacity(0.1), radius: 2)
                                    if strokeColorName == option.name {
                                        Circle().strokeBorder(Color.accentColor, lineWidth: 2).frame(width: 36, height: 36)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 2)
                }
            }

            // Border width
            if strokeColorName != "none" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Border Width").font(.subheadline.weight(.medium))
                    HStack(spacing: 8) {
                        ForEach([1.0, 2.0, 3.0, 5.0], id: \.self) { w in
                            Button { strokeWidth = w } label: {
                                Text("\(Int(w))pt")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(strokeWidth == w ? .white : .primary)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(Capsule()
                                        .fill(strokeWidth == w ? Color.accentColor : Color.secondary.opacity(0.12)))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }

            // Live preview
            if bgColorName != "none" || strokeColorName != "none" {
                HStack {
                    Spacer()
                    Text(textEditing.draft.isEmpty ? "Preview" : String(textEditing.draft.prefix(20)))
                        .font(previewFont)
                        .foregroundStyle(colorFromName(selectedColor))
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(bgColorName != "none"
                                      ? (cardColorFromName(bgColorName) ?? Color.clear)
                                      : Color.clear)
                                .overlay(
                                    strokeColorName != "none"
                                    ? RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(cardColorFromName(strokeColorName) ?? Color.clear,
                                                      lineWidth: strokeWidth)
                                    : nil
                                )
                        )
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Save
    private var saveButton: some View {
        Button {
            let trimmed = textEditing.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            element.text            = trimmed
            element.fontSize        = TextStyle.clampedFontSize(fontSize)
            element.isBold          = isBold
            element.isItalic        = isItalic
            element.isUnderline     = isUnderline
            element.textAlignment   = alignment
            element.colorName       = selectedColor
            element.fontName        = selectedFont
            element.bgColorName     = bgColorName
            element.strokeColorName = strokeColorName
            element.strokeWidth     = strokeWidth
            element.updatedAt       = Date()
            try? context.save()
            var style = TextStyle(
                text: trimmed,
                fontSize: fontSize,
                isBold: isBold,
                isItalic: isItalic,
                isUnderline: isUnderline,
                colorName: selectedColor,
                fontName: selectedFont
            )
            style.textAlignment = alignment
            style.bgColorName = bgColorName
            style.strokeColorName = strokeColorName
            style.strokeWidth = strokeWidth
            settings.rememberTextStyle(style)
            Task { await TextSyncService.shared.upsert(element) }
            dismiss()
        } label: {
            let empty = textEditing.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Text("Save Changes")
                .font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(empty ? Color.secondary.opacity(0.2) : Color.accentColor)
                .foregroundStyle(empty ? Color.secondary : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(textEditing.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    // MARK: - Helpers
    private func label(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
    }

    private var fontSizeStep: Double {
        fontSize >= 72 ? 8 : 2
    }

    private var fontSizePresetMenu: some View {
        Menu {
            ForEach([10, 12, 14, 16, 18, 24, 32, 48, 72, 96, 144, 192, 240], id: \.self) { size in
                Button("\(size) pt") { fontSize = Double(size) }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(Int(fontSize))pt")
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private func colorFromName(_ name: String) -> Color {
        TextStyle.colorOptions.first { $0.name == name }?.color ?? .primary
    }

    private func cardColorFromName(_ name: String) -> Color? {
        guard name != "none" else { return nil }
        return cardColorOptions.first { $0.name == name }?.color
    }

    private var supportedFontTypes: [UTType] {
        [UTType(filenameExtension: "ttf") ?? .data]
    }

    private func handleFontImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let importedFont = try customFontStore.importFont(from: url)
                selectedFont = importedFont.name
            } catch {
                fontImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        case .failure(let error):
            fontImportError = error.localizedDescription
        }
    }

    private let cardColorOptions: [(name: String, color: Color)] = [
        ("red",    .red),    ("orange", .orange),
        ("yellow", Color(red: 1, green: 0.85, blue: 0)),
        ("green",  .green),  ("blue",   .blue),
        ("purple", .purple), ("pink",   .pink),
        ("teal",   .teal),   ("white",  .white),
        ("black",  Color(white: 0.1)), ("gray", Color(white: 0.5)),
    ]
}
