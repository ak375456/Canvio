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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    themeSection
                    toolbarSection
                    gridSection
                }
                .padding(24)
            }
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
            HStack {
                label("TOOLBAR")
                Spacer()
                if settings.toolbarPosition == .hidden {
                    Text("Long-press canvas to add")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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

    // MARK: - Grid style
    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("CANVAS GRID")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78))], spacing: 10) {
                ForEach(GridStyle.allCases) { style in
                    optionCard(
                        title: style.title,
                        icon: style.icon,
                        isSelected: settings.gridStyle == style
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.gridStyle = style
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

    private func optionCard(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.8))
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
}
