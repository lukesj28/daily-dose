import SwiftUI
import UIKit

struct ArticleHeaderView: View {
    let article: Article
    var highlightColorR: Double = 1.0
    var highlightColorG: Double = 0.93
    var highlightColorB: Double = 0.27
    var onAnnotate: ((PendingAnnotation) -> Void)? = nil
    var onEditAnnotation: ((Annotation) -> Void)? = nil
    var onDeleteAnnotation: ((Annotation) -> Void)? = nil

    var body: some View {
        let byIndex = Dictionary(
            grouping: article.annotations.filter { $0.blockSection == BlockSection.header && $0.isTextAnnotation },
            by: \.blockIndex
        )
        return VStack(alignment: .leading, spacing: 12) {
            Text(article.journal)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(.tint))

            TextBlockView(
                text: article.title,
                annotations: byIndex[1, default: []],
                highlightColorR: highlightColorR,
                highlightColorG: highlightColorG,
                highlightColorB: highlightColorB,
                baseFont: UIFont.preferredFont(forTextStyle: .title1),
                baseFontWeight: .bold,
                enableMarkdown: false,
                onAnnotate: { range in
                    onAnnotate?(.text(section: BlockSection.header, index: 1, range: range))
                },
                onEditAnnotation: { onEditAnnotation?($0) },
                onDeleteAnnotation: { onDeleteAnnotation?($0) }
            )
            .id("header_1")

            TextBlockView(
                text: article.authors.joined(separator: ", "),
                annotations: byIndex[2, default: []],
                highlightColorR: highlightColorR,
                highlightColorG: highlightColorG,
                highlightColorB: highlightColorB,
                baseFont: UIFont.preferredFont(forTextStyle: .subheadline),
                textColor: .secondaryLabel,
                enableMarkdown: false,
                onAnnotate: { range in
                    onAnnotate?(.text(section: BlockSection.header, index: 2, range: range))
                },
                onEditAnnotation: { onEditAnnotation?($0) },
                onDeleteAnnotation: { onDeleteAnnotation?($0) }
            )
            .id("header_2")

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextBlockView(
                    text: article.formattedPublishDate,
                    annotations: byIndex[3, default: []],
                    highlightColorR: highlightColorR,
                    highlightColorG: highlightColorG,
                    highlightColorB: highlightColorB,
                    baseFont: UIFont.preferredFont(forTextStyle: .caption1),
                    textColor: .tertiaryLabel,
                    enableMarkdown: false,
                    onAnnotate: { range in
                        onAnnotate?(.text(section: BlockSection.header, index: 3, range: range))
                    },
                    onEditAnnotation: { onEditAnnotation?($0) },
                    onDeleteAnnotation: { onDeleteAnnotation?($0) }
                )
                .id("header_3")
            }
        }
    }
}
