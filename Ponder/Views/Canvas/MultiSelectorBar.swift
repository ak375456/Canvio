//
//  MultiSelectBar.swift
//  Ponder
//

import SwiftUI

enum CanvasObjectAlignment: String, CaseIterable, Identifiable {
    case left
    case horizontalCenter
    case right
    case top
    case verticalCenter
    case bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Align Left"
        case .horizontalCenter: return "Align Horizontal Centers"
        case .right: return "Align Right"
        case .top: return "Align Top"
        case .verticalCenter: return "Align Vertical Centers"
        case .bottom: return "Align Bottom"
        }
    }

    var icon: String {
        switch self {
        case .left: return "align.horizontal.left"
        case .horizontalCenter: return "align.horizontal.center"
        case .right: return "align.horizontal.right"
        case .top: return "align.vertical.top"
        case .verticalCenter: return "align.vertical.center"
        case .bottom: return "align.vertical.bottom"
        }
    }
}

enum CanvasObjectDistribution: String, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal: return "Distribute Horizontally"
        case .vertical: return "Distribute Vertically"
        }
    }

    var icon: String {
        switch self {
        case .horizontal: return "distribute.horizontal.center"
        case .vertical: return "distribute.vertical.center"
        }
    }
}

enum CanvasRulerAlignment: String, CaseIterable, Identifiable {
    case before
    case center
    case after

    var id: String { rawValue }

    var title: String {
        switch self {
        case .before: return "Align Above Ruler"
        case .center: return "Align Centers to Ruler"
        case .after: return "Align Below Ruler"
        }
    }

    var icon: String {
        switch self {
        case .before: return "arrow.up.to.line"
        case .center: return "scope"
        case .after: return "arrow.down.to.line"
        }
    }
}

struct CanvasAlignmentDock: View {
    let title: String
    let isGuideActive: Bool
    let isRulerActive: Bool
    var canDistribute: Bool = false
    let onToggleGuide: () -> Void
    let onToggleRuler: () -> Void
    let onAlign: (CanvasObjectAlignment) -> Void
    let onAlignToRuler: (CanvasRulerAlignment) -> Void
    let onRotateRuler: () -> Void
    var onDistribute: (CanvasObjectDistribution) -> Void = { _ in }
    var onDone: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Label(title, systemImage: "align.horizontal.left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 13)

            Divider().frame(height: 22)

            CanvasAlignmentToolButtons(
                isGuideActive: isGuideActive,
                isRulerActive: isRulerActive,
                onToggleGuide: onToggleGuide,
                onToggleRuler: onToggleRuler
            )

            Divider().frame(height: 22)

            if isRulerActive {
                CanvasRulerAlignmentControls(
                    onAlign: onAlignToRuler,
                    onRotate: onRotateRuler
                )
            } else {
                CanvasAlignmentControls(
                    canDistribute: canDistribute,
                    onAlign: onAlign,
                    onDistribute: onDistribute
                )
            }

            if let onDone {
                Divider().frame(height: 22)

                Button(action: onDone) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 42, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close alignment controls")
                .help("Close alignment controls")
            }
        }
        .frame(height: 44)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        .fixedSize()
        .accessibilityElement(children: .contain)
    }
}

private struct CanvasAlignmentToolButtons: View {
    let isGuideActive: Bool
    let isRulerActive: Bool
    let onToggleGuide: () -> Void
    let onToggleRuler: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            CanvasAlignmentGuideButton(
                isActive: isGuideActive,
                onToggle: onToggleGuide
            )

            CanvasAlignmentRulerButton(
                isActive: isRulerActive,
                onToggle: onToggleRuler
            )
        }
        .padding(.horizontal, 5)
    }
}

private struct CanvasAlignmentGuideButton: View {
    let isActive: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .semibold))
                Text("Guide")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isActive ? Color.white : Color.orange)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                isActive ? Color.orange : Color.orange.opacity(0.12),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Remove alignment guide" : "Place alignment guide")
        .accessibilityHint(
            isActive
                ? "Returns alignment to the page or current selection."
                : "Places a movable target on the canvas for precise alignment."
        )
        .help(isActive ? "Remove alignment guide" : "Place alignment guide")
    }
}

private struct CanvasAlignmentRulerButton: View {
    let isActive: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "ruler")
                    .font(.system(size: 14, weight: .semibold))
                Text("Ruler")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isActive ? Color.white : Color.indigo)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                isActive ? Color.indigo : Color.indigo.opacity(0.12),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Remove alignment ruler" : "Place alignment ruler")
        .accessibilityHint(
            isActive
                ? "Returns to regular alignment controls."
                : "Places a movable and rotatable ruler for aligning canvas items."
        )
        .help(isActive ? "Remove alignment ruler" : "Place alignment ruler")
    }
}

private struct CanvasRulerAlignmentControls: View {
    let onAlign: (CanvasRulerAlignment) -> Void
    let onRotate: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CanvasRulerAlignment.allCases) { action in
                Button {
                    onAlign(action)
                } label: {
                    Image(systemName: action.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.indigo)
                        .frame(width: 42, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
                .help(action.title)
            }

            Divider().frame(height: 22)

            Button(action: onRotate) {
                Image(systemName: "rotate.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 42, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rotate ruler 90 degrees")
            .help("Rotate ruler 90°")
        }
    }
}

private struct CanvasAlignmentControls: View {
    let canDistribute: Bool
    let onAlign: (CanvasObjectAlignment) -> Void
    let onDistribute: (CanvasObjectDistribution) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CanvasObjectAlignment.allCases) { action in
                if action == .top {
                    Divider().frame(height: 22)
                }
                alignmentButton(action)
            }

            if canDistribute {
                Divider().frame(height: 22)
                ForEach(CanvasObjectDistribution.allCases) { action in
                    distributionButton(action)
                }
            }
        }
    }

    private func alignmentButton(_ action: CanvasObjectAlignment) -> some View {
        Button {
            onAlign(action)
        } label: {
            Image(systemName: action.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .help(action.title)
    }

    private func distributionButton(_ action: CanvasObjectDistribution) -> some View {
        Button {
            onDistribute(action)
        } label: {
            Image(systemName: action.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 42, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .help(action.title)
    }
}

struct MultiSelectBar: View {
    let count: Int
    let groupActionTitle: String
    let groupActionIcon: String
    let canUseGroupAction: Bool
    let canAlign: Bool
    let canDistribute: Bool
    let isGuideActive: Bool
    let isRulerActive: Bool
    let onToggleGuide: () -> Void
    let onToggleRuler: () -> Void
    let onAlign: (CanvasObjectAlignment) -> Void
    let onAlignToRuler: (CanvasRulerAlignment) -> Void
    let onRotateRuler: () -> Void
    let onDistribute: (CanvasObjectDistribution) -> Void
    let onGroupAction: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(count == 0 ? "Tap to select" : "\(count) selected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)

            Divider().frame(height: 20)

            CanvasAlignmentToolButtons(
                isGuideActive: isGuideActive,
                isRulerActive: isRulerActive,
                onToggleGuide: onToggleGuide,
                onToggleRuler: onToggleRuler
            )
            .disabled(!canAlign)
            .opacity(canAlign ? 1 : 0.42)

            Divider().frame(height: 20)

            Group {
                if isRulerActive {
                    CanvasRulerAlignmentControls(
                        onAlign: onAlignToRuler,
                        onRotate: onRotateRuler
                    )
                } else {
                    CanvasAlignmentControls(
                        canDistribute: canDistribute,
                        onAlign: onAlign,
                        onDistribute: onDistribute
                    )
                }
            }
            .disabled(!canAlign)
            .opacity(canAlign ? 1 : 0.42)

            Divider().frame(height: 20)

            Button(action: onGroupAction) {
                HStack(spacing: 6) {
                    Image(systemName: groupActionIcon).font(.system(size: 14, weight: .medium))
                    Text(groupActionTitle).font(.subheadline.weight(.medium))
                }
                .foregroundStyle(canUseGroupAction ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 14).frame(height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canUseGroupAction)

            Divider().frame(height: 20)

            Button(action: onDuplicate) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.square.on.square").font(.system(size: 14, weight: .medium))
                    Text("Duplicate").font(.subheadline.weight(.medium))
                }
                .foregroundStyle(count > 0 ? .blue : Color.secondary)
                .padding(.horizontal, 14).frame(height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(count == 0)

            Divider().frame(height: 20)

            Button(action: onDelete) {
                HStack(spacing: 6) {
                    Image(systemName: "trash").font(.system(size: 14, weight: .medium))
                    Text("Delete").font(.subheadline.weight(.medium))
                }
                .foregroundStyle(count > 0 ? .red : Color.secondary)
                .padding(.horizontal, 14).frame(height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
        }
        .frame(height: 44)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }
}

/// Kept outside the horizontally scrolling action strip so users can always
/// see how to leave selection mode, regardless of the viewport width.
struct MultiSelectDoneButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Done", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(Color.accentColor, in: Capsule())
        .shadow(color: Color.accentColor.opacity(0.22), radius: 8, y: 3)
        .accessibilityLabel("Done selecting")
        .accessibilityHint("Leaves selection mode.")
        .accessibilityIdentifier("canvas.multiSelect.done")
    }
}
