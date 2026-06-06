//
//  SettingsSheet.swift
//  Ponder
//
//  Created by aftab fazal qayum on 11/05/2026.
//

//
//  SettingsSheet.swift
//  Ponder
//

import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var pro = ProManager.shared
    @ObservedObject private var auth = AuthService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var showPaywall = false
    @State private var showAuth = false
    
    var exportButton: AnyView? = nil
    private let communityURL = URL(string: "https://www.reddit.com/r/Canvio/")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    themeSection
                    toolbarSection
                    canvasActionsSection
                    communitySection
                    selectionSection
                    canvasBackgroundSection
                    gridSection
                    exportSection
                }
                .padding(24)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet {
                settings.isPro = true
                if auth.currentUser == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showAuth = true
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
        .sheet(isPresented: $showAuth) {
            AuthView(
                title: "Sign in for Sync",
                subtitle: "Sign in to restore your canvases and sync Canvio Pro across all your devices.",
                onSignedIn: {
                    showAuth = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Text("Settings")
                .font(.title3.weight(.bold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Theme
    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("APPEARANCE")
            HStack(spacing: 10) {
                ForEach(AppTheme.allCases) { theme in
                    optionCard(
                        title: theme.title,
                        icon: theme.icon,
                        isSelected: settings.theme == theme
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.theme = theme
                        }
                    }
                }
            }
        }
    }

    // MARK: - Toolbar position
    private var toolbarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("TOOLBAR")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78))], spacing: 10) {
                ForEach(ToolbarPosition.allCases) { pos in
                    optionCard(
                        title: pos.title,
                        icon: pos.icon,
                        isSelected: settings.toolbarPosition == pos
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.toolbarPosition = pos
                        }
                    }
                }
            }
        }
    }

    // MARK: - Canvas actions
    private var canvasActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("CANVAS ACTIONS")
            VStack(alignment: .leading, spacing: 10) {
                instructionRow(icon: "doc.on.doc", text: "Hold any item on the canvas to duplicate it.")
                instructionRow(icon: "checkmark.circle", text: "To duplicate multiple items, hold the canvas, select items, then tap Duplicate.")
                instructionRow(icon: "text.cursor", text: "Double tap on the canvas to start typing directly.")
            }
        }
    }

    // MARK: - Community
    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("COMMUNITY")
            Button {
                openURL(communityURL)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.14))
                            .frame(width: 38, height: 38)
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Canvio Community")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Showcase your canvas, report a bug, or request a feature on Reddit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the Canvio Reddit community in your browser.")
        }
    }

    // MARK: - Selection
    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("SELECTION")
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { settings.overlapStackPickerEnabled },
                    set: { settings.overlapStackPickerEnabled = $0 }
                )) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "square.3.layers.3d")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Overlapping item picker")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("When several items overlap, tapping that spot can show a small picker so you can choose the item behind the front one. It only checks the stack while this is enabled.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .toggleStyle(.switch)
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Canvas background
    private var canvasBackgroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("CANVAS BACKGROUND")
            HStack(spacing: 10) {
                ForEach(CanvasBackgroundMode.allCases) { mode in
                    backgroundModeButton(mode)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104))], spacing: 10) {
                ForEach(CanvasBackgroundPalette.allCases) { palette in
                    backgroundPaletteCard(palette)
                }
            }
        }
    }

    private func backgroundModeButton(_ mode: CanvasBackgroundMode) -> some View {
        let selected = settings.canvasBackgroundMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.canvasBackgroundMode = mode
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: mode.icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(mode.title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(selected ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.accentColor : Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    private func backgroundPaletteCard(_ palette: CanvasBackgroundPalette) -> some View {
        let selected = settings.canvasBackgroundPalette == palette
        let locked = isPremiumBackgroundPalette(palette) && !pro.isPro
        return Button {
            if locked {
                showPaywall = true
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    settings.canvasBackgroundPalette = palette
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CanvasBackgroundSwatch(
                    mode: settings.canvasBackgroundMode,
                    palette: palette,
                    systemColorScheme: colorScheme
                )
                .frame(height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

                HStack(spacing: 5) {
                    Text(palette.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(selected ? .white : Color.primary.opacity(0.82))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if locked {
                        Text("PRO")
                            .font(.system(size: 7, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor)
                            .foregroundStyle(Color.white)
                            .clipShape(Capsule())
                    } else if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.accentColor : Color.secondary.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        selected ? Color.clear : Color.secondary.opacity(0.15),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func isPremiumBackgroundPalette(_ palette: CanvasBackgroundPalette) -> Bool {
        switch palette {
        case .neutral, .amber:
            return false
        case .paper, .slate, .sky, .mint, .rose, .lavender:
            return true
        }
    }

    // MARK: - Grid style
    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("CANVAS GRID")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78))], spacing: 10) {
                ForEach(GridStyle.allCases) { style in
                    optionCard(
                        title: style.title,
                        icon: style.icon,
                        isSelected: settings.effectiveGridStyle == style,
                        isProFeature: style != .dotted
                    ) {
                        if style == .dotted || pro.isPro {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                settings.gridStyle = style
                            }
                        } else {
                            showPaywall = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Export
    @ViewBuilder
    private var exportSection: some View {
        if let exportButton {
            VStack(alignment: .leading, spacing: 12) {
                label("EXPORT")
                exportButton
            }
        }
    }

    // MARK: - Helpers
    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(1)
    }

    private func optionCard(title: String, icon: String, isSelected: Bool, isProFeature: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                HStack(spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.8))
                    if isProFeature && !pro.isPro {
                        Text("PRO")
                            .font(.system(size: 7, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor)
                            .foregroundStyle(Color.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.clear : Color.secondary.opacity(0.15),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func instructionRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CanvasBackgroundSwatch: View {
    let mode: CanvasBackgroundMode
    let palette: CanvasBackgroundPalette
    let systemColorScheme: ColorScheme

    private var appearance: CanvasBackgroundAppearance {
        palette.appearance(for: mode.resolvedColorScheme(system: systemColorScheme))
    }

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(appearance.base))

            let bandWidth = max(1, size.width / 4)
            for index in 0..<4 where index.isMultiple(of: 2) {
                let rect = CGRect(x: CGFloat(index) * bandWidth, y: 0,
                                  width: bandWidth, height: size.height)
                context.fill(Path(rect), with: .color(appearance.alternate))
            }

            var x = bandWidth
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(appearance.line), lineWidth: 1)
                x += bandWidth
            }
        }
    }
}
