#if os(macOS)
import SwiftUI
import AppKit

/// Attaches a local NSEvent monitor to intercept scroll-wheel events for the
/// canvas without disrupting SwiftUI's own hit-testing or gesture recognizers.
///
/// The monitor is hosted by an `NSViewRepresentable` so scrolls can be filtered
/// to the canvas window/area before they pan or zoom the canvas.
///
/// Behaviour (matches Figma / Miro on Mac):
/// | Input                        | Action |
/// |------------------------------|--------|
/// | Two-finger swipe (trackpad)  | Pan    |
/// | ⌘ + scroll (trackpad/mouse) | Zoom   |
struct MacScrollInterceptor: NSViewRepresentable {

    /// - deltaX:        Horizontal delta (pts, positive = right).
    /// - deltaY:        Vertical delta   (pts, positive = down canvas).
    /// - phase:         Raw `NSEvent.Phase`.
    /// - isZoom:        When `true`, interpret as zoom rather than pan.
    var onScroll: (
        _ deltaX: CGFloat,
        _ deltaY: CGFloat,
        _ phase: NSEvent.Phase,
        _ isZoom: Bool
    ) -> Void

    func makeNSView(context: Context) -> ScrollMonitorView {
        let view = ScrollMonitorView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollMonitorView, context: Context) {
        nsView.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: ScrollMonitorView, coordinator: ()) {
        nsView.removeMonitor()
    }

    // MARK: - Monitor host view

    final class ScrollMonitorView: NSView {
        var onScroll: ((CGFloat, CGFloat, NSEvent.Phase, Bool) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                removeMonitor()
            } else {
                installMonitor()
            }
        }

        deinit {
            removeMonitor()
        }

        private func installMonitor() {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.shouldHandle(event) else { return event }

                let isZoom = event.modifierFlags.contains(.command)

                let dx: CGFloat
                let dy: CGFloat

                if event.hasPreciseScrollingDeltas {
                    dx =  event.scrollingDeltaX
                    dy =  event.scrollingDeltaY
                } else {
                    dx =  event.deltaX * 20
                    dy =  event.deltaY * 20
                }

                DispatchQueue.main.async { [weak self] in
                    guard let onScroll = self?.onScroll else { return }
                    if isZoom {
                        // positive dy = fingers/wheel moving up = zoom IN
                        onScroll(0, dy, event.phase, true)
                    } else {
                        // negate dy so swiping fingers UP moves canvas UP
                        onScroll(dx, -dy, event.phase, false)
                    }
                }

                // Return the event so other responders (e.g. scroll views in sheets)
                // can still receive it.
                return event
            }
        }

        func removeMonitor() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        private func shouldHandle(_ event: NSEvent) -> Bool {
            guard let window,
                  let eventWindow = event.window,
                  eventWindow === window
            else { return false }

            guard window.attachedSheet == nil else { return false }

            let localPoint = convert(event.locationInWindow, from: nil)
            guard bounds.contains(localPoint) else { return false }

            if let hitView = window.contentView?.hitTest(event.locationInWindow),
               hitView.isInsideNativeScrollView {
                return false
            }

            return true
        }
    }
}

/// Hosts a lightweight AppKit key monitor for canvas shortcuts without making
/// the SwiftUI canvas focusable. This avoids the macOS focus ring around the
/// whole drawing surface while still letting text fields receive typed input.
struct MacKeyboardShortcutMonitor: NSViewRepresentable {
    var isEnabled: Bool
    var onKeyEvent: (_ event: NSEvent, _ viewportSize: CGSize) -> Bool

    func makeNSView(context: Context) -> KeyMonitorView {
        let view = KeyMonitorView()
        view.isEnabled = isEnabled
        view.onKeyEvent = onKeyEvent
        return view
    }

    func updateNSView(_ nsView: KeyMonitorView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onKeyEvent = onKeyEvent
        nsView.refreshMonitor()
    }

    static func dismantleNSView(_ nsView: KeyMonitorView, coordinator: ()) {
        nsView.removeMonitor()
    }

    final class KeyMonitorView: NSView {
        var isEnabled = true
        var onKeyEvent: ((NSEvent, CGSize) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            refreshMonitor()
        }

        deinit {
            removeMonitor()
        }

        func refreshMonitor() {
            if window == nil {
                removeMonitor()
            } else if monitor == nil {
                installMonitor()
            }
        }

        private func installMonitor() {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self, self.shouldHandle(event) else { return event }
                let handled = self.onKeyEvent?(event, self.bounds.size) ?? false
                return handled ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func shouldHandle(_ event: NSEvent) -> Bool {
            guard isEnabled,
                  let window,
                  let eventWindow = event.window,
                  eventWindow === window
            else { return false }

            guard window.attachedSheet == nil else { return false }

            if let responder = window.firstResponder,
               responder is NSTextView || responder is NSTextField || responder is NSComboBox {
                return false
            }

            if let hitView = window.contentView?.hitTest(event.locationInWindow),
               hitView.isInsideKeyboardInputView {
                return false
            }

            return true
        }
    }
}

private extension NSView {
    var isInsideNativeScrollView: Bool {
        if self is NSScrollView || self is NSTextView {
            return true
        }
        return superview?.isInsideNativeScrollView ?? false
    }

    var isInsideKeyboardInputView: Bool {
        if self is NSTextView || self is NSTextField || self is NSComboBox || self is NSSearchField {
            return true
        }
        return superview?.isInsideKeyboardInputView ?? false
    }
}
#endif
