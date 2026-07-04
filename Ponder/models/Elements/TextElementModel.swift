//
//  TextElementModel.swift
//  Ponder
//

import Foundation
import SwiftData
import SwiftUI

@Model
class TextElementModel: LayerableElement {
    var id: UUID
    var canvasID: UUID
    var text: String
    var x: Double
    var y: Double
    var fontSize: Double
    var isBold: Bool
    var isItalic: Bool
    var isUnderline: Bool = false
    var colorName: String
    var fontName: String = "system"
    var alignmentRaw: String = "leading"
    var zIndex: Int = 0
    var groupID: UUID? = nil
    var updatedAt: Date = Date()
    var richTextData: Data? = nil

    // Optional provenance for text extracted from a PDF selection.
    var sourcePDFDocumentID: UUID? = nil
    var sourcePDFPageIndex: Int? = nil
    var sourcePDFRectsData: Data? = nil

    // Card background & stroke — default "none" = no card
    var bgColorName: String     = "none"
    var strokeColorName: String = "none"
    var strokeWidth: Double     = 2.0

    init(canvasID: UUID, text: String = "", x: Double = 0, y: Double = 0) {
        self.id             = UUID()
        self.canvasID       = canvasID
        self.text           = text
        self.x              = x
        self.y              = y
        self.fontSize       = 16
        self.isBold         = false
        self.isItalic       = false
        self.isUnderline    = false
        self.colorName      = "primary"
        self.fontName       = "system"
        self.alignmentRaw   = "leading"
        self.zIndex         = 0
        self.groupID        = nil
        self.updatedAt      = Date()
        self.richTextData   = nil
        self.sourcePDFDocumentID = nil
        self.sourcePDFPageIndex = nil
        self.sourcePDFRectsData = nil
        self.bgColorName     = "none"
        self.strokeColorName = "none"
        self.strokeWidth     = 2.0
        rebuildRichTextFromLegacyStyle()
    }

    // MARK: - Computed helpers

    var textAlignment: TextAlignment {
        get {
            switch alignmentRaw {
            case "center":   return .center
            case "trailing": return .trailing
            default:         return .leading
            }
        }
        set {
            switch newValue {
            case .center:   alignmentRaw = "center"
            case .trailing: alignmentRaw = "trailing"
            default:        alignmentRaw = "leading"
            }
        }
    }

    var multilineAlignment: HorizontalAlignment {
        switch textAlignment {
        case .center:   return .center
        case .trailing: return .trailing
        default:        return .leading
        }
    }

    var hasCard: Bool { bgColorName != "none" || strokeColorName != "none" }

    var baseRichTextAttributes: RichTextAttributes {
        RichTextAttributes(
            fontName: fontName,
            fontSize: fontSize,
            isBold: isBold,
            isItalic: isItalic,
            isUnderline: isUnderline,
            colorName: colorName
        )
    }

    var richTextDocument: RichTextDocument? {
        get { RichTextDocument.decoded(from: richTextData) }
        set { richTextData = newValue?.encodedData() }
    }

    var resolvedRichTextDocument: RichTextDocument {
        if let doc = richTextDocument?.normalized,
           !doc.runs.isEmpty || text.isEmpty {
            return doc
        }
        return legacyRichTextDocument
    }

    var hasPartialRichTextStyling: Bool {
        resolvedRichTextDocument.hasRichStyling(comparedTo: baseRichTextAttributes)
    }

    func setRichTextDocument(_ document: RichTextDocument, mirrorLegacyStyle: Bool = true) {
        let normalized = document.normalized
        richTextData = normalized.encodedData()
        text = normalized.plainText
        alignmentRaw = normalized.paragraph.alignmentRaw

        guard mirrorLegacyStyle, let attrs = normalized.firstAttributes else { return }
        fontSize = attrs.fontSize
        isBold = attrs.isBold
        isItalic = attrs.isItalic
        isUnderline = attrs.isUnderline
        colorName = attrs.colorName
        fontName = attrs.fontName
    }

    func rebuildRichTextFromLegacyStyle() {
        setRichTextDocument(legacyRichTextDocument, mirrorLegacyStyle: false)
    }

    private var legacyRichTextDocument: RichTextDocument {
        RichTextDocument.legacy(
            text: text,
            fontSize: fontSize,
            isBold: isBold,
            isItalic: isItalic,
            isUnderline: isUnderline,
            colorName: colorName,
            fontName: fontName,
            alignmentRaw: alignmentRaw
        )
    }

    var sourcePDFRects: [PDFNormalizedRect] {
        get {
            guard let sourcePDFRectsData else { return [] }
            return (try? JSONDecoder().decode([PDFNormalizedRect].self, from: sourcePDFRectsData)) ?? []
        }
        set { sourcePDFRectsData = try? JSONEncoder().encode(newValue) }
    }

    // MARK: - LayerableElement
    var layerTitle: String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Text" : String(t.prefix(28))
    }
    var layerIcon: String { "textformat" }
    var layerTint: Color  { .blue }
}
