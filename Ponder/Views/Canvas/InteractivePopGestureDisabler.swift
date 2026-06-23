#if os(iOS)
import SwiftUI
import UIKit

struct InteractivePopGestureDisabler: UIViewControllerRepresentable {
    let isDisabled: Bool

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.isDisabled = isDisabled
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.isDisabled = isDisabled
        controller.updateGestureState()
    }

    final class Controller: UIViewController {
        var isDisabled = false

        private weak var trackedNavigationController: UINavigationController?
        private var previousIsEnabled: Bool?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            updateGestureState()
        }

        deinit {
            restoreGestureState()
        }

        func updateGestureState() {
            guard let navigationController else {
                DispatchQueue.main.async { [weak self] in
                    self?.updateGestureState()
                }
                return
            }

            if trackedNavigationController !== navigationController {
                restoreGestureState()
                trackedNavigationController = navigationController
                previousIsEnabled = navigationController.interactivePopGestureRecognizer?.isEnabled
            }

            navigationController.interactivePopGestureRecognizer?.isEnabled = !isDisabled
        }

        private func restoreGestureState() {
            if let trackedNavigationController, let previousIsEnabled {
                trackedNavigationController.interactivePopGestureRecognizer?.isEnabled = previousIsEnabled
            }
            trackedNavigationController = nil
            previousIsEnabled = nil
        }
    }
}
#endif
