#if os(iOS)
import SwiftUI
import UIKit

/// Opens drawing tools when no PencilKit surface is active. Active drawing
/// surfaces keep their native squeeze palette and double-tap behavior.
struct CanvasPencilSqueezeShortcut: UIViewRepresentable {
    var isEnabled: Bool
    var onShowDrawingTools: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = false

        let interaction = UIPencilInteraction()
        interaction.delegate = context.coordinator
        interaction.isEnabled = isEnabled
        view.addInteraction(interaction)
        context.coordinator.interaction = interaction
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.interaction?.isEnabled = isEnabled
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        guard let interaction = coordinator.interaction else { return }
        interaction.isEnabled = false
        interaction.delegate = nil
        view.removeInteraction(interaction)
        coordinator.interaction = nil
    }

    final class Coordinator: NSObject, UIPencilInteractionDelegate {
        var parent: CanvasPencilSqueezeShortcut
        weak var interaction: UIPencilInteraction?

        init(parent: CanvasPencilSqueezeShortcut) {
            self.parent = parent
        }

        @available(iOS 17.5, *)
        func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
        ) {
            // Respond once on release, honoring Settings > Apple Pencil > Squeeze.
            // Other preferences (including Off and Shortcuts) belong to the system
            // or an active PencilKit surface; they must not start a new drawing.
            guard parent.isEnabled,
                  let window = interaction.view?.window,
                  window.isKeyWindow,
                  window.windowScene?.activationState == .foregroundActive,
                  squeeze.phase == .ended,
                  UIPencilInteraction.preferredSqueezeAction == .showContextualPalette
            else { return }

            parent.onShowDrawingTools()
        }
    }
}
#endif
