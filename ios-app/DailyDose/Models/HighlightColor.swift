import SwiftUI
import UIKit

enum HighlightColor: String, CaseIterable {
    case yellow, green, blue, pink, purple

    var name: String { rawValue.capitalized }

    var uiColor: UIColor { Self.uiColors[self] ?? .clear }

    func highlighting(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.backgroundColor = Color(uiColor)
        return attributed
    }

    static let stylesheet: String = {
        rules(for: UITraitCollection(userInterfaceStyle: .light))
            + "\n@media (prefers-color-scheme: dark) {\n"
            + rules(for: UITraitCollection(userInterfaceStyle: .dark))
            + "\n}"
    }()

    private static let uiColors: [HighlightColor: UIColor] = Dictionary(uniqueKeysWithValues: allCases.map { color in
        let base = color.swatchColor
        return (color, UIColor { traits in
            base.resolvedColor(with: traits)
                .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.45 : 0.35)
        })
    })

    private static func rules(for traits: UITraitCollection) -> String {
        allCases.map { "[data-hl=\"\($0.rawValue)\"] { box-shadow: inset 0 0 0 100vmax \($0.css(in: traits)); }" }
            .joined(separator: "\n")
    }

    var swatchColor: UIColor {
        switch self {
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .pink: .systemPink
        case .purple: .systemPurple
        }
    }

    private func css(in traits: UITraitCollection) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgba(\(Int(r * 255)), \(Int(g * 255)), \(Int(b * 255)), \(a))"
    }
}
