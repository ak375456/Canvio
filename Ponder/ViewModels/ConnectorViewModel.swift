//
//  ConnectorViewModel.swift
//  Ponder
//

import SwiftUI
import SwiftData
import Combine

// MARK: - Element geometry helper
// CanvasView passes this so ConnectorViewModel can resolve anchor points
// without knowing about any specific element type.

struct ElementBounds {
    let id: UUID
    let cx: Double   // canvas-coordinate center X
    let cy: Double   // canvas-coordinate center Y
    let width: Double
    let height: Double
}

private struct ConnectorStyleHistoryState: Equatable {
    let lineStyle: ConnectorLineStyle
    let colorName: String
    let strokeWidth: Double
    let hasArrowHead: Bool

    init(_ connector: ConnectorModel) {
        lineStyle = connector.lineStyle
        colorName = connector.colorName
        strokeWidth = connector.strokeWidth
        hasArrowHead = connector.hasArrowHead
    }
}

// MARK: - ViewModel

@MainActor
class ConnectorViewModel: ObservableObject {

    // MARK: Connect-mode state machine

    enum ConnectState {
        case inactive
        case pickingFrom
        case pickingTo(fromID: UUID, fromAnchor: ConnectorAnchor, previewPoint: CGPoint?)
    }

    @Published var connectState: ConnectState = .inactive
    @Published var selectedConnectorID: UUID? = nil

    var isConnectModeActive: Bool {
        if case .inactive = connectState { return false }
        return true
    }

    // MARK: - Enter / exit

    func enterConnectMode() {
        connectState        = .pickingFrom
        selectedConnectorID = nil
    }

    func exitConnectMode() {
        connectState = .inactive
    }

    func selectAnchor(elementID: UUID, anchor: ConnectorAnchor,
                      anchorPoint: CGPoint,
                      canvasID: UUID,
                      allConnectors: [ConnectorModel],
                      context: ModelContext,
                      undoManager: CanvasUndoManager? = nil) {
        switch connectState {

        case .pickingFrom:
            connectState = .pickingTo(fromID: elementID, fromAnchor: anchor, previewPoint: anchorPoint)

        case .pickingTo(let fromID, let fromAnchor, _):
            guard elementID != fromID else {
                connectState = .pickingFrom
                return
            }
            let duplicate = allConnectors.contains {
                $0.fromElementID == fromID && $0.fromAnchor == fromAnchor &&
                $0.toElementID   == elementID && $0.toAnchor == anchor
            }
            guard !duplicate else {
                connectState = .pickingFrom
                return
            }
            addConnector(
                canvasID: canvasID,
                fromID: fromID, fromAnchor: fromAnchor,
                toID: elementID, toAnchor: anchor,
                context: context, undoManager: undoManager
            )
            connectState = .pickingFrom

        case .inactive:
            break
        }
    }

    func updatePreviewPoint(_ point: CGPoint) {
        if case .pickingTo(let id, let anchor, _) = connectState {
            connectState = .pickingTo(fromID: id, fromAnchor: anchor, previewPoint: point)
        }
    }

    // MARK: - CRUD

    func addConnector(canvasID: UUID,
                      fromID: UUID, fromAnchor: ConnectorAnchor,
                      toID: UUID,   toAnchor: ConnectorAnchor,
                      lineStyle: ConnectorLineStyle = .curved,
                      colorName: String = "primary",
                      strokeWidth: Double = 2.0,
                      hasArrowHead: Bool = true,
                      context: ModelContext,
                      undoManager: CanvasUndoManager? = nil) {
        let connector = ConnectorModel(
            canvasID: canvasID,
            fromElementID: fromID, fromAnchor: fromAnchor,
            toElementID: toID,     toAnchor: toAnchor,
            lineStyle: lineStyle, colorName: colorName,
            strokeWidth: strokeWidth, hasArrowHead: hasArrowHead
        )
        context.insert(connector)
        try? context.save()
        selectedConnectorID = connector.id

        Task { await ConnectorSyncService.shared.upsert(connector) }

        let id = connector.id
        undoManager?.push(CanvasAction(
            name: "Add connector",
            undo: {
                if let c = try? context.fetch(FetchDescriptor<ConnectorModel>())
                    .first(where: { $0.id == id }) {
                    context.delete(c); try? context.save()
                    Task { await ConnectorSyncService.shared.delete(c) }
                }
            },
            redo: {
                let c = ConnectorModel(
                    canvasID: canvasID,
                    fromElementID: fromID, fromAnchor: fromAnchor,
                    toElementID: toID,     toAnchor: toAnchor,
                    lineStyle: lineStyle, colorName: colorName,
                    strokeWidth: strokeWidth, hasArrowHead: hasArrowHead
                )
                c.id = id
                context.insert(c); try? context.save()
                Task { await ConnectorSyncService.shared.upsert(c) }
            }
        ))
    }

    func delete(connector: ConnectorModel, context: ModelContext,
                undoManager: CanvasUndoManager? = nil) {
        let snap = (
            id: connector.id, canvasID: connector.canvasID,
            fromID: connector.fromElementID, fromAnchor: connector.fromAnchor,
            toID: connector.toElementID, toAnchor: connector.toAnchor,
            lineStyle: connector.lineStyle, colorName: connector.colorName,
            strokeWidth: connector.strokeWidth, hasArrowHead: connector.hasArrowHead
        )

        Task { await ConnectorSyncService.shared.delete(connector) }
        context.delete(connector); try? context.save()
        if selectedConnectorID == snap.id { selectedConnectorID = nil }

        undoManager?.push(CanvasAction(
            name: "Delete connector",
            undo: {
                let c = ConnectorModel(
                    canvasID: snap.canvasID,
                    fromElementID: snap.fromID, fromAnchor: snap.fromAnchor,
                    toElementID: snap.toID,     toAnchor: snap.toAnchor,
                    lineStyle: snap.lineStyle, colorName: snap.colorName,
                    strokeWidth: snap.strokeWidth, hasArrowHead: snap.hasArrowHead
                )
                c.id = snap.id
                context.insert(c); try? context.save()
                Task { await ConnectorSyncService.shared.upsert(c) }
            },
            redo: {
                if let c = try? context.fetch(FetchDescriptor<ConnectorModel>())
                    .first(where: { $0.id == snap.id }) {
                    context.delete(c); try? context.save()
                    Task { await ConnectorSyncService.shared.delete(c) }
                }
            }
        ))
    }

    func updateStyle(connector: ConnectorModel,
                     lineStyle: ConnectorLineStyle? = nil,
                     colorName: String? = nil,
                     strokeWidth: Double? = nil,
                     hasArrowHead: Bool? = nil,
                     context: ModelContext,
                     undoManager: CanvasUndoManager? = nil) {
        let oldState = ConnectorStyleHistoryState(connector)
        if let v = lineStyle    { connector.lineStyle    = v }
        if let v = colorName    { connector.colorName    = v }
        if let v = strokeWidth  { connector.strokeWidth  = v }
        if let v = hasArrowHead { connector.hasArrowHead = v }
        connector.updatedAt = Date()
        try? context.save()
        Task { await ConnectorSyncService.shared.upsert(connector) }
        let newState = ConnectorStyleHistoryState(connector)
        let id = connector.id
        undoManager?.recordChange(
            name: "Change connector style",
            from: oldState,
            to: newState
        ) { state in
            let connectors = (try? context.fetch(FetchDescriptor<ConnectorModel>())) ?? []
            guard let current = connectors.first(where: { $0.id == id }) else { return }
            current.lineStyle = state.lineStyle
            current.colorName = state.colorName
            current.strokeWidth = state.strokeWidth
            current.hasArrowHead = state.hasArrowHead
            current.updatedAt = Date()
            try? context.save()
            Task { await ConnectorSyncService.shared.upsert(current) }
        }
    }

    // Removes all connectors that reference a deleted element
    // Now soft-deletes on Supabase too so other devices remove them.
    func deleteOrphanedConnectors(for elementID: UUID,
                                  allConnectors: [ConnectorModel],
                                  context: ModelContext,
                                  undoManager: CanvasUndoManager? = nil) {
        let orphans = allConnectors.filter {
            $0.fromElementID == elementID || $0.toElementID == elementID
        }
        for c in orphans {
            delete(connector: c, context: context, undoManager: undoManager)
        }
    }

    func stopEditing() {
        selectedConnectorID = nil
        connectState = .inactive
    }

    // MARK: - Geometry helpers

    static func anchors(for bounds: ElementBounds) -> [(ConnectorAnchor, CGPoint)] {
        ConnectorAnchor.allCases.map { anchor in
            (anchor, anchor.point(cx: bounds.cx, cy: bounds.cy,
                                  width: bounds.width, height: bounds.height))
        }
    }

    static func resolvePoints(connector: ConnectorModel,
                               boundsMap: [UUID: ElementBounds]) -> (CGPoint, CGPoint)? {
        guard let from = boundsMap[connector.fromElementID],
              let to   = boundsMap[connector.toElementID] else { return nil }
        let start = connector.fromAnchor.point(cx: from.cx, cy: from.cy,
                                               width: from.width, height: from.height)
        let end   = connector.toAnchor.point(cx: to.cx, cy: to.cy,
                                             width: to.width, height: to.height)
        return (start, end)
    }

    static func path(from start: CGPoint, to end: CGPoint,
                     style: ConnectorLineStyle) -> Path {
        ConnectorGeometry.path(from: start, to: end, style: style)
    }

    static func path(from start: CGPoint, fromAnchor: ConnectorAnchor,
                     to end: CGPoint, toAnchor: ConnectorAnchor,
                     style: ConnectorLineStyle) -> Path {
        ConnectorGeometry.path(
            from: start,
            fromAnchor: fromAnchor,
            to: end,
            toAnchor: toAnchor,
            style: style
        )
    }

    static func path(from start: CGPoint, fromAnchor: ConnectorAnchor,
                     to end: CGPoint, style: ConnectorLineStyle) -> Path {
        ConnectorGeometry.path(
            from: start,
            fromAnchor: fromAnchor,
            to: end,
            style: style
        )
    }

    static func point(from start: CGPoint, fromAnchor: ConnectorAnchor,
                      to end: CGPoint, toAnchor: ConnectorAnchor,
                      style: ConnectorLineStyle, t: CGFloat) -> CGPoint {
        ConnectorGeometry.point(
            from: start,
            fromAnchor: fromAnchor,
            to: end,
            toAnchor: toAnchor,
            style: style,
            t: t
        )
    }

    static func pointBeforeEnd(from start: CGPoint, fromAnchor: ConnectorAnchor,
                               to end: CGPoint, toAnchor: ConnectorAnchor,
                               style: ConnectorLineStyle,
                               distance offset: CGFloat) -> CGPoint {
        ConnectorGeometry.pointBeforeEnd(
            from: start,
            fromAnchor: fromAnchor,
            to: end,
            toAnchor: toAnchor,
            style: style,
            distance: offset
        )
    }

    static func arrowPath(from start: CGPoint, to end: CGPoint,
                          strokeWidth: Double) -> Path {
        let angle  = atan2(end.y - start.y, end.x - start.x)
        let length = CGFloat(strokeWidth * 4.5)
        let spread: CGFloat = .pi / 6

        var p = Path()
        p.move(to: end)
        p.addLine(to: CGPoint(
            x: end.x - length * cos(angle - spread),
            y: end.y - length * sin(angle - spread)
        ))
        p.move(to: end)
        p.addLine(to: CGPoint(
            x: end.x - length * cos(angle + spread),
            y: end.y - length * sin(angle + spread)
        ))
        return p
    }
}

// Make ConnectorAnchor iterable for anchor-dot rendering
extension ConnectorAnchor: CaseIterable {
    public static var allCases: [ConnectorAnchor] = [.top, .bottom, .left, .right]
}
