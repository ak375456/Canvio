//
//  ConnectorOverlayView.swift
//  Ponder
//

import SwiftUI
import SwiftData

/// Lines layer — rendered at zIndex(-1) behind all elements.
/// Call ConnectorAnchorDotsView separately at a HIGH zIndex so dots
/// are never covered by element card backgrounds.
struct ConnectorOverlayView: View {
    let connectors:  [ConnectorModel]
    let boundsMap:   [UUID: ElementBounds]
    @ObservedObject var vm: ConnectorViewModel
    @Environment(\.modelContext) private var context
    let undoManager:  CanvasUndoManager?
    let canvasID:     UUID
    let canvasScale:  CGFloat

    var body: some View {
        ZStack {
            // Background drag tracker for live preview
            if vm.isConnectModeActive {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if case .pickingTo = vm.connectState {
                                    vm.updatePreviewPoint(value.location)
                                }
                            }
                    )
            }

            // Persisted connector lines
            ForEach(connectors) { connector in
                if let (start, end) = ConnectorViewModel.resolvePoints(
                    connector: connector, boundsMap: boundsMap) {

                    let isSelected = vm.selectedConnectorID == connector.id
                    let color      = paletteColor(connector.colorName)
                    let lineW      = CGFloat(connector.strokeWidth)
                    let hitWidth   = 44 / canvasScale

                    ConnectorViewModel.path(from: start, to: end, style: connector.lineStyle)
                        .stroke(Color.clear, lineWidth: hitWidth)
                        .contentShape(
                            ConnectorViewModel.path(from: start, to: end, style: connector.lineStyle)
                                .stroke(lineWidth: hitWidth)
                        )
                        .onTapGesture {
                            vm.selectedConnectorID = (vm.selectedConnectorID == connector.id)
                                ? nil : connector.id
                        }

                    ConnectorViewModel.path(from: start, to: end, style: connector.lineStyle)
                        .stroke(
                            isSelected ? Color.accentColor : color,
                            style: StrokeStyle(lineWidth: lineW, lineCap: .round, lineJoin: .round)
                        )
                        .allowsHitTesting(false)

                    if connector.hasArrowHead {
                        let tipStart = tipStartPoint(start: start, end: end,
                                                     style: connector.lineStyle,
                                                     strokeWidth: connector.strokeWidth)
                        ConnectorViewModel.arrowPath(from: tipStart, to: end,
                                                     strokeWidth: connector.strokeWidth)
                            .stroke(
                                isSelected ? Color.accentColor : color,
                                style: StrokeStyle(lineWidth: lineW, lineCap: .round)
                            )
                            .allowsHitTesting(false)
                    }

                    if isSelected {
                        let mid = midPoint(start: start, end: end, style: connector.lineStyle)
                        connectorBadge(connector: connector, at: mid)
                    }
                }
            }

            // Live preview dashed line
            if case .pickingTo(let fromID, let fromAnchor, let previewPoint?) = vm.connectState,
               let fromBounds = boundsMap[fromID] {
                let start = fromAnchor.point(
                    cx: fromBounds.cx, cy: fromBounds.cy,
                    width: fromBounds.width, height: fromBounds.height)
                ConnectorViewModel.path(from: start, to: previewPoint, style: .curved)
                    .stroke(
                        Color.accentColor.opacity(0.8),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 5])
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Selection badge

    private func connectorBadge(connector: ConnectorModel, at point: CGPoint) -> some View {
        HStack(spacing: 6) {
            Button {
                let next: ConnectorLineStyle = connector.lineStyle == .straight ? .curved : .straight
                vm.updateStyle(connector: connector, lineStyle: next, context: context)
            } label: {
                Image(systemName: connector.lineStyle == .straight ? "scribble" : "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary).frame(width: 28, height: 28)
            }.buttonStyle(.plain)

            Button {
                vm.updateStyle(connector: connector,
                               hasArrowHead: !connector.hasArrowHead, context: context)
            } label: {
                Image(systemName: connector.hasArrowHead ? "arrow.right" : "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(connector.hasArrowHead ? Color.accentColor : Color.primary.opacity(0.5))
                    .frame(width: 28, height: 28)
            }.buttonStyle(.plain)

            Menu {
                ForEach(["primary","blue","red","green","orange","purple","pink","teal","gray"], id: \.self) { name in
                    Button { vm.updateStyle(connector: connector, colorName: name, context: context) } label: {
                        HStack {
                            Circle().fill(paletteColor(name)).frame(width: 12, height: 12)
                            Text(name.capitalized)
                        }
                    }
                }
            } label: {
                Circle().fill(paletteColor(connector.colorName)).frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1))
            }

            Menu {
                ForEach([1.0, 2.0, 3.0, 4.0, 6.0], id: \.self) { w in
                    Button { vm.updateStyle(connector: connector, strokeWidth: w, context: context) } label: {
                        Text("\(Int(w))pt")
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "lineweight").font(.system(size: 11))
                    Text("\(Int(connector.strokeWidth))").font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.primary.opacity(0.7)).frame(width: 34, height: 28)
            }

            Divider().frame(height: 18)

            Button {
                vm.delete(connector: connector, context: context, undoManager: undoManager)
            } label: {
                Image(systemName: "trash").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.red).frame(width: 28, height: 28)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
        .scaleEffect(1.0 / canvasScale)
        .position(x: point.x, y: point.y - 36 / canvasScale)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
        .animation(.spring(duration: 0.2), value: vm.selectedConnectorID)
        .zIndex(600)
    }

    // MARK: - Geometry helpers

    private func midPoint(start: CGPoint, end: CGPoint, style: ConnectorLineStyle) -> CGPoint {
        switch style {
        case .straight:
            return CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        case .curved:
            let dx = (end.x - start.x) * 0.5
            let cp1 = CGPoint(x: start.x + dx, y: start.y)
            let cp2 = CGPoint(x: end.x - dx,   y: end.y)
            let t: CGFloat = 0.5
            let x = pow(1-t,3)*start.x + 3*pow(1-t,2)*t*cp1.x + 3*(1-t)*t*t*cp2.x + t*t*t*end.x
            let y = pow(1-t,3)*start.y + 3*pow(1-t,2)*t*cp1.y + 3*(1-t)*t*t*cp2.y + t*t*t*end.y
            return CGPoint(x: x, y: y)
        }
    }

    private func tipStartPoint(start: CGPoint, end: CGPoint,
                                style: ConnectorLineStyle, strokeWidth: Double) -> CGPoint {
        let offset = CGFloat(strokeWidth * 5)
        switch style {
        case .straight:
            let angle = atan2(end.y - start.y, end.x - start.x)
            return CGPoint(x: end.x - offset * cos(angle), y: end.y - offset * sin(angle))
        case .curved:
            let dx = (end.x - start.x) * 0.5
            let cp2 = CGPoint(x: end.x - dx, y: end.y)
            let angle = atan2(end.y - cp2.y, end.x - cp2.x)
            return CGPoint(x: end.x - offset * cos(angle), y: end.y - offset * sin(angle))
        }
    }

    private func paletteColor(_ name: String) -> Color {
        switch name {
        case "blue":   return .blue
        case "red":    return .red
        case "green":  return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink":   return .pink
        case "teal":   return .teal
        case "gray":   return .gray
        default:       return .primary
        }
    }
}

// MARK: - Anchor dots layer
// Rendered SEPARATELY at a high zIndex in CanvasView so dots always
// appear above element card backgrounds regardless of element zIndex.

struct ConnectorAnchorDotsView: View {
    let boundsMap:   [UUID: ElementBounds]
    @ObservedObject var vm: ConnectorViewModel
    @Environment(\.modelContext) private var context
    let undoManager:  CanvasUndoManager?
    let canvasID:     UUID
    let canvasScale:  CGFloat
    let connectors:   [ConnectorModel]

    var body: some View {
        ZStack {
            if vm.isConnectModeActive {
                ForEach(Array(boundsMap.values), id: \.id) { bounds in
                    anchorDots(for: bounds)
                }
            }
        }
    }

    @ViewBuilder
    private func anchorDots(for bounds: ElementBounds) -> some View {
        ForEach(ConnectorAnchor.allCases, id: \.rawValue) { anchor in
            let point = anchor.point(cx: bounds.cx, cy: bounds.cy,
                                     width: bounds.width, height: bounds.height)

            let isFromAnchor: Bool = {
                if case .pickingTo(let id, let a, _) = vm.connectState {
                    return id == bounds.id && a == anchor
                }
                return false
            }()

            ZStack {
                let tapSize: CGFloat = 44 / canvasScale
                Circle().fill(Color.clear)
                    .frame(width: tapSize, height: tapSize)
                    .contentShape(Circle())

                Circle()
                    .fill(isFromAnchor ? Color.accentColor : Color.white)
                    .frame(width: 16 / canvasScale, height: 16 / canvasScale)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 2.5 / canvasScale)
                            .opacity(isFromAnchor ? 0 : 1)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 4 / canvasScale)
            }
            .position(x: point.x, y: point.y)
            .highPriorityGesture(
                TapGesture().onEnded {
                    vm.selectAnchor(
                        elementID: bounds.id, anchor: anchor,
                        anchorPoint: point, canvasID: canvasID,
                        allConnectors: connectors, context: context,
                        undoManager: undoManager
                    )
                }
            )
            .animation(.spring(duration: 0.18), value: isFromAnchor)
        }
    }
}
