#if os(iOS)
import SwiftUI
import UIKit
import PencilKit

struct CanvasGestureBridge: UIViewRepresentable {
    var isEnabled: Bool
    var routesCanvasDrawingInput: Bool = false
    var requiresTwoFingerPan: Bool = false
    var selectedElementFrame: CGRect?
    var canvasGestureExclusionFrames: [CGRect] = []
    var onPanBegan: () -> Void
    var onPanChanged: (CGSize) -> Void
    var onPanEnded: () -> Void
    var onPinchBegan: () -> Void
    var onPinchChanged: (CGFloat, CGPoint) -> Void
    var onPinchEnded: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = GestureBridgeView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onHostChanged = { [weak coordinator = context.coordinator, weak view] in
            coordinator?.attach(sourceView: view)
        }
        context.coordinator.parent = self
        DispatchQueue.main.async {
            context.coordinator.attach(sourceView: view)
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateEnabledState()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CanvasGestureBridge
        private weak var sourceView: UIView?
        private weak var attachedView: UIView?
        private var panRecognizer: UIPanGestureRecognizer?
        private var pinchRecognizer: UIPinchGestureRecognizer?
        private var isPinching = false
        private var isPanning = false
        private var activePanTouchCount = 1

        init(parent: CanvasGestureBridge) {
            self.parent = parent
        }

        func attach(sourceView: UIView?) {
            guard let sourceView else {
                self.sourceView = nil
                detach()
                return
            }
            self.sourceView = sourceView

            guard let targetView = sourceView.window else {
                detach()
                return
            }
            guard attachedView !== targetView else { return }

            detach()

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.cancelsTouchesInView = false
            pinch.delaysTouchesBegan = false
            pinch.delaysTouchesEnded = false
            pinch.delegate = self

            targetView.addGestureRecognizer(pan)
            targetView.addGestureRecognizer(pinch)

            attachedView = targetView
            panRecognizer = pan
            pinchRecognizer = pinch
            updateEnabledState()
        }

        func updateEnabledState() {
            if panRecognizer?.isEnabled != parent.isEnabled {
                panRecognizer?.isEnabled = parent.isEnabled
            }
            if pinchRecognizer?.isEnabled != parent.isEnabled {
                pinchRecognizer?.isEnabled = parent.isEnabled
            }

            synchronizeDrawingInputRouting()
            if panRecognizer?.cancelsTouchesInView != parent.routesCanvasDrawingInput {
                panRecognizer?.cancelsTouchesInView = parent.routesCanvasDrawingInput
            }
            if pinchRecognizer?.cancelsTouchesInView != parent.routesCanvasDrawingInput {
                pinchRecognizer?.cancelsTouchesInView = parent.routesCanvasDrawingInput
            }
        }

        /// In canvas drawing, finger navigation follows the same global
        /// "Draw with Finger" preference that PencilKit's `.default` policy uses:
        /// one finger pans when drawing is Pencil-only, otherwise two fingers pan.
        private func synchronizeDrawingInputRouting() {
            activePanTouchCount = parent.requiresTwoFingerPan
                && !UIPencilInteraction.prefersPencilOnlyDrawing ? 2 : 1
            if panRecognizer?.minimumNumberOfTouches != activePanTouchCount {
                panRecognizer?.minimumNumberOfTouches = activePanTouchCount
            }
            if panRecognizer?.maximumNumberOfTouches != activePanTouchCount {
                panRecognizer?.maximumNumberOfTouches = activePanTouchCount
            }
        }

        private func detach() {
            if let panRecognizer, let view = panRecognizer.view {
                view.removeGestureRecognizer(panRecognizer)
            }
            if let pinchRecognizer, let view = pinchRecognizer.view {
                view.removeGestureRecognizer(pinchRecognizer)
            }
            panRecognizer = nil
            pinchRecognizer = nil
            attachedView = nil
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard parent.isEnabled, let sourceView else { return }
            let requiredTouchCount = activePanTouchCount
            switch recognizer.state {
            case .began:
                guard recognizer.numberOfTouches == requiredTouchCount else { return }
                isPanning = true
                parent.onPanBegan()
                let t = recognizer.translation(in: sourceView)
                parent.onPanChanged(CGSize(width: t.x, height: t.y))
            case .changed:
                guard recognizer.numberOfTouches == requiredTouchCount else { return }
                let t = recognizer.translation(in: sourceView)
                parent.onPanChanged(CGSize(width: t.x, height: t.y))
            case .ended, .cancelled, .failed:
                isPanning = false
                if !isPinching {
                    parent.onPanEnded()
                }
            default:
                break
            }
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard parent.isEnabled, let sourceView else { return }
            switch recognizer.state {
            case .began:
                isPinching = true
                parent.onPinchBegan()
                parent.onPinchChanged(recognizer.scale, recognizer.location(in: sourceView))
            case .changed:
                isPinching = true
                parent.onPinchChanged(recognizer.scale, recognizer.location(in: sourceView))
            case .ended, .cancelled, .failed:
                isPinching = false
                if !isPanning {
                    parent.onPinchEnded()
                }
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.isEnabled, let sourceView else { return false }
            synchronizeDrawingInputRouting()
            if isPanning && !(parent.requiresTwoFingerPan && gestureRecognizer === pinchRecognizer) {
                return false
            }
            let point = gestureRecognizer.location(in: sourceView)
            guard sourceView.bounds.contains(point) else { return false }
            if isCanvasNavigationRecognizer(gestureRecognizer),
               isInsideCanvasGestureExclusion(point) {
                return false
            }

            if isCanvasNavigationRecognizer(gestureRecognizer),
               let attachedView {
                let windowPoint = gestureRecognizer.location(in: attachedView)
                if isInsideActivePencilKitRulerCanvas(attachedView.hitTest(windowPoint, with: nil)) {
                    return false
                }
            }

            if gestureRecognizer === panRecognizer {
                if parent.selectedElementFrame?.contains(point) == true {
                    return false
                }
                if let attachedView {
                    let windowPoint = gestureRecognizer.location(in: attachedView)
                    if isInteractiveSystemView(attachedView.hitTest(windowPoint, with: nil)) {
                        return false
                    }
                }
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            guard parent.isEnabled, let sourceView else { return false }
            synchronizeDrawingInputRouting()
            // Apple Pencil is always reserved for PencilKit while drawing.
            if parent.routesCanvasDrawingInput && touch.type == .pencil {
                return false
            }
            let point = touch.location(in: sourceView)
            guard sourceView.bounds.contains(point) else { return false }
            if isCanvasNavigationRecognizer(gestureRecognizer),
               isInsideCanvasGestureExclusion(point) {
                return false
            }

            if isCanvasNavigationRecognizer(gestureRecognizer),
               isInsideActivePencilKitRulerCanvas(touch.view) {
                return false
            }

            if gestureRecognizer === panRecognizer {
                if parent.selectedElementFrame?.contains(point) == true {
                    return false
                }
                if isInteractiveSystemView(touch.view) {
                    return false
                }
            }

            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if parent.requiresTwoFingerPan {
                let isPanAndPinch =
                    (gestureRecognizer === panRecognizer && otherGestureRecognizer === pinchRecognizer)
                    || (gestureRecognizer === pinchRecognizer && otherGestureRecognizer === panRecognizer)
                if isPanAndPinch {
                    return true
                }
            }
            if gestureRecognizer === panRecognizer || otherGestureRecognizer === panRecognizer {
                return false
            }
            return true
        }

        private func isCanvasNavigationRecognizer(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer === panRecognizer || gestureRecognizer === pinchRecognizer
        }

        private func isInsideCanvasGestureExclusion(_ point: CGPoint) -> Bool {
            parent.canvasGestureExclusionFrames.contains { $0.contains(point) }
        }

        private func isInsideActivePencilKitRulerCanvas(_ view: UIView?) -> Bool {
            var current = view
            var depth = 0
            while let candidate = current, depth < 8 {
                if let canvas = candidate as? PKCanvasView {
                    return canvas.isRulerActive
                }
                current = candidate.superview
                depth += 1
            }
            return false
        }

        private func isInteractiveSystemView(_ view: UIView?) -> Bool {
            var current = view
            var depth = 0
            while let candidate = current, depth < 8 {
                if candidate === sourceView {
                    return false
                }
                let className = NSStringFromClass(type(of: candidate))
                if parent.routesCanvasDrawingInput && className.contains("PKCanvasView") {
                    return false
                }
                if candidate is UIControl || candidate is UIScrollView {
                    return true
                }

                if className.contains("Menu")
                    || className.contains("Popover")
                    || className.contains("Context")
                    || className.contains("Alert")
                    || className.contains("Sheet")
                    || className.contains("Palette") {
                    return true
                }

                current = candidate.superview
                depth += 1
            }
            return false
        }
    }

    final class GestureBridgeView: UIView {
        var onHostChanged: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.onHostChanged?()
            }
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            DispatchQueue.main.async { [weak self] in
                self?.onHostChanged?()
            }
        }
    }
}
#endif
