import SwiftUI
import UIKit

struct SignInPresenter: UIViewControllerRepresentable {
    @Binding var presenter: UIViewController?

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.isHidden = true
        presenter = viewController
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if presenter !== uiViewController {
            presenter = uiViewController
        }
    }
}
