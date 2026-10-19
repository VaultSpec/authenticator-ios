import SwiftUI
import UIKit

/// Leaves its content out of screenshots, screen recordings and mirrored displays while
/// `isActive` is true.
///
/// iOS has no API that blocks screenshots. The system does leave the contents of a secure text
/// field out of every capture, so the content is drawn inside that field's secure layer.
/// The content is display-only: touches pass through to the views behind it.
struct ScreenshotShield<Content: View>: UIViewRepresentable {
    var isActive: Bool
    @ViewBuilder var content: Content

    func makeUIView(context: Context) -> ShieldView {
        ShieldView(content: AnyView(content))
    }

    func updateUIView(_ view: ShieldView, context: Context) {
        view.host.rootView = AnyView(content)
        view.setProtected(isActive)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ShieldView, context: Context) -> CGSize? {
        uiView.host.sizeThatFits(in: CGSize(
            width: proposal.width ?? .greatestFiniteMagnitude,
            height: proposal.height ?? .greatestFiniteMagnitude
        ))
    }
}

final class ShieldView: UIView {
    let host: UIHostingController<AnyView>
    private let field = UITextField()

    init(content: AnyView) {
        host = UIHostingController(rootView: content)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        host.view.backgroundColor = .clear
        field.isSecureTextEntry = true

        // The secure field's canvas view; if a future iOS changes it, fall back to a plain view
        let container = (field.layer.sublayers?.first?.delegate as? UIView) ?? UIView()
        container.subviews.forEach { $0.removeFromSuperview() }
        container.isUserInteractionEnabled = false
        for view in [container, host.view!] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(container)
        container.addSubview(host.view)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setProtected(_ protected: Bool) {
        if field.isSecureTextEntry != protected { field.isSecureTextEntry = protected }
    }
}
