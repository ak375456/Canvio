//
//  PastePreservingTextEditor.swift
//  Ponder
//

import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct PastePreservingTextEditor: View {
    @Binding var text: String
    let fontName: String
    let fontSize: Double
    let isBold: Bool
    let isItalic: Bool
    let isFocused: Bool

    var body: some View {
        PlatformPastePreservingTextEditor(
            text: $text,
            fontName: fontName,
            fontSize: fontSize,
            isBold: isBold,
            isItalic: isItalic,
            isFocused: isFocused
        )
        .onChange(of: text) { _, newValue in
            let normalized = newValue.normalizedTextLineBreaks
            if normalized != newValue {
                text = normalized
            }
        }
    }
}

private extension String {
    nonisolated var normalizedTextLineBreaks: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0085}", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}

private enum PasteboardTextReader {
    nonisolated static func string(fromHTML data: Data) -> String? {
        attributedString(
            from: data,
            type: .html,
            encoding: String.Encoding.utf8.rawValue
        )?.string.normalizedTextLineBreaks
    }

    nonisolated static func string(fromRTF data: Data) -> String? {
        attributedString(from: data, type: .rtf)?.string.normalizedTextLineBreaks
    }

    nonisolated private static func attributedString(
        from data: Data,
        type: NSAttributedString.DocumentType,
        encoding: UInt? = nil
    ) -> NSAttributedString? {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: type
        ]
        if let encoding {
            options[.characterEncoding] = encoding
        }
        return try? NSAttributedString(data: data, options: options, documentAttributes: nil)
    }

    nonisolated static func firstNonEmpty(_ candidates: [String?]) -> String? {
        candidates
            .compactMap { $0?.normalizedTextLineBreaks }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

#if os(macOS)
private struct PlatformPastePreservingTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontName: String
    let fontSize: Double
    let isBold: Bool
    let isItalic: Bool
    let isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PastingTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
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
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let normalized = text.normalizedTextLineBreaks
        if textView.string != normalized {
            textView.string = normalized
        }
        textView.font = makeFont()
        if !isFocused {
            context.coordinator.didApplyInitialFocus = false
        } else if !context.coordinator.didApplyInitialFocus {
            if scrollView.window?.firstResponder === textView ||
                scrollView.window?.makeFirstResponder(textView) == true {
                context.coordinator.didApplyInitialFocus = true
            }
        }
    }

    private func makeFont() -> NSFont {
        let base: NSFont
        if fontName == "system" {
            base = .systemFont(ofSize: fontSize)
        } else {
            base = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        }

        var traits: NSFontTraitMask = []
        if isBold { traits.insert(.boldFontMask) }
        if isItalic { traits.insert(.italicFontMask) }

        guard !traits.isEmpty else {
            return base
        }
        return NSFontManager.shared.convert(base, toHaveTrait: traits)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        var didApplyInitialFocus = false

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string.normalizedTextLineBreaks
        }
    }
}

private final class PastingTextView: NSTextView {
    override func paste(_ sender: Any?) {
        guard let pasted = readPasteboardText() else {
            super.paste(sender)
            return
        }
        insertText(pasted, replacementRange: selectedRange())
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let string = insertString as? String {
            super.insertText(string.normalizedTextLineBreaks, replacementRange: replacementRange)
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
        }
    }

    private func readPasteboardText() -> String? {
        let pasteboard = NSPasteboard.general
        return PasteboardTextReader.firstNonEmpty([
            pasteboard.data(forType: .html).flatMap(PasteboardTextReader.string(fromHTML:)),
            pasteboard.data(forType: .rtf).flatMap(PasteboardTextReader.string(fromRTF:)),
            pasteboard.string(forType: .string)
        ])
    }
}
#elseif canImport(UIKit)
private struct PlatformPastePreservingTextEditor: UIViewRepresentable {
    @Binding var text: String
    let fontName: String
    let fontSize: Double
    let isBold: Bool
    let isItalic: Bool
    let isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> PastingTextView {
        let textView = PastingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ textView: PastingTextView, context: Context) {
        let normalized = text.normalizedTextLineBreaks
        if textView.text != normalized {
            textView.text = normalized
        }
        textView.font = makeFont()
        textView.textColor = .label
        if !isFocused {
            context.coordinator.didApplyInitialFocus = false
        } else if !context.coordinator.didApplyInitialFocus {
            if textView.isFirstResponder || textView.becomeFirstResponder() {
                context.coordinator.didApplyInitialFocus = true
            }
        }
    }

    private func makeFont() -> UIFont {
        let descriptor: UIFontDescriptor
        if fontName == "system" {
            descriptor = UIFont.systemFont(ofSize: fontSize).fontDescriptor
        } else {
            descriptor = UIFontDescriptor(name: fontName, size: fontSize)
        }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if isBold { traits.insert(.traitBold) }
        if isItalic { traits.insert(.traitItalic) }

        let styledDescriptor = descriptor.withSymbolicTraits(traits) ?? descriptor
        return UIFont(descriptor: styledDescriptor, size: fontSize)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        weak var textView: UITextView?
        var didApplyInitialFocus = false

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text.normalizedTextLineBreaks
        }
    }
}

private final class PastingTextView: UITextView {
    override func paste(_ sender: Any?) {
        guard let pasted = readPasteboardText() else {
            super.paste(sender)
            return
        }
        insertText(pasted)
    }

    override func insertText(_ text: String) {
        super.insertText(text.normalizedTextLineBreaks)
    }

    private func readPasteboardText() -> String? {
        let pasteboard = UIPasteboard.general
        return PasteboardTextReader.firstNonEmpty([
            pasteboard.data(forPasteboardType: UTType.html.identifier).flatMap(PasteboardTextReader.string(fromHTML:)),
            pasteboard.data(forPasteboardType: UTType.rtf.identifier).flatMap(PasteboardTextReader.string(fromRTF:)),
            pasteboard.string
        ])
    }
}
#else
private struct PlatformPastePreservingTextEditor: View {
    @Binding var text: String
    let fontName: String
    let fontSize: Double
    let isBold: Bool
    let isItalic: Bool
    let isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
    }
}
#endif
