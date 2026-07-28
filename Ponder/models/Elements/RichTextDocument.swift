//
//  RichTextDocument.swift
//  Ponder
//

import Foundation
import SwiftUI

struct RichTextAttributes: Codable, Equatable {
    var fontName: String
    var fontSize: Double
    var isBold: Bool
    var isItalic: Bool
    var isUnderline: Bool
    var colorName: String

    init(
        fontName: String = "system",
        fontSize: Double = 16,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        colorName: String = "primary"
    ) {
        self.fontName = fontName
        self.fontSize = TextStyle.clampedFontSize(fontSize)
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.colorName = colorName
    }

    init(style: TextStyle) {
        self.init(
            fontName: style.fontName,
            fontSize: style.fontSize,
            isBold: style.isBold,
            isItalic: style.isItalic,
            isUnderline: style.isUnderline,
            colorName: style.colorName
        )
    }

    enum CodingKeys: String, CodingKey {
        case fontName
        case fontSize
        case bold
        case italic
        case underline
        case colorName
        case isBold
        case isItalic
        case isUnderline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontName = (try? container.decode(String.self, forKey: .fontName)) ?? "system"
        fontSize = TextStyle.clampedFontSize(
            (try? container.decode(Double.self, forKey: .fontSize)) ?? 16
        )
        isBold = (try? container.decode(Bool.self, forKey: .bold))
            ?? (try? container.decode(Bool.self, forKey: .isBold))
            ?? false
        isItalic = (try? container.decode(Bool.self, forKey: .italic))
            ?? (try? container.decode(Bool.self, forKey: .isItalic))
            ?? false
        isUnderline = (try? container.decode(Bool.self, forKey: .underline))
            ?? (try? container.decode(Bool.self, forKey: .isUnderline))
            ?? false
        colorName = (try? container.decode(String.self, forKey: .colorName)) ?? "primary"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontName, forKey: .fontName)
        try container.encode(TextStyle.clampedFontSize(fontSize), forKey: .fontSize)
        try container.encode(isBold, forKey: .bold)
        try container.encode(isItalic, forKey: .italic)
        try container.encode(isUnderline, forKey: .underline)
        try container.encode(colorName, forKey: .colorName)
    }

    func normalized(fontSizeDelta: Double = 0) -> RichTextAttributes {
        RichTextAttributes(
            fontName: fontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "system" : fontName,
            fontSize: TextStyle.clampedFontSize(fontSize + fontSizeDelta),
            isBold: isBold,
            isItalic: isItalic,
            isUnderline: isUnderline,
            colorName: colorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "primary" : colorName
        )
    }

    var swiftUIFont: Font {
        let size = TextStyle.clampedFontSize(fontSize)
        var font: Font = fontName == "system"
            ? .system(size: size)
            : .custom(fontName, size: size)
        if isBold { font = font.bold() }
        if isItalic { font = font.italic() }
        return font
    }
}

struct RichTextRun: Codable, Equatable {
    var text: String
    var attrs: RichTextAttributes

    init(text: String, attrs: RichTextAttributes) {
        self.text = text
        self.attrs = attrs.normalized()
    }
}

struct RichTextParagraph: Codable, Equatable {
    var alignmentRaw: String

    init(alignmentRaw: String = "leading") {
        self.alignmentRaw = RichTextParagraph.normalizedAlignment(alignmentRaw)
    }

    enum CodingKeys: String, CodingKey {
        case alignmentRaw
        case alignment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? container.decode(String.self, forKey: .alignmentRaw))
            ?? (try? container.decode(String.self, forKey: .alignment))
            ?? "leading"
        alignmentRaw = RichTextParagraph.normalizedAlignment(raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(alignmentRaw, forKey: .alignmentRaw)
    }

    var textAlignment: TextAlignment {
        get {
            switch alignmentRaw {
            case "center": return .center
            case "trailing": return .trailing
            default: return .leading
            }
        }
        set {
            switch newValue {
            case .center: alignmentRaw = "center"
            case .trailing: alignmentRaw = "trailing"
            default: alignmentRaw = "leading"
            }
        }
    }

    static func normalizedAlignment(_ raw: String) -> String {
        switch raw {
        case "center", "trailing": return raw
        default: return "leading"
        }
    }
}

struct RichTextDocument: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var runs: [RichTextRun]
    var paragraph: RichTextParagraph

    init(
        version: Int = RichTextDocument.currentVersion,
        runs: [RichTextRun] = [],
        paragraph: RichTextParagraph = RichTextParagraph()
    ) {
        self.version = max(1, version)
        self.runs = runs
        self.paragraph = paragraph
    }

    enum CodingKeys: String, CodingKey {
        case version
        case runs
        case paragraph
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = max(1, (try? container.decode(Int.self, forKey: .version)) ?? RichTextDocument.currentVersion)
        runs = (try? container.decode([RichTextRun].self, forKey: .runs)) ?? []
        paragraph = (try? container.decode(RichTextParagraph.self, forKey: .paragraph)) ?? RichTextParagraph()
    }

    var plainText: String {
        runs.map(\.text).joined()
    }

    var firstAttributes: RichTextAttributes? {
        runs.first(where: { !$0.text.isEmpty })?.attrs.normalized()
            ?? runs.first?.attrs.normalized()
    }

    var normalized: RichTextDocument {
        var merged: [RichTextRun] = []
        for run in runs where !run.text.isEmpty {
            let normalizedRun = RichTextRun(text: run.text.normalizedRichTextLineBreaks,
                                            attrs: run.attrs.normalized())
            if let last = merged.last, last.attrs == normalizedRun.attrs {
                merged[merged.count - 1].text += normalizedRun.text
            } else {
                merged.append(normalizedRun)
            }
        }
        return RichTextDocument(
            version: RichTextDocument.currentVersion,
            runs: merged,
            paragraph: RichTextParagraph(alignmentRaw: paragraph.alignmentRaw)
        )
    }

    func encodedData() -> Data? {
        try? JSONEncoder().encode(normalized)
    }

    static func decoded(from data: Data?) -> RichTextDocument? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(RichTextDocument.self, from: data).normalized
    }

    static func legacy(
        text: String,
        fontSize: Double,
        isBold: Bool,
        isItalic: Bool,
        isUnderline: Bool,
        colorName: String,
        fontName: String,
        alignmentRaw: String
    ) -> RichTextDocument {
        let normalizedText = text.normalizedRichTextLineBreaks
        let attrs = RichTextAttributes(
            fontName: fontName,
            fontSize: fontSize,
            isBold: isBold,
            isItalic: isItalic,
            isUnderline: isUnderline,
            colorName: colorName
        )
        return RichTextDocument(
            runs: normalizedText.isEmpty ? [] : [RichTextRun(text: normalizedText, attrs: attrs)],
            paragraph: RichTextParagraph(alignmentRaw: alignmentRaw)
        ).normalized
    }

    func applyingToAllRuns(_ transform: (inout RichTextAttributes) -> Void) -> RichTextDocument {
        var copy = normalized
        copy.runs = copy.runs.map { run in
            var attrs = run.attrs.normalized()
            transform(&attrs)
            return RichTextRun(text: run.text, attrs: attrs)
        }
        return copy.normalized
    }

    func replacingPlainText(_ text: String, attributes: RichTextAttributes) -> RichTextDocument {
        RichTextDocument(
            runs: text.isEmpty ? [] : [RichTextRun(text: text.normalizedRichTextLineBreaks, attrs: attributes)],
            paragraph: paragraph
        ).normalized
    }

    func attributedString(fontSizeDelta: Double = 0) -> AttributedString {
        var output = AttributedString()
        for run in normalized.runs {
            let attrs = run.attrs.normalized(fontSizeDelta: fontSizeDelta)
            var segment = AttributedString(run.text)
            segment.font = attrs.swiftUIFont
            segment.foregroundColor = TextStyle.color(named: attrs.colorName)
            if attrs.isUnderline {
                segment.underlineStyle = .single
            }
            output += segment
        }
        return output
    }

    func hasRichStyling(comparedTo base: RichTextAttributes) -> Bool {
        let doc = normalized
        guard !doc.runs.isEmpty else { return false }
        if doc.runs.count > 1 { return true }
        return doc.runs[0].attrs.normalized() != base.normalized()
    }
}

private extension String {
    var normalizedRichTextLineBreaks: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0085}", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
