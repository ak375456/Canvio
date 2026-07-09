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
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var pro = ProManager.shared
    @ObservedObject private var auth = AuthService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var showPaywall = false
    @State private var showAuth = false
    @State private var isImportingFont = false
    @State private var fontImportError: String?
    @State private var resumeFontImportAfterPaywall = false
    #if os(macOS)
    @State private var showMacShortcuts = true
    #endif
    @ObservedObject private var customFontStore = CustomFontStore.shared
    private let communityURL = URL(string: "https://www.reddit.com/r/Canvio/")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    themeSection
                    toolbarSection
                    canvasChromeSection
                    #if os(macOS)
                    macShortcutsSection
                    #endif
                    #if os(iOS)
                    drawingSection
                    #endif
                    mediaSection
                    canvasActionsSection
                    communitySection
                    selectionSection
                    canvasBackgroundSection
                    gridSection
                }
                .padding(24)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet {
                settings.isPro = true
                let shouldImportFont = resumeFontImportAfterPaywall
                resumeFontImportAfterPaywall = false

                if shouldImportFont {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isImportingFont = true
                    }
                } else if auth.currentUser == nil {
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

    // MARK: - Toolbar
    private var toolbarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("TOOLBAR")
            settingsToggleCard(
                icon: "dock.rectangle",
                title: "Show toolbar",
                subtitle: "Display the canvas toolbar at the bottom of the screen.",
                isOn: Binding(
                    get: { settings.toolbarPosition != .hidden },
                    set: { settings.toolbarPosition = $0 ? .bottom : .hidden }
                )
            )

            settingsToggleCard(
                icon: "square.grid.3x3",
                title: "Compact floating buttons",
                subtitle: "Use small icon-only buttons around the canvas instead of the wide toolbar.",
                isOn: Binding(
                    get: { settings.toolbarStyle == .compactButtons },
                    set: { settings.toolbarStyle = $0 ? .compactButtons : .floatingBar }
                )
            )
        }
    }

    // MARK: - Canvas Chrome
    private var canvasChromeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("CANVAS CONTROLS")
            VStack(alignment: .leading, spacing: 10) {
                #if os(iOS)
                settingsToggleContent(
                    icon: "rectangle.topthird.inset.filled",
                    title: "Show top bar",
                    subtitle: "Keep undo, export, settings, and canvas actions at the top.",
                    isOn: Binding(
                        get: { settings.canvasTopBarVisible },
                        set: { settings.canvasTopBarVisible = $0 }
                    )
                )

                Divider()
                #endif

                settingsToggleContent(
                    icon: "rectangle.on.rectangle.angled",
                    title: "Show pages",
                    subtitle: "Display the page switcher pill on the canvas.",
                    isOn: Binding(
                        get: { settings.canvasPagesPanelVisible },
                        set: { settings.canvasPagesPanelVisible = $0 }
                    )
                )

                Divider()

                settingsToggleContent(
                    icon: "map",
                    title: "Show minimap",
                    subtitle: "Display the map button for quick navigation.",
                    isOn: Binding(
                        get: { settings.canvasMinimapVisible },
                        set: { settings.canvasMinimapVisible = $0 }
                    )
                )
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    #if os(macOS)
    // MARK: - macOS Shortcuts
    private var macShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("MACOS SHORTCUTS")
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showMacShortcuts.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        settingsRowLabel(
                            icon: "keyboard",
                            title: "Keyboard shortcuts",
                            subtitle: showMacShortcuts ? "Hide the Mac shortcut list." : "Show the Mac shortcut list."
                        )
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showMacShortcuts ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showMacShortcuts {
                    VStack(spacing: 8) {
                        shortcutRow("⌘K", "Command palette")
                        shortcutRow("T", "Add text")
                        shortcutRow("N", "Sticky note")
                        shortcutRow("D", "Drawing mode")
                        shortcutRow("S", "Shape")
                        shortcutRow("L", "Lasso")
                        shortcutRow("M", "Toggle minimap")
                        shortcutRow("P", "Toggle pages")
                        shortcutRow("⌘D", "Duplicate selected item")
                        shortcutRow("⌫", "Delete selected item")
                        shortcutRow("↑ ↓ ← →", "Nudge selected item")
                        shortcutRow("⇧ + arrows", "Bigger nudge")
                        shortcutRow("⌘G", "Group selected items")
                        shortcutRow("⌘⇧G", "Ungroup")
                        shortcutRow("[ / ]", "Send backward or forward")
                        shortcutRow("Esc", "Exit mode or close floating controls")
                        shortcutRow("Space + drag", "Pan canvas")
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func shortcutRow(_ shortcut: String, _ title: String) -> some View {
        HStack(spacing: 12) {
            Text(shortcut)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 86, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
    #endif

    // MARK: - Drawing
    private var drawingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("DRAWING")
            VStack(alignment: .leading, spacing: 10) {
                settingsToggleContent(
                    icon: "pencil.and.outline",
                    title: "Smart shapes",
                    subtitle: "Straighten lines and clean up simple shapes while drawing.",
                    isOn: Binding(
                        get: { settings.smartShapeSnappingEnabled },
                        set: { settings.smartShapeSnappingEnabled = $0 }
                    )
                )

                Divider()

                settingsToggleContent(
                    icon: "textformat.abc.dottedunderline",
                    title: "Handwriting to text",
                    subtitle: "Add a Write option inside the Drawing tool to turn handwriting into editable text.",
                    isOn: Binding(
                        get: { settings.handwritingToTextEnabled },
                        set: { settings.handwritingToTextEnabled = $0 }
                    )
                )

                if settings.handwritingToTextEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        handwritingToolLocationHint

                        Divider()
                            .padding(.vertical, 2)

                        HStack {
                            Text("Recognition strictness")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(strictnessLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { settings.handwritingToTextStrictness },
                                set: { settings.handwritingToTextStrictness = $0 }
                            ),
                            in: 0.15...0.75,
                            step: 0.05
                        )
                        .tint(.accentColor)

                        Divider()
                            .padding(.vertical, 2)

                        Text("TEXT GROUPING")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Picker(
                            "Text grouping",
                            selection: Binding(
                                get: { settings.handwritingTextGrouping },
                                set: { settings.handwritingTextGrouping = $0 }
                            )
                        ) {
                            ForEach(HandwritingTextGrouping.allCases) { grouping in
                                Text(grouping.shortTitle).tag(grouping)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(settings.handwritingTextGrouping.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()
                            .padding(.vertical, 2)

                        handwritingTextStyleEditor
                    }
                    .padding(.leading, 28)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var handwritingToolLocationHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHERE IT APPEARS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                handwritingToolRouteStep(
                    icon: "pencil.and.scribble",
                    title: "Drawing",
                    tint: .orange
                )

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                handwritingToolRouteStep(
                    icon: "textformat.abc.dottedunderline",
                    title: "Write",
                    tint: .blue
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Open Drawing from the canvas toolbar, choose Write, then finish the writing session to place the recognized text on the canvas.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func handwritingToolRouteStep(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
    }

    private var handwritingTextStyleEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CONVERTED TEXT STYLE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            handwritingTextPreview
            handwritingFontRow
            handwritingFontSizeRow
            handwritingFontStyleRow
            handwritingAlignmentRow
            handwritingTextColorRow
            handwritingCardRow
        }
    }

    private var handwritingTextPreview: some View {
        HStack {
            Spacer(minLength: 0)
            Text("Recognized text")
                .font(handwritingPreviewFont)
                .underline(settings.handwritingTextIsUnderline)
                .foregroundStyle(colorFromName(settings.handwritingTextColorName))
                .multilineTextAlignment(handwritingAlignment)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(cardColorFromName(settings.handwritingTextBgColorName) ?? Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    cardColorFromName(settings.handwritingTextStrokeColorName) ?? Color.clear,
                                    lineWidth: settings.handwritingTextStrokeColorName == "none" ? 0 : settings.handwritingTextStrokeWidth
                                )
                        )
                )
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }

    private var handwritingFontRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text("Font")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                importFontButton
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(customFontStore.allFonts) { font in
                        handwritingFontChip(font)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func handwritingFontChip(_ font: AppFont) -> some View {
        let isSelected = settings.handwritingTextFontName == font.name
        return Button {
            settings.handwritingTextFontName = font.name
        } label: {
            Text(font.displayName)
                .font(font.name == "system" ? .system(size: 15, weight: .medium) : .custom(font.name, size: 16))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    private var importFontButton: some View {
        Button {
            if pro.isPro {
                isImportingFont = true
            } else {
                resumeFontImportAfterPaywall = true
                showPaywall = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("Import")
                    .font(.caption.weight(.semibold))
                if !pro.isPro {
                    Text("PRO")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private var handwritingFontSizeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Font size")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                handwritingFontSizePresetMenu
            }

            HStack(spacing: 12) {
                Button {
                    settings.handwritingTextFontSize = settings.handwritingTextFontSize - 2
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { settings.handwritingTextFontSize },
                        set: { settings.handwritingTextFontSize = $0 }
                    ),
                    in: TextStyle.minimumFontSize...TextStyle.maximumFontSize,
                    step: 1
                )
                .tint(.accentColor)

                Button {
                    settings.handwritingTextFontSize = settings.handwritingTextFontSize + handwritingFontSizeStep
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var handwritingFontSizePresetMenu: some View {
        Menu {
            ForEach([10, 12, 14, 16, 18, 24, 32, 48, 72, 96, 144, 192, 240], id: \.self) { size in
                Button("\(size) pt") {
                    settings.handwritingTextFontSize = Double(size)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(Int(settings.handwritingTextFontSize))pt")
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private var handwritingFontStyleRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                handwritingStyleToggle(
                    title: "Bold",
                    icon: "bold",
                    isOn: Binding(
                        get: { settings.handwritingTextIsBold },
                        set: { settings.handwritingTextIsBold = $0 }
                    )
                )
                handwritingStyleToggle(
                    title: "Italic",
                    icon: "italic",
                    isOn: Binding(
                        get: { settings.handwritingTextIsItalic },
                        set: { settings.handwritingTextIsItalic = $0 }
                    )
                )
                handwritingStyleToggle(
                    title: "Underline",
                    icon: "underline",
                    isOn: Binding(
                        get: { settings.handwritingTextIsUnderline },
                        set: { settings.handwritingTextIsUnderline = $0 }
                    )
                )
            }
        }
    }

    private func handwritingStyleToggle(title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(isOn.wrappedValue ? .white : Color.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isOn.wrappedValue ? Color.accentColor : Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    private var handwritingAlignmentRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alignment")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                handwritingAlignButton("leading", icon: "text.alignleft", title: "Left")
                handwritingAlignButton("center", icon: "text.aligncenter", title: "Center")
                handwritingAlignButton("trailing", icon: "text.alignright", title: "Right")
            }
        }
    }

    private func handwritingAlignButton(_ rawValue: String, icon: String, title: String) -> some View {
        let isSelected = settings.handwritingTextAlignmentRawValue == rawValue
        return Button {
            settings.handwritingTextAlignmentRawValue = rawValue
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(isSelected ? .white : Color.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    private var handwritingTextColorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text color")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TextStyle.colorOptions, id: \.name) { option in
                        colorDot(
                            name: option.name,
                            color: option.color,
                            selection: Binding(
                                get: { settings.handwritingTextColorName },
                                set: { settings.handwritingTextColorName = $0 }
                            ),
                            usesAccentRing: false
                        )
                    }
                    ColorPicker(
                        "Custom converted text color",
                        selection: handwritingTextCustomColorBinding,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isCustomHandwritingTextColor ? Color.primary.opacity(0.45) : Color.primary.opacity(0.12),
                                lineWidth: isCustomHandwritingTextColor ? 2 : 1
                            )
                    )
                    .accessibilityLabel("Custom converted text color")
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var handwritingCardRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Card")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 7) {
                Text("Background")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        noneColorDot(selection: Binding(
                            get: { settings.handwritingTextBgColorName },
                            set: { settings.handwritingTextBgColorName = $0 }
                        ))
                        ForEach(cardColorOptions, id: \.name) { option in
                            colorDot(
                                name: option.name,
                                color: option.color,
                                selection: Binding(
                                    get: { settings.handwritingTextBgColorName },
                                    set: { settings.handwritingTextBgColorName = $0 }
                                ),
                                usesAccentRing: true
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Border")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        noneColorDot(selection: Binding(
                            get: { settings.handwritingTextStrokeColorName },
                            set: { settings.handwritingTextStrokeColorName = $0 }
                        ))
                        ForEach(cardColorOptions, id: \.name) { option in
                            colorDot(
                                name: option.name,
                                color: option.color,
                                selection: Binding(
                                    get: { settings.handwritingTextStrokeColorName },
                                    set: { settings.handwritingTextStrokeColorName = $0 }
                                ),
                                usesAccentRing: true
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if settings.handwritingTextStrokeColorName != "none" {
                HStack(spacing: 8) {
                    ForEach([1.0, 2.0, 3.0, 5.0], id: \.self) { width in
                        Button {
                            settings.handwritingTextStrokeWidth = width
                        } label: {
                            Text("\(Int(width))pt")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(settings.handwritingTextStrokeWidth == width ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(settings.handwritingTextStrokeWidth == width ? Color.accentColor : Color.secondary.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Media
    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("MEDIA")
            settingsToggleCard(
                icon: "rectangle.on.rectangle",
                title: "Floating YouTube player",
                subtitle: "Keep the playing video pinned to the screen while you pan, zoom, or move around the canvas.",
                isOn: Binding(
                    get: { settings.floatingYouTubePlaybackEnabled },
                    set: { settings.floatingYouTubePlaybackEnabled = $0 }
                )
            )
        }
    }

    // MARK: - Canvas actions
    private var canvasActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("CANVAS ACTIONS")
            VStack(alignment: .leading, spacing: 10) {
                instructionRow(icon: "doc.on.doc", text: "Hold any item on the canvas to duplicate it.")
                instructionRow(icon: "checkmark.circle", text: "To duplicate multiple items, hold the canvas, select items, then tap Duplicate.")
                instructionRow(icon: "square.stack.3d.up.fill", text: "To group items, hold the canvas, select multiple items, then tap Group. Selecting one grouped item selects the whole group.")
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
                settingsToggleCard(
                    icon: "square.3.layers.3d",
                    title: "Overlapping item picker",
                    subtitle: "When several items overlap, tapping that spot can show a small picker so you can choose the item behind the front one. It only checks the stack while this is enabled.",
                    isOn: Binding(
                        get: { settings.overlapStackPickerEnabled },
                        set: { settings.overlapStackPickerEnabled = $0 }
                    )
                )
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

            if settings.canvasBackgroundPalette == .custom {
                Group {
                    if pro.isPro {
                        customCanvasBackgroundEditor
                    } else {
                        customCanvasBackgroundLockedCard
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
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
                resumeFontImportAfterPaywall = false
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
                    systemColorScheme: colorScheme,
                    customColors: settings.customCanvasBackgroundColors
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
        case .paper, .slate, .sky, .mint, .rose, .lavender, .custom:
            return true
        }
    }

    private var customCanvasBackgroundLockedCard: some View {
        Button {
            resumeFontImportAfterPaywall = false
            showPaywall = true
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom background colors")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Unlock Pro to pick separate light and dark canvas colors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text("PRO")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var customCanvasBackgroundEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CUSTOM COLORS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Pick separate canvas colors for light and dark mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                Button("Reset") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.resetCustomCanvasBackgroundColors()
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            HStack(spacing: 10) {
                customBackgroundPreviewCard(
                    title: "Light",
                    mode: .light,
                    hex: settings.customCanvasBackgroundColors.lightHex
                )
                customBackgroundPreviewCard(
                    title: "Dark",
                    mode: .dark,
                    hex: settings.customCanvasBackgroundColors.darkHex
                )
            }

            VStack(spacing: 10) {
                customBackgroundColorPicker(
                    title: "Light mode",
                    systemImage: "sun.max",
                    selection: Binding(
                        get: { settings.customCanvasBackgroundLightColor },
                        set: { settings.customCanvasBackgroundLightColor = $0 }
                    )
                )

                customBackgroundColorPicker(
                    title: "Dark mode",
                    systemImage: "moon",
                    selection: Binding(
                        get: { settings.customCanvasBackgroundDarkColor },
                        set: { settings.customCanvasBackgroundDarkColor = $0 }
                    )
                )
            }

            HStack(spacing: 10) {
                Button {
                    settings.saveCurrentCustomCanvasBackgroundToHistory()
                } label: {
                    Label("Save Pair", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                if !settings.customCanvasBackgroundHistory.isEmpty {
                    Button {
                        settings.clearCustomCanvasBackgroundHistory()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 38, height: 34)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Clear saved custom backgrounds")
                }
            }

            if !settings.customCanvasBackgroundHistory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECENT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(settings.customCanvasBackgroundHistory) { preset in
                                customBackgroundHistoryChip(preset)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func customBackgroundPreviewCard(
        title: String,
        mode: CanvasBackgroundMode,
        hex: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            CanvasBackgroundSwatch(
                mode: mode,
                palette: .custom,
                systemColorScheme: colorScheme,
                customColors: settings.customCanvasBackgroundColors
            )
            .frame(height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            HStack(spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 2)
                Text(hex.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func customBackgroundColorPicker(
        title: String,
        systemImage: String,
        selection: Binding<Color>
    ) -> some View {
        ColorPicker(selection: selection, supportsOpacity: false) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func customBackgroundHistoryChip(_ preset: CanvasCustomBackgroundPreset) -> some View {
        let selected = settings.customCanvasBackgroundColors == preset.colors
        return HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    settings.applyCustomCanvasBackgroundPreset(preset)
                }
            } label: {
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(ShapeColorPalette.color(named: preset.lightHex, fallback: .white))
                        .frame(width: 24, height: 28)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(ShapeColorPalette.color(named: preset.darkHex, fallback: .black))
                        .frame(width: 24, height: 28)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apply custom background colors")

            Button {
                settings.deleteCustomCanvasBackgroundPreset(preset)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete custom background colors")
        }
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
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
                            resumeFontImportAfterPaywall = false
                            showPaywall = true
                        }
                    }
                }
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

    private var strictnessLabel: String {
        switch settings.handwritingToTextStrictness {
        case ..<0.3: return "Relaxed"
        case 0.3..<0.55: return "Balanced"
        default: return "Strict"
        }
    }

    private var handwritingPreviewFont: Font {
        let base: Font = settings.handwritingTextFontName == "system"
            ? .system(size: settings.handwritingTextFontSize)
            : .custom(settings.handwritingTextFontName, size: settings.handwritingTextFontSize)
        var font = base
        if settings.handwritingTextIsBold { font = font.bold() }
        if settings.handwritingTextIsItalic { font = font.italic() }
        return font
    }

    private var handwritingAlignment: TextAlignment {
        switch settings.handwritingTextAlignmentRawValue {
        case "center": return .center
        case "trailing": return .trailing
        default: return .leading
        }
    }

    private var handwritingFontSizeStep: Double {
        settings.handwritingTextFontSize >= 72 ? 8 : 2
    }

    private var handwritingTextCustomColorBinding: Binding<Color> {
        Binding(
            get: { colorFromName(settings.handwritingTextColorName) },
            set: {
                settings.handwritingTextColorName = TextStyle.storageName(
                    for: $0,
                    fallback: settings.handwritingTextColorName
                )
            }
        )
    }

    private var isCustomHandwritingTextColor: Bool {
        !TextStyle.colorOptions.contains { $0.name == settings.handwritingTextColorName }
    }

    private func colorFromName(_ name: String) -> Color {
        TextStyle.color(named: name)
    }

    private func cardColorFromName(_ name: String) -> Color? {
        guard name != "none" else { return nil }
        return cardColorOptions.first { $0.name == name }?.color
    }

    private func colorDot(name: String,
                          color: Color,
                          selection: Binding<String>,
                          usesAccentRing: Bool) -> some View {
        Button {
            selection.wrappedValue = name
        } label: {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(name == "white" ? 0.35 : 0.12), lineWidth: 1))

                if selection.wrappedValue == name {
                    Circle()
                        .strokeBorder(usesAccentRing ? Color.accentColor : Color.primary.opacity(0.45), lineWidth: 2)
                        .frame(width: 34, height: 34)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(swatchCheckmarkColor(for: name))
                }
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }

    private func swatchCheckmarkColor(for name: String) -> Color {
        ["white", "yellow", "mint"].contains(name) ? .black : .white
    }

    private func noneColorDot(selection: Binding<String>) -> some View {
        Button {
            selection.wrappedValue = "none"
        } label: {
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5))
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                if selection.wrappedValue == "none" {
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: 34, height: 34)
                }
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
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
                settings.handwritingTextFontName = importedFont.name
            } catch {
                fontImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        case .failure(let error):
            fontImportError = error.localizedDescription
        }
    }

    private var cardColorOptions: [(name: String, color: Color)] {
        [
            ("red", .red),
            ("orange", .orange),
            ("yellow", Color(red: 1, green: 0.85, blue: 0)),
            ("green", .green),
            ("blue", .blue),
            ("purple", .purple),
            ("pink", .pink),
            ("teal", .teal),
            ("white", .white),
            ("black", Color(white: 0.1)),
            ("gray", Color(white: 0.5))
        ]
    }

    private func settingsRowLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsToggleContent(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            settingsRowLabel(icon: icon, title: title, subtitle: subtitle)
                .layoutPriority(1)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsToggleCard(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        settingsToggleContent(icon: icon, title: title, subtitle: subtitle, isOn: isOn)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
    var customColors: CanvasCustomBackgroundColors = .defaults

    private var appearance: CanvasBackgroundAppearance {
        palette.appearance(
            for: mode.resolvedColorScheme(system: systemColorScheme),
            customColors: customColors
        )
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
