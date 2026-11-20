import SwiftUI

struct ArticleSkeletonView: View {
    @ScaledMetric(relativeTo: .title) private var titleHeight = 26
    @ScaledMetric(relativeTo: .subheadline) private var authorsHeight = 13
    @ScaledMetric(relativeTo: .caption) private var dateHeight = 11
    @ScaledMetric(relativeTo: .body) private var lineHeight = 14
    @ScaledMetric(relativeTo: .body) private var lineGap = 12

    private static let paragraphs: [[CGFloat]] = [
        [1, 1, 0.96, 1, 0.55],
        [1, 0.98, 1, 0.7],
        [1, 1, 0.94, 1, 1, 0.4],
    ]

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, ReadingLayout.maxWidth) - ReadingLayout.gutter * 2
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    bar(width: width, height: titleHeight)
                    bar(width: width * 0.65, height: titleHeight)
                }
                .padding(.bottom, 16)

                bar(width: width * 0.5, height: authorsHeight)
                    .padding(.bottom, 14)

                bar(width: width * 0.4, height: dateHeight)
                    .padding(.bottom, ReadingLayout.headerSpacing)

                Divider()
                    .padding(.bottom, ReadingLayout.dividerSpacing)

                VStack(alignment: .leading, spacing: 28) {
                    ForEach(Self.paragraphs.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: lineGap) {
                            ForEach(Self.paragraphs[index].indices, id: \.self) { line in
                                bar(width: width * Self.paragraphs[index][line], height: lineHeight)
                            }
                        }
                    }
                }
            }
            .frame(width: width, alignment: .leading)
            .padding(.top, ReadingLayout.topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .shimmering()
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading today's article")
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 3)
            .fill(.fill.secondary)
            .frame(width: max(width, 0), height: height)
    }
}
