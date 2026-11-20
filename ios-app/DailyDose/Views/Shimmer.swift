import SwiftUI

private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .mask {
                    LinearGradient(
                        colors: [.black.opacity(0.45), .black, .black.opacity(0.45)],
                        startPoint: UnitPoint(x: phase - 1, y: 0.5),
                        endPoint: UnitPoint(x: phase, y: 0.5)
                    )
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { phase = 2 }
                }
        }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}
