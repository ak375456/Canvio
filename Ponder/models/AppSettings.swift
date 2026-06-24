//
//  AppSettings.swift
//  Ponder
//
//  Created by aftab fazal qayum on 11/05/2026.
//

//
//  AppSettings.swift
//  Ponder
//

import SwiftUI
import Combine

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

enum ToolbarPosition: String {
    case bottom
    case hidden
}

enum ToolbarStyle: String, CaseIterable, Identifiable {
    case floatingBar
    case compactButtons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .floatingBar: return "Floating Bar"
        case .compactButtons: return "Compact Buttons"
        }
    }

    var icon: String {
        switch self {
        case .floatingBar: return "capsule"
        case .compactButtons: return "square.grid.3x3"
        }
    }
}

enum GridStyle: String, CaseIterable, Identifiable {
    case dotted
    case squares
    case horizontal
    case vertical
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dotted:     return "Dots"
        case .squares:    return "Grid"
        case .horizontal: return "Lines"
        case .vertical:   return "Columns"
        case .none:       return "Blank"
        }
    }

    var icon: String {
        switch self {
        case .dotted:     return "circle.grid.2x2"
        case .squares:    return "square.grid.3x3"
        case .horizontal: return "line.3.horizontal"
        case .vertical:   return "rectangle.split.3x1"
        case .none:       return "square"
        }
    }
}

enum HandwritingTextGrouping: String, CaseIterable, Identifiable {
    case oneBlock
    case automatic
    case eachLine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneBlock:  return "One Block"
        case .automatic: return "Automatic"
        case .eachLine:  return "Each Line"
        }
    }

    var shortTitle: String {
        switch self {
        case .oneBlock:  return "Block"
        case .automatic: return "Auto"
        case .eachLine:  return "Lines"
        }
    }

    var icon: String {
        switch self {
        case .oneBlock:  return "text.alignleft"
        case .automatic: return "wand.and.stars"
        case .eachLine:  return "text.line.first.and.arrowtriangle.forward"
        }
    }

    var explanation: String {
        switch self {
        case .oneBlock:
            return "Keep everything written in the session together as one editable text object."
        case .automatic:
            return "Keep nearby lines together and separate text that is written farther apart."
        case .eachLine:
            return "Create an independently editable text object for every recognized line."
        }
    }
}

enum CanvasBackgroundMode: String, CaseIterable, Identifiable {
    case adaptive
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adaptive: return "Auto"
        case .light:    return "Light"
        case .dark:     return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .adaptive: return "circle.lefthalf.filled"
        case .light:    return "sun.max"
        case .dark:     return "moon"
        }
    }

    static func matching(theme: AppTheme) -> CanvasBackgroundMode {
        switch theme {
        case .system: return .adaptive
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var matchingTheme: AppTheme {
        switch self {
        case .adaptive: return .system
        case .light:    return .light
        case .dark:     return .dark
        }
    }

    func resolvedColorScheme(system: ColorScheme) -> ColorScheme {
        switch self {
        case .adaptive: return system
        case .light:    return .light
        case .dark:     return .dark
        }
    }
}

struct CanvasBackgroundAppearance {
    let base: Color
    let alternate: Color
    let line: Color
    let dot: Color
}

enum CanvasBackgroundPalette: String, CaseIterable, Identifiable {
    case neutral
    case paper
    case slate
    case sky
    case mint
    case rose
    case lavender
    case amber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neutral:  return "Default"
        case .paper:    return "Paper"
        case .slate:    return "Slate"
        case .sky:      return "Sky"
        case .mint:     return "Mint"
        case .rose:     return "Rose"
        case .lavender: return "Violet"
        case .amber:    return "Amber"
        }
    }

    func appearance(for colorScheme: ColorScheme) -> CanvasBackgroundAppearance {
        switch (self, colorScheme) {
        case (.neutral, .dark):
            return .init(base: Color(red: 0.03, green: 0.03, blue: 0.04),
                         alternate: Color(red: 0.08, green: 0.08, blue: 0.09),
                         line: Color.white.opacity(0.12),
                         dot: Color.white.opacity(0.28))
        case (.neutral, _):
            return .init(base: Color(red: 0.97, green: 0.97, blue: 0.98),
                         alternate: Color(red: 0.91, green: 0.92, blue: 0.94),
                         line: Color.black.opacity(0.12),
                         dot: Color.black.opacity(0.28))

        case (.paper, .dark):
            return .init(base: Color(red: 0.10, green: 0.10, blue: 0.10),
                         alternate: Color(red: 0.15, green: 0.15, blue: 0.14),
                         line: Color.white.opacity(0.12),
                         dot: Color.white.opacity(0.26))
        case (.paper, _):
            return .init(base: Color.white,
                         alternate: Color(red: 0.94, green: 0.95, blue: 0.95),
                         line: Color.black.opacity(0.10),
                         dot: Color.black.opacity(0.24))

        case (.slate, .dark):
            return .init(base: Color(red: 0.06, green: 0.09, blue: 0.13),
                         alternate: Color(red: 0.10, green: 0.14, blue: 0.20),
                         line: Color.white.opacity(0.13),
                         dot: Color.white.opacity(0.28))
        case (.slate, _):
            return .init(base: Color(red: 0.92, green: 0.95, blue: 0.98),
                         alternate: Color(red: 0.84, green: 0.89, blue: 0.95),
                         line: Color(red: 0.14, green: 0.20, blue: 0.28).opacity(0.14),
                         dot: Color(red: 0.14, green: 0.20, blue: 0.28).opacity(0.30))

        case (.sky, .dark):
            return .init(base: Color(red: 0.04, green: 0.11, blue: 0.18),
                         alternate: Color(red: 0.07, green: 0.17, blue: 0.27),
                         line: Color(red: 0.72, green: 0.88, blue: 1.0).opacity(0.15),
                         dot: Color(red: 0.72, green: 0.88, blue: 1.0).opacity(0.32))
        case (.sky, _):
            return .init(base: Color(red: 0.91, green: 0.97, blue: 1.0),
                         alternate: Color(red: 0.80, green: 0.92, blue: 1.0),
                         line: Color(red: 0.15, green: 0.39, blue: 0.60).opacity(0.14),
                         dot: Color(red: 0.15, green: 0.39, blue: 0.60).opacity(0.30))

        case (.mint, .dark):
            return .init(base: Color(red: 0.04, green: 0.13, blue: 0.09),
                         alternate: Color(red: 0.07, green: 0.20, blue: 0.14),
                         line: Color(red: 0.70, green: 0.95, blue: 0.78).opacity(0.14),
                         dot: Color(red: 0.70, green: 0.95, blue: 0.78).opacity(0.30))
        case (.mint, _):
            return .init(base: Color(red: 0.91, green: 1.0, blue: 0.96),
                         alternate: Color(red: 0.80, green: 0.96, blue: 0.88),
                         line: Color(red: 0.10, green: 0.45, blue: 0.26).opacity(0.14),
                         dot: Color(red: 0.10, green: 0.45, blue: 0.26).opacity(0.30))

        case (.rose, .dark):
            return .init(base: Color(red: 0.15, green: 0.06, blue: 0.09),
                         alternate: Color(red: 0.22, green: 0.09, blue: 0.13),
                         line: Color(red: 1.0, green: 0.72, blue: 0.79).opacity(0.14),
                         dot: Color(red: 1.0, green: 0.72, blue: 0.79).opacity(0.30))
        case (.rose, _):
            return .init(base: Color(red: 1.0, green: 0.94, blue: 0.96),
                         alternate: Color(red: 1.0, green: 0.84, blue: 0.89),
                         line: Color(red: 0.64, green: 0.16, blue: 0.27).opacity(0.14),
                         dot: Color(red: 0.64, green: 0.16, blue: 0.27).opacity(0.30))

        case (.lavender, .dark):
            return .init(base: Color(red: 0.10, green: 0.07, blue: 0.16),
                         alternate: Color(red: 0.16, green: 0.11, blue: 0.25),
                         line: Color(red: 0.78, green: 0.68, blue: 1.0).opacity(0.14),
                         dot: Color(red: 0.78, green: 0.68, blue: 1.0).opacity(0.30))
        case (.lavender, _):
            return .init(base: Color(red: 0.96, green: 0.94, blue: 1.0),
                         alternate: Color(red: 0.88, green: 0.84, blue: 1.0),
                         line: Color(red: 0.30, green: 0.18, blue: 0.58).opacity(0.14),
                         dot: Color(red: 0.30, green: 0.18, blue: 0.58).opacity(0.30))

        case (.amber, .dark):
            return .init(base: Color(red: 0.15, green: 0.10, blue: 0.04),
                         alternate: Color(red: 0.23, green: 0.16, blue: 0.07),
                         line: Color(red: 1.0, green: 0.78, blue: 0.42).opacity(0.14),
                         dot: Color(red: 1.0, green: 0.78, blue: 0.42).opacity(0.30))
        case (.amber, _):
            return .init(base: Color(red: 1.0, green: 0.97, blue: 0.90),
                         alternate: Color(red: 1.0, green: 0.90, blue: 0.72),
                         line: Color(red: 0.62, green: 0.36, blue: 0.08).opacity(0.14),
                         dot: Color(red: 0.62, green: 0.36, blue: 0.08).opacity(0.30))
        }
    }
}

@MainActor
class AppSettings: ObservableObject {
    @AppStorage("ponder.theme") private var themeRaw: String = AppTheme.system.rawValue
    @AppStorage("ponder.toolbarPosition") private var toolbarPositionRaw: String = ToolbarPosition.bottom.rawValue
    @AppStorage("ponder.toolbarStyle") private var toolbarStyleRaw: String = ToolbarStyle.floatingBar.rawValue
    @AppStorage("ponder.gridStyle") private var gridStyleRaw: String = GridStyle.dotted.rawValue
    @AppStorage("ponder.canvasBackgroundMode") private var canvasBackgroundModeRaw: String = CanvasBackgroundMode.adaptive.rawValue
    @AppStorage("ponder.canvasBackgroundPalette") private var canvasBackgroundPaletteRaw: String = CanvasBackgroundPalette.neutral.rawValue
    @AppStorage("ponder.overlapStackPickerEnabled") private var overlapStackPickerEnabledRaw: Bool = false
    @AppStorage("ponder.smartShapeSnappingEnabled") private var smartShapeSnappingEnabledRaw: Bool = true
    @AppStorage("ponder.handwritingToTextEnabled") private var handwritingToTextEnabledRaw: Bool = true
    @AppStorage("ponder.handwritingToTextStrictness") private var handwritingToTextStrictnessRaw: Double = 0.35
    @AppStorage("ponder.handwritingTextGrouping") private var handwritingTextGroupingRaw: String = HandwritingTextGrouping.automatic.rawValue
    @AppStorage("ponder.lastTextFontName") private var lastTextFontNameRaw: String = "system"
    @AppStorage("ponder.lastTextFontSize") private var lastTextFontSizeRaw: Double = 16
    @AppStorage("ponder.lastTextColorName") private var lastTextColorNameRaw: String = "primary"
    @AppStorage("ponder.lastTextIsBold") private var lastTextIsBoldRaw: Bool = false
    @AppStorage("ponder.lastTextIsItalic") private var lastTextIsItalicRaw: Bool = false
    @AppStorage("ponder.lastTextIsUnderline") private var lastTextIsUnderlineRaw: Bool = false
    @AppStorage("ponder.lastTextAlignment") private var lastTextAlignmentRaw: String = "leading"
    @AppStorage("ponder.lastTextBgColorName") private var lastTextBgColorNameRaw: String = "none"
    @AppStorage("ponder.lastTextStrokeColorName") private var lastTextStrokeColorNameRaw: String = "none"
    @AppStorage("ponder.lastTextStrokeWidth") private var lastTextStrokeWidthRaw: Double = 2.0
    @AppStorage("isPro") private var isProRaw: Bool = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboardingRaw: Bool = false

    var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .system }
        set {
            themeRaw = newValue.rawValue
            canvasBackgroundModeRaw = CanvasBackgroundMode.matching(theme: newValue).rawValue
            objectWillChange.send()
        }
    }

    var toolbarPosition: ToolbarPosition {
        get { ToolbarPosition(rawValue: toolbarPositionRaw) ?? .bottom }
        set { toolbarPositionRaw = newValue.rawValue; objectWillChange.send() }
    }

    var toolbarStyle: ToolbarStyle {
        get { ToolbarStyle(rawValue: toolbarStyleRaw) ?? .floatingBar }
        set { toolbarStyleRaw = newValue.rawValue; objectWillChange.send() }
    }

    var gridStyle: GridStyle {
        get { GridStyle(rawValue: gridStyleRaw) ?? .dotted }
        set { gridStyleRaw = newValue.rawValue; objectWillChange.send() }
    }

    var canvasBackgroundMode: CanvasBackgroundMode {
        get { CanvasBackgroundMode.matching(theme: theme) }
        set {
            canvasBackgroundModeRaw = newValue.rawValue
            themeRaw = newValue.matchingTheme.rawValue
            objectWillChange.send()
        }
    }

    var canvasBackgroundPalette: CanvasBackgroundPalette {
        get { CanvasBackgroundPalette(rawValue: canvasBackgroundPaletteRaw) ?? .neutral }
        set { canvasBackgroundPaletteRaw = newValue.rawValue; objectWillChange.send() }
    }

    var overlapStackPickerEnabled: Bool {
        get { overlapStackPickerEnabledRaw }
        set { overlapStackPickerEnabledRaw = newValue; objectWillChange.send() }
    }

    var smartShapeSnappingEnabled: Bool {
        get { smartShapeSnappingEnabledRaw }
        set { smartShapeSnappingEnabledRaw = newValue; objectWillChange.send() }
    }

    var handwritingToTextEnabled: Bool {
        get { handwritingToTextEnabledRaw }
        set { handwritingToTextEnabledRaw = newValue; objectWillChange.send() }
    }

    var handwritingToTextStrictness: Double {
        get { handwritingToTextStrictnessRaw }
        set { handwritingToTextStrictnessRaw = max(0, min(1, newValue)); objectWillChange.send() }
    }

    var handwritingTextGrouping: HandwritingTextGrouping {
        get { HandwritingTextGrouping(rawValue: handwritingTextGroupingRaw) ?? .automatic }
        set { handwritingTextGroupingRaw = newValue.rawValue; objectWillChange.send() }
    }

    var lastTextFontName: String {
        get { lastTextFontNameRaw }
        set { lastTextFontNameRaw = newValue; objectWillChange.send() }
    }

    var lastTextFontSize: Double {
        get { lastTextFontSizeRaw }
        set { lastTextFontSizeRaw = TextStyle.clampedFontSize(newValue); objectWillChange.send() }
    }

    var lastTextColorName: String {
        get { lastTextColorNameRaw }
        set { lastTextColorNameRaw = newValue; objectWillChange.send() }
    }

    var lastTextIsBold: Bool {
        get { lastTextIsBoldRaw }
        set { lastTextIsBoldRaw = newValue; objectWillChange.send() }
    }

    var lastTextIsItalic: Bool {
        get { lastTextIsItalicRaw }
        set { lastTextIsItalicRaw = newValue; objectWillChange.send() }
    }

    var lastTextIsUnderline: Bool {
        get { lastTextIsUnderlineRaw }
        set { lastTextIsUnderlineRaw = newValue; objectWillChange.send() }
    }

    var lastTextAlignmentRawValue: String {
        get { lastTextAlignmentRaw }
        set { lastTextAlignmentRaw = newValue; objectWillChange.send() }
    }

    var lastTextBgColorName: String {
        get { lastTextBgColorNameRaw }
        set { lastTextBgColorNameRaw = newValue; objectWillChange.send() }
    }

    var lastTextStrokeColorName: String {
        get { lastTextStrokeColorNameRaw }
        set { lastTextStrokeColorNameRaw = newValue; objectWillChange.send() }
    }

    var lastTextStrokeWidth: Double {
        get { lastTextStrokeWidthRaw }
        set { lastTextStrokeWidthRaw = max(1, min(12, newValue)); objectWillChange.send() }
    }

    var isPro: Bool {
        get { isProRaw }
        set { isProRaw = newValue; objectWillChange.send() }
    }

    var hasSeenOnboarding: Bool {
        get { hasSeenOnboardingRaw }
        set { hasSeenOnboardingRaw = newValue; objectWillChange.send() }
    }

    var effectiveGridStyle: GridStyle {
        isPro ? gridStyle : .dotted
    }

    func rememberTextStyle(_ style: TextStyle) {
        lastTextFontNameRaw = style.fontName
        lastTextFontSizeRaw = TextStyle.clampedFontSize(style.fontSize)
        lastTextColorNameRaw = style.colorName
        lastTextIsBoldRaw = style.isBold
        lastTextIsItalicRaw = style.isItalic
        lastTextIsUnderlineRaw = style.isUnderline
        lastTextAlignmentRaw = style.alignmentRaw
        lastTextBgColorNameRaw = style.bgColorName
        lastTextStrokeColorNameRaw = style.strokeColorName
        lastTextStrokeWidthRaw = style.strokeWidth
        objectWillChange.send()
    }

    func lastTextStyle(text: String, estimatedFontSize: Double? = nil) -> TextStyle {
        TextStyle(
            text: text,
            fontSize: estimatedFontSize.map(TextStyle.clampedFontSize) ?? lastTextFontSizeRaw,
            isBold: lastTextIsBoldRaw,
            isItalic: lastTextIsItalicRaw,
            isUnderline: lastTextIsUnderlineRaw,
            colorName: lastTextColorNameRaw,
            fontName: lastTextFontNameRaw,
            alignmentRaw: lastTextAlignmentRaw,
            bgColorName: lastTextBgColorNameRaw,
            strokeColorName: lastTextStrokeColorNameRaw,
            strokeWidth: lastTextStrokeWidthRaw
        )
    }
}
