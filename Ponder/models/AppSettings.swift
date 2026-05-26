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

enum ToolbarPosition: String, CaseIterable, Identifiable {
    case bottom
    case left
    case right
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottom: return "Bottom"
        case .left:   return "Left"
        case .right:  return "Right"
        case .hidden: return "Hidden"
        }
    }

    var icon: String {
        switch self {
        case .bottom: return "dock.rectangle"
        case .left:   return "sidebar.left"
        case .right:  return "sidebar.right"
        case .hidden: return "eye.slash"
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

@MainActor
class AppSettings: ObservableObject {
    @AppStorage("ponder.theme") private var themeRaw: String = AppTheme.system.rawValue
    @AppStorage("ponder.toolbarPosition") private var toolbarPositionRaw: String = ToolbarPosition.bottom.rawValue
    @AppStorage("ponder.gridStyle") private var gridStyleRaw: String = GridStyle.dotted.rawValue
    @AppStorage("isPro") private var isProRaw: Bool = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboardingRaw: Bool = false

    var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue; objectWillChange.send() }
    }

    var toolbarPosition: ToolbarPosition {
        get { ToolbarPosition(rawValue: toolbarPositionRaw) ?? .bottom }
        set { toolbarPositionRaw = newValue.rawValue; objectWillChange.send() }
    }

    var gridStyle: GridStyle {
        get { GridStyle(rawValue: gridStyleRaw) ?? .dotted }
        set { gridStyleRaw = newValue.rawValue; objectWillChange.send() }
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
}
