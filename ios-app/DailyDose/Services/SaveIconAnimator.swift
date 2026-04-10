import UIKit

/// Renders the save icon as a UIView on the key window so drag position updates
/// bypass SwiftUI's render cycle entirely.
final class SaveIconAnimator {
    static let shared = SaveIconAnimator()
    private init() {}

    private var iconView: UIView?

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    func show(at location: CGPoint) {
        guard let window = keyWindow else { return }
        hide()

        let view = makeIconView()
        view.center = CGPoint(x: location.x, y: location.y - 60)
        window.addSubview(view)
        iconView = view
    }

    func move(to location: CGPoint) {
        // Direct layer mutation — no animation, no SwiftUI state
        iconView?.layer.position = CGPoint(x: location.x, y: location.y - 60)
    }

    func flyToLibrary(completion: @escaping () -> Void) {
        guard let window = keyWindow, let view = iconView else { return }

        // Library tab (2nd of 2) centers at 75% width.
        // Tab bar icon sits ~24.5pt above the bottom safe area edge.
        let targetX = window.bounds.width * 0.75
        let targetY = window.bounds.height - window.safeAreaInsets.bottom - 24.5

        UIView.animate(withDuration: 0.45, delay: 0, options: .curveEaseIn) {
            view.center = CGPoint(x: targetX, y: targetY)
            view.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
            view.alpha = 0
        } completion: { _ in
            view.removeFromSuperview()
            self.iconView = nil
            completion()
        }
    }

    func hide() {
        iconView?.removeFromSuperview()
        iconView = nil
    }

    private func makeIconView() -> UIView {
        let size = CGSize(width: 56, height: 72)
        let container = UIView(frame: CGRect(origin: .zero, size: size))

        let config = UIImage.SymbolConfiguration(pointSize: 40)

        // draw(at:) at natural size avoids the scaling artifacts draw(in:) causes
        // when fill and outline variants have slightly different internal metrics.
        let composite = UIGraphicsImageRenderer(size: size).image { _ in
            func centered(_ image: UIImage) -> CGPoint {
                CGPoint(x: (size.width - image.size.width) / 2,
                        y: (size.height - image.size.height) / 2)
            }
            if let fill = UIImage(systemName: "text.page.fill", withConfiguration: config)?
                .withTintColor(.systemBackground, renderingMode: .alwaysOriginal) {
                fill.draw(at: centered(fill))
            }
            if let outline = UIImage(systemName: "text.page", withConfiguration: config)?
                .withTintColor(.label, renderingMode: .alwaysOriginal) {
                outline.draw(at: centered(outline))
            }
        }

        let imageView = UIImageView(image: composite)
        imageView.frame = CGRect(origin: .zero, size: size)
        imageView.contentMode = .center
        container.addSubview(imageView)
        return container
    }
}
