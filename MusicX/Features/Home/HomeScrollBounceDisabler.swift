import SwiftUI
import UIKit

/// Disables vertical bounce only for the homepage ScrollView.
struct HomeScrollBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { configureNearestScrollView(from: view) }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { configureNearestScrollView(from: view) }
    }

    private func configureNearestScrollView(from view: UIView) {
        var ancestor = view.superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView {
                scrollView.bounces = false
                scrollView.alwaysBounceVertical = false
                return
            }
            ancestor = current.superview
        }
    }
}
