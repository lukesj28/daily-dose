import SwiftUI

struct DisclaimerView: View {
    @AppStorage("hasAcceptedDisclaimer") private var hasAccepted = false

    private var notice: some View {
        VStack(spacing: 32) {
            Image(systemName: "cross.case")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                Text("Important Notice")
                    .font(.title)
                    .fontWeight(.bold)

                Text("This application is for informational and educational purposes only. It does not constitute professional medical advice, diagnosis, or treatment. Always seek the advice of a physician or other qualified health provider with any questions you may have regarding a medical condition.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    var body: some View {
        VStack(spacing: 32) {
            ViewThatFits(in: .vertical) {
                notice.frame(maxHeight: .infinity)
                ScrollView { notice }
            }

            Button {
                hasAccepted = true
            } label: {
                Text("I Understand")
                    .font(.headline)
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(.label))
        }
        .frame(maxWidth: 560)
        .padding(24)
    }
}
