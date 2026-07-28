//
//  RichTextEditor.swift
//  Ponder
//

import Combine
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct RichTextSelectionSummary: Equatable {
    var hasSelection: Bool = false
    var attributes: RichTextAttributes = RichTextAttributes()
}

@MainActor
protocol RichTextEditorBridge: AnyObject {
    func replaceDocument(_ document: RichTextDocument)
    func toggleBold()
    func toggleItalic()
    func toggleUnderline()
    func setColor(_ colorName: String)
    func setFontName(_ fontName: String)
    func setFontSize(_ fontSize: Double)
    func setAlignment(_ alignment: TextAlignment)
}

@MainActor
final class RichTextEditingState: ObservableObject {
    @Published var document: RichTextDocument
    @Published var selectionSummary: RichTextSelectionSummary

    weak var bridge: RichTextEditorBridge?

    init() {
        self.document = RichTextDocument()
        self.selectionSummary = RichTextSelectionSummary()
    }

    init(document: RichTextDocument) {
        let normalized = document.normalized
        self.document = normalized
        self.selectionSummary = RichTextSelectionSummary(
            attributes: normalized.firstAttributes ?? RichTextAttributes()
        )
    }

    func load(_ document: RichTextDocument) {
        let normalized = document.normalized
        self.document = normalized
        selectionSummary = RichTextSelectionSummary(
            attributes: normalized.firstAttributes ?? selectionSummary.attributes
        )
        bridge?.replaceDocument(normalized)
    }

    func toggleBold() { bridge?.toggleBold() }
    func toggleItalic() { bridge?.toggleItalic() }
    func toggleUnderline() { bridge?.toggleUnderline() }
    func setColor(_ colorName: String) { bridge?.setColor(colorName) }
    func setFontName(_ fontName: String) { bridge?.setFontName(fontName) }
    func setFontSize(_ fontSize: Double) { bridge?.setFontSize(fontSize) }
    func setAlignment(_ alignment: TextAlignment) { bridge?.setAlignment(alignment) }
}

struct RichTextEditor: View {
    @ObservedObject var state: RichTextEditingState
    let isFocused: Bool

    var body: some View {
        PlatformRichTextEditor(state: state, isFocused: isFocused)
    }
}

#if canImport(UIKit) || canImport(AppKit)

private extension NSAttributedString.Key {
    static let richTextFontName = NSAttributedString.Key("com.ponder.richText.fontName")
    static let richTextFontSize = NSAttributedString.Key("com.ponder.richText.fontSize")
    static let richTextBold = NSAttributedString.Key("com.ponder.richText.bold")
    static let richTextItalic = NSAttributedString.Key("com.ponder.richText.italic")
    static let richTextUnderline = NSAttributedString.Key("com.ponder.richText.underline")
    static let richTextColorName = NSAttributedString.Key("com.ponder.richText.colorName")
}

private enum NativeRichText {
    static func attributedString(from document: RichTextDocument) -> NSAttributedString {
        let normalized = document.normalized
        let output = NSMutableAttributedString()
        for run in normalized.runs {
            output.append(NSAttributedString(
                string: run.text,
                attributes: nativeAttributes(
                    for: run.attrs,
                    alignmentRaw: normalized.paragraph.alignmentRaw
                )
            ))
        }
        return output
    }

    static func document(from attributedString: NSAttributedString, alignmentRaw: String) -> RichTextDocument {
        guard attributedString.length > 0 else {
            return RichTextDocument(
                runs: [],
                paragraph: RichTextParagraph(alignmentRaw: alignmentRaw)
            )
        }

        var runs: [RichTextRun] = []
        let fullRange = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            let text = attributedString.attributedSubstring(from: range).string.normalizedRichEditorLineBreaks
            guard !text.isEmpty else { return }
            runs.append(RichTextRun(
                text: text,
                attrs: richTextAttributes(from: attributes, fallback: RichTextAttributes())
            ))
        }

        return RichTextDocument(
            runs: runs,
            paragraph: RichTextParagraph(alignmentRaw: alignmentRaw)
        ).normalized
    }

    static func nativeAttributes(
        for attributes: RichTextAttributes,
        alignmentRaw: String
    ) -> [NSAttributedString.Key: Any] {
        let attrs = attributes.normalized()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = nativeAlignment(from: alignmentRaw)

        var native: [NSAttributedString.Key: Any] = [
            .font: platformFont(for: attrs),
            .foregroundColor: platformColor(named: attrs.colorName),
            .paragraphStyle: paragraphStyle,
            .richTextFontName: attrs.fontName,
            .richTextFontSize: attrs.fontSize,
            .richTextBold: attrs.isBold,
            .richTextItalic: attrs.isItalic,
            .richTextUnderline: attrs.isUnderline,
            .richTextColorName: attrs.colorName
        ]

        if attrs.isUnderline {
            native[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return native
    }

    static func richTextAttributes(
        from attributes: [NSAttributedString.Key: Any],
        fallback: RichTextAttributes
    ) -> RichTextAttributes {
        let fontSize: Double
        if let stored = attributes[.richTextFontSize] as? Double {
            fontSize = stored
        } else if let stored = attributes[.richTextFontSize] as? NSNumber {
            fontSize = stored.doubleValue
        } else {
            fontSize = inferredFontSize(from: attributes) ?? fallback.fontSize
        }

        let isUnderline: Bool
        if let stored = attributes[.richTextUnderline] as? Bool {
            isUnderline = stored
        } else if let stored = attributes[.richTextUnderline] as? NSNumber {
            isUnderline = stored.boolValue
        } else {
            let raw = attributes[.underlineStyle] as? Int ?? 0
            isUnderline = raw != 0
        }

        return RichTextAttributes(
            fontName: attributes[.richTextFontName] as? String ?? fallback.fontName,
            fontSize: fontSize,
            isBold: boolAttribute(.richTextBold, in: attributes) ?? inferredBold(from: attributes) ?? fallback.isBold,
            isItalic: boolAttribute(.richTextItalic, in: attributes) ?? inferredItalic(from: attributes) ?? fallback.isItalic,
            isUnderline: isUnderline,
            colorName: attributes[.richTextColorName] as? String ?? inferredColorName(from: attributes) ?? fallback.colorName
        )
    }

    static func rawAlignment(from alignment: NSTextAlignment) -> String {
        switch alignment {
        case .center: return "center"
        case .right: return "trailing"
        default: return "leading"
        }
    }

    static func nativeAlignment(from raw: String) -> NSTextAlignment {
        switch raw {
        case "center": return .center
        case "trailing": return .right
        default: return .left
        }
    }

    private static func boolAttribute(
        _ key: NSAttributedString.Key,
        in attributes: [NSAttributedString.Key: Any]
    ) -> Bool? {
        if let value = attributes[key] as? Bool { return value }
        if let value = attributes[key] as? NSNumber { return value.boolValue }
        return nil
    }

    #if canImport(UIKit)
    private static func platformFont(for attributes: RichTextAttributes) -> UIFont {
        let size = CGFloat(TextStyle.clampedFontSize(attributes.fontSize))
        let base = attributes.fontName == "system"
            ? UIFont.systemFont(ofSize: size)
            : (UIFont(name: attributes.fontName, size: size) ?? UIFont.systemFont(ofSize: size))

        var traits = base.fontDescriptor.symbolicTraits
        if attributes.isBold { traits.insert(.traitBold) }
        if attributes.isItalic { traits.insert(.traitItalic) }
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func platformColor(named name: String) -> UIColor {
        if name == "primary" { return .label }
        if let color = uiColorFromHex(name) { return color }
        return UIColor(TextStyle.color(named: name, fallback: .primary))
    }

    private static func inferredFontSize(from attributes: [NSAttributedString.Key: Any]) -> Double? {
        (attributes[.font] as? UIFont).map { Double($0.pointSize) }
    }

    private static func inferredBold(from attributes: [NSAttributedString.Key: Any]) -> Bool? {
        (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold)
    }

    private static func inferredItalic(from attributes: [NSAttributedString.Key: Any]) -> Bool? {
        (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitItalic)
    }

    private static func inferredColorName(from attributes: [NSAttributedString.Key: Any]) -> String? {
        guard let color = attributes[.foregroundColor] as? UIColor else { return nil }
        return hexString(from: color)
    }

    private static func uiColorFromHex(_ name: String) -> UIColor? {
        guard let components = rgbaComponents(from: name) else { return nil }
        return UIColor(
            red: components.red,
            green: components.green,
            blue: components.blue,
            alpha: components.alpha
        )
    }

    private static func hexString(from color: UIColor) -> String? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return hexString(red: red, green: green, blue: blue, alpha: alpha)
    }
    #elseif canImport(AppKit)
    private static func platformFont(for attributes: RichTextAttributes) -> NSFont {
        let size = CGFloat(TextStyle.clampedFontSize(attributes.fontSize))
        let base = attributes.fontName == "system"
            ? NSFont.systemFont(ofSize: size)
            : (NSFont(name: attributes.fontName, size: size) ?? NSFont.systemFont(ofSize: size))
        var font = base
        if attributes.isBold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if attributes.isItalic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    private static func platformColor(named name: String) -> NSColor {
        if name == "primary" { return .labelColor }
        if let color = nsColorFromHex(name) { return color }
        return NSColor(TextStyle.color(named: name, fallback: .primary))
    }

    private static func inferredFontSize(from attributes: [NSAttributedString.Key: Any]) -> Double? {
        (attributes[.font] as? NSFont).map { Double($0.pointSize) }
    }

    private static func inferredBold(from attributes: [NSAttributedString.Key: Any]) -> Bool? {
        guard let font = attributes[.font] as? NSFont else { return nil }
        return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }

    private static func inferredItalic(from attributes: [NSAttributedString.Key: Any]) -> Bool? {
        guard let font = attributes[.font] as? NSFont else { return nil }
        return NSFontManager.shared.traits(of: font).contains(.italicFontMask)
    }

    private static func inferredColorName(from attributes: [NSAttributedString.Key: Any]) -> String? {
        guard let color = attributes[.foregroundColor] as? NSColor,
              let converted = color.usingColorSpace(.sRGB) else { return nil }
        return hexString(
            red: converted.redComponent,
            green: converted.greenComponent,
            blue: converted.blueComponent,
            alpha: converted.alphaComponent
        )
    }

    private static func nsColorFromHex(_ name: String) -> NSColor? {
        guard let components = rgbaComponents(from: name) else { return nil }
        return NSColor(
            srgbRed: components.red,
            green: components.green,
            blue: components.blue,
            alpha: components.alpha
        )
    }
    #endif

    private static func rgbaComponents(from name: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        let raw = name.hasPrefix("#") ? String(name.dropFirst()) : name
        guard raw.count == 6 || raw.count == 8,
              let value = UInt64(raw, radix: 16) else { return nil }

        if raw.count == 8 {
            return (
                CGFloat((value & 0xFF000000) >> 24) / 255,
                CGFloat((value & 0x00FF0000) >> 16) / 255,
                CGFloat((value & 0x0000FF00) >> 8) / 255,
                CGFloat(value & 0x000000FF) / 255
            )
        }

        return (
            CGFloat((value & 0xFF0000) >> 16) / 255,
            CGFloat((value & 0x00FF00) >> 8) / 255,
            CGFloat(value & 0x0000FF) / 255,
            1
        )
    }

    private static func hexString(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> String {
        let r = Int(round(min(max(red, 0), 1) * 255))
        let g = Int(round(min(max(green, 0), 1) * 255))
        let b = Int(round(min(max(blue, 0), 1) * 255))
        let a = Int(round(min(max(alpha, 0), 1) * 255))
        if a < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

private extension String {
    var normalizedRichEditorLineBreaks: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0085}", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}

private enum RichPasteboardTextReader {
    static func firstNonEmpty(_ candidates: [String?]) -> String? {
        candidates
            .compactMap { $0?.normalizedRichEditorLineBreaks }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

#endif

#if canImport(UIKit)

private struct PlatformRichTextEditor: UIViewRepresentable {
    @ObservedObject var state: RichTextEditingState
    let isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> PastingRichTextView {
        let textView = PastingRichTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.allowsEditingTextAttributes = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false
        context.coordinator.textView = textView
        context.coordinator.replaceDocument(state.document)
        state.bridge = context.coordinator
        return textView
    }

    func updateUIView(_ textView: PastingRichTextView, context: Context) {
        state.bridge = context.coordinator
        context.coordinator.applyExternalDocumentIfNeeded(state.document)
        if !isFocused {
            context.coordinator.didApplyInitialFocus = false
        } else if !context.coordinator.didApplyInitialFocus {
            if textView.isFirstResponder || textView.becomeFirstResponder() {
                context.coordinator.didApplyInitialFocus = true
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, RichTextEditorBridge {
        weak var textView: UITextView?
        private let state: RichTextEditingState
        private var lastNativeDocument: RichTextDocument?
        private var isReplacingText = false
        var didApplyInitialFocus = false

        init(state: RichTextEditingState) {
            self.state = state
        }

        func textViewDidChange(_ textView: UITextView) {
            publishDocument(from: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            publishSelection(from: textView)
        }

        func replaceDocument(_ document: RichTextDocument) {
            guard let textView else { return }
            replaceDocument(document, in: textView)
        }

        func applyExternalDocumentIfNeeded(_ document: RichTextDocument) {
            guard let textView else { return }
            let normalized = document.normalized
            guard normalized != lastNativeDocument else { return }
            replaceDocument(normalized, in: textView)
        }

        func toggleBold() {
            let target = !state.selectionSummary.attributes.isBold
            applyToSelection { $0.isBold = target }
        }

        func toggleItalic() {
            let target = !state.selectionSummary.attributes.isItalic
            applyToSelection { $0.isItalic = target }
        }

        func toggleUnderline() {
            let target = !state.selectionSummary.attributes.isUnderline
            applyToSelection { $0.isUnderline = target }
        }

        func setColor(_ colorName: String) {
            applyToSelection { $0.colorName = colorName }
        }

        func setFontName(_ fontName: String) {
            applyToSelection { $0.fontName = fontName }
        }

        func setFontSize(_ fontSize: Double) {
            applyToSelection { $0.fontSize = TextStyle.clampedFontSize(fontSize) }
        }

        func setAlignment(_ alignment: TextAlignment) {
            guard let textView else { return }
            var document = currentDocument(from: textView)
            document.paragraph.textAlignment = alignment
            replaceDocument(document, in: textView, preservingSelection: true)
            publishDocument(from: textView)
            publishSelection(from: textView)
        }

        private func replaceDocument(
            _ document: RichTextDocument,
            in textView: UITextView,
            preservingSelection: Bool = false
        ) {
            let range = preservingSelection ? textView.selectedRange : NSRange(location: 0, length: 0)
            isReplacingText = true
            textView.attributedText = NativeRichText.attributedString(from: document)
            textView.textAlignment = NativeRichText.nativeAlignment(from: document.paragraph.alignmentRaw)
            textView.typingAttributes = NativeRichText.nativeAttributes(
                for: document.firstAttributes ?? state.selectionSummary.attributes,
                alignmentRaw: document.paragraph.alignmentRaw
            )
            textView.selectedRange = clamped(range, length: textView.attributedText.length)
            isReplacingText = false
            lastNativeDocument = document.normalized
            state.document = document.normalized
            publishSelection(from: textView)
        }

        private func applyToSelection(_ transform: (inout RichTextAttributes) -> Void) {
            guard let textView else { return }
            let selectedRange = textView.selectedRange
            let alignmentRaw = NativeRichText.rawAlignment(from: textView.textAlignment)

            if selectedRange.length == 0 {
                var attrs = NativeRichText.richTextAttributes(
                    from: textView.typingAttributes,
                    fallback: state.selectionSummary.attributes
                )
                transform(&attrs)
                textView.typingAttributes = NativeRichText.nativeAttributes(
                    for: attrs,
                    alignmentRaw: alignmentRaw
                )
                guard textView.attributedText.length > 0 else {
                    state.selectionSummary = RichTextSelectionSummary(hasSelection: false, attributes: attrs)
                    return
                }
            }

            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            let targetRange = selectedRange.length == 0
                ? NSRange(location: 0, length: mutable.length)
                : selectedRange
            let safeRange = clamped(targetRange, length: mutable.length)
            guard safeRange.length > 0 else { return }

            mutable.enumerateAttributes(in: safeRange, options: []) { attributes, range, _ in
                var attrs = NativeRichText.richTextAttributes(
                    from: attributes,
                    fallback: state.selectionSummary.attributes
                )
                transform(&attrs)
                mutable.setAttributes(
                    NativeRichText.nativeAttributes(for: attrs, alignmentRaw: alignmentRaw),
                    range: range
                )
            }

            isReplacingText = true
            textView.attributedText = mutable
            textView.textAlignment = NativeRichText.nativeAlignment(from: alignmentRaw)
            textView.selectedRange = selectedRange.length == 0
                ? clamped(selectedRange, length: mutable.length)
                : safeRange
            isReplacingText = false
            publishDocument(from: textView)
            publishSelection(from: textView)
        }

        private func publishDocument(from textView: UITextView) {
            guard !isReplacingText else { return }
            let document = currentDocument(from: textView)
            lastNativeDocument = document
            state.document = document
        }

        private func publishSelection(from textView: UITextView) {
            let range = textView.selectedRange
            let attrs: RichTextAttributes
            if range.length > 0, textView.attributedText.length > 0 {
                let location = min(range.location, max(textView.attributedText.length - 1, 0))
                attrs = NativeRichText.richTextAttributes(
                    from: textView.attributedText.attributes(at: location, effectiveRange: nil),
                    fallback: state.selectionSummary.attributes
                )
            } else {
                attrs = NativeRichText.richTextAttributes(
                    from: textView.typingAttributes,
                    fallback: state.selectionSummary.attributes
                )
            }
            state.selectionSummary = RichTextSelectionSummary(
                hasSelection: range.length > 0,
                attributes: attrs
            )
        }

        private func currentDocument(from textView: UITextView) -> RichTextDocument {
            NativeRichText.document(
                from: textView.attributedText ?? NSAttributedString(),
                alignmentRaw: NativeRichText.rawAlignment(from: textView.textAlignment)
            )
        }

        private func clamped(_ range: NSRange, length: Int) -> NSRange {
            let location = min(max(range.location, 0), length)
            let availableLength = max(0, length - location)
            return NSRange(location: location, length: min(range.length, availableLength))
        }
    }
}

private final class PastingRichTextView: UITextView {
    override func paste(_ sender: Any?) {
        guard let pasted = readPasteboardText() else {
            super.paste(sender)
            return
        }
        insertText(pasted)
    }

    override func insertText(_ text: String) {
        super.insertText(text.normalizedRichEditorLineBreaks)
    }

    private func readPasteboardText() -> String? {
        let pasteboard = UIPasteboard.general
        return RichPasteboardTextReader.firstNonEmpty([
            pasteboard.string
        ])
    }
}

#elseif canImport(AppKit)

private struct PlatformRichTextEditor: NSViewRepresentable {
    @ObservedObject var state: RichTextEditingState
    let isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PastingRichTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.replaceDocument(state.document)
        state.bridge = context.coordinator
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        state.bridge = context.coordinator
        context.coordinator.applyExternalDocumentIfNeeded(state.document)
        guard let textView = context.coordinator.textView else { return }
        if !isFocused {
            context.coordinator.didApplyInitialFocus = false
        } else if !context.coordinator.didApplyInitialFocus {
            if scrollView.window?.firstResponder === textView ||
                scrollView.window?.makeFirstResponder(textView) == true {
                context.coordinator.didApplyInitialFocus = true
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, RichTextEditorBridge {
        weak var textView: NSTextView?
        private let state: RichTextEditingState
        private var lastNativeDocument: RichTextDocument?
        private var isReplacingText = false
        var didApplyInitialFocus = false

        init(state: RichTextEditingState) {
            self.state = state
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            publishDocument(from: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            publishSelection(from: textView)
        }

        func replaceDocument(_ document: RichTextDocument) {
            guard let textView else { return }
            replaceDocument(document, in: textView)
        }

        func applyExternalDocumentIfNeeded(_ document: RichTextDocument) {
            guard let textView else { return }
            let normalized = document.normalized
            guard normalized != lastNativeDocument else { return }
            replaceDocument(normalized, in: textView)
        }

        func toggleBold() {
            let target = !state.selectionSummary.attributes.isBold
            applyToSelection { $0.isBold = target }
        }

        func toggleItalic() {
            let target = !state.selectionSummary.attributes.isItalic
            applyToSelection { $0.isItalic = target }
        }

        func toggleUnderline() {
            let target = !state.selectionSummary.attributes.isUnderline
            applyToSelection { $0.isUnderline = target }
        }

        func setColor(_ colorName: String) {
            applyToSelection { $0.colorName = colorName }
        }

        func setFontName(_ fontName: String) {
            applyToSelection { $0.fontName = fontName }
        }

        func setFontSize(_ fontSize: Double) {
            applyToSelection { $0.fontSize = TextStyle.clampedFontSize(fontSize) }
        }

        func setAlignment(_ alignment: TextAlignment) {
            guard let textView else { return }
            var document = currentDocument(from: textView)
            document.paragraph.textAlignment = alignment
            replaceDocument(document, in: textView, preservingSelection: true)
            publishDocument(from: textView)
            publishSelection(from: textView)
        }

        private func replaceDocument(
            _ document: RichTextDocument,
            in textView: NSTextView,
            preservingSelection: Bool = false
        ) {
            let range = preservingSelection ? textView.selectedRange() : NSRange(location: 0, length: 0)
            isReplacingText = true
            textView.textStorage?.setAttributedString(NativeRichText.attributedString(from: document))
            textView.alignment = NativeRichText.nativeAlignment(from: document.paragraph.alignmentRaw)
            textView.typingAttributes = NativeRichText.nativeAttributes(
                for: document.firstAttributes ?? state.selectionSummary.attributes,
                alignmentRaw: document.paragraph.alignmentRaw
            )
            textView.setSelectedRange(clamped(range, length: textView.textStorage?.length ?? 0))
            isReplacingText = false
            lastNativeDocument = document.normalized
            state.document = document.normalized
            publishSelection(from: textView)
        }

        private func applyToSelection(_ transform: (inout RichTextAttributes) -> Void) {
            guard let textView,
                  let storage = textView.textStorage else { return }
            let selectedRange = textView.selectedRange()
            let alignmentRaw = NativeRichText.rawAlignment(from: textView.alignment)

            if selectedRange.length == 0 {
                var attrs = NativeRichText.richTextAttributes(
                    from: textView.typingAttributes,
                    fallback: state.selectionSummary.attributes
                )
                transform(&attrs)
                textView.typingAttributes = NativeRichText.nativeAttributes(
                    for: attrs,
                    alignmentRaw: alignmentRaw
                )
                guard storage.length > 0 else {
                    state.selectionSummary = RichTextSelectionSummary(hasSelection: false, attributes: attrs)
                    return
                }
            }

            let targetRange = selectedRange.length == 0
                ? NSRange(location: 0, length: storage.length)
                : selectedRange
            let safeRange = clamped(targetRange, length: storage.length)
            guard safeRange.length > 0 else { return }
            let mutable = NSMutableAttributedString(attributedString: storage)
            mutable.enumerateAttributes(in: safeRange, options: []) { attributes, range, _ in
                var attrs = NativeRichText.richTextAttributes(
                    from: attributes,
                    fallback: state.selectionSummary.attributes
                )
                transform(&attrs)
                mutable.setAttributes(
                    NativeRichText.nativeAttributes(for: attrs, alignmentRaw: alignmentRaw),
                    range: range
                )
            }

            isReplacingText = true
            storage.setAttributedString(mutable)
            textView.alignment = NativeRichText.nativeAlignment(from: alignmentRaw)
            textView.setSelectedRange(
                selectedRange.length == 0 ? clamped(selectedRange, length: storage.length) : safeRange
            )
            isReplacingText = false
            publishDocument(from: textView)
            publishSelection(from: textView)
        }

        private func publishDocument(from textView: NSTextView) {
            guard !isReplacingText else { return }
            let document = currentDocument(from: textView)
            lastNativeDocument = document
            state.document = document
        }

        private func publishSelection(from textView: NSTextView) {
            let range = textView.selectedRange()
            let storage = textView.textStorage ?? NSTextStorage(string: "")
            let attrs: RichTextAttributes
            if range.length > 0, storage.length > 0 {
                let location = min(range.location, max(storage.length - 1, 0))
                attrs = NativeRichText.richTextAttributes(
                    from: storage.attributes(at: location, effectiveRange: nil),
                    fallback: state.selectionSummary.attributes
                )
            } else {
                attrs = NativeRichText.richTextAttributes(
                    from: textView.typingAttributes,
                    fallback: state.selectionSummary.attributes
                )
            }
            state.selectionSummary = RichTextSelectionSummary(
                hasSelection: range.length > 0,
                attributes: attrs
            )
        }

        private func currentDocument(from textView: NSTextView) -> RichTextDocument {
            NativeRichText.document(
                from: textView.attributedString(),
                alignmentRaw: NativeRichText.rawAlignment(from: textView.alignment)
            )
        }

        private func clamped(_ range: NSRange, length: Int) -> NSRange {
            let location = min(max(range.location, 0), length)
            let availableLength = max(0, length - location)
            return NSRange(location: location, length: min(range.length, availableLength))
        }
    }
}

private final class PastingRichTextView: NSTextView {
    override func paste(_ sender: Any?) {
        guard let pasted = readPasteboardText() else {
            super.paste(sender)
            return
        }
        insertText(pasted, replacementRange: selectedRange())
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let string = insertString as? String {
            super.insertText(string.normalizedRichEditorLineBreaks, replacementRange: replacementRange)
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
        }
    }

    private func readPasteboardText() -> String? {
        RichPasteboardTextReader.firstNonEmpty([
            NSPasteboard.general.string(forType: .string)
        ])
    }
}

#else

private struct PlatformRichTextEditor: View {
    @ObservedObject var state: RichTextEditingState
    let isFocused: Bool

    var body: some View {
        TextEditor(text: Binding(
            get: { state.document.plainText },
            set: { state.document = state.document.replacingPlainText($0, attributes: state.selectionSummary.attributes) }
        ))
    }
}

#endif
