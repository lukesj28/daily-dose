import SwiftUI

struct SwatchButton: View {
    let color: HighlightColor
    let isSelected: Bool
    var diameter: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(color.swatchColor))
                .frame(width: diameter, height: diameter)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: diameter * 0.45, weight: .bold))
                            .foregroundStyle(.black.opacity(0.75))
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
