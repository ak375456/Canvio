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
    @State private var showPaywall = false
    @State private var showAuth = false
    
    var exportButton: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    themeSection
                    toolbarSection
                    canvasActionsSection
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
                subtitle: "Sign in to restore your canvases and sync Canvio Pro across all your devices."
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
