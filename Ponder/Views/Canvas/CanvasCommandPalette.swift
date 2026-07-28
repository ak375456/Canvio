//
//  CanvasCommandPalette.swift
//  Ponder
//

import SwiftUI

#if os(macOS)
struct CanvasCommandPaletteAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let shortcut: String
    let systemImage: String
    let tint: Color
    let isEnabled: Bool
    let action: () -> Void
}

struct CanvasCommandPalette: View {
    let actions: [CanvasCommandPaletteAction]
    @Binding var isPresented: Bool

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filteredActions: [CanvasCommandPaletteAction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return actions }
        let tokens = trimmed.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return actions.filter {
            let haystack = "\($0.title) \($0.subtitle) \($0.shortcut)".lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Search commands", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .focused($searchFocused)
                        .onSubmit { runFirstEnabledAction() }
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(height: 48)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredActions) { action in
                            commandRow(action)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 360)
            }
            .frame(width: 460)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private func commandRow(_ action: CanvasCommandPaletteAction) -> some View {
        Button {
            run(action)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(action.tint.opacity(action.isEnabled ? 0.14 : 0.07))
                    Image(systemName: action.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(action.tint)
                        .opacity(action.isEnabled ? 1 : 0.45)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(action.isEnabled ? .primary : .secondary)
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if !action.shortcut.isEmpty {
                    Text(action.shortcut)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(action.isEnabled ? Color.primary.opacity(0.035) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
    }

    private func run(_ action: CanvasCommandPaletteAction) {
        guard action.isEnabled else { return }
        isPresented = false
        action.action()
    }

    private func runFirstEnabledAction() {
        guard let action = filteredActions.first(where: \.isEnabled) else { return }
        run(action)
    }
}
#endif
