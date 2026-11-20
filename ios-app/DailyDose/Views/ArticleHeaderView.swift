import SwiftUI
import UIKit
import SwiftData

struct ArticleHeaderView: View {
    let article: Article
    var onAnnotate: ((PendingAnnotation) -> Void)? = nil
    var onEditAnnotation: ((Annotation) -> Void)? = nil
    var onDeleteAnnotation: ((Annotation) -> Void)? = nil

    @ViewBuilder
    var body: some View {
        if article.isDeleted {
            EmptyView()
        } else {
            let byIndex = Dictionary(
                grouping: article.annotations.filter { $0.blockSection == BlockSection.header && $0.isTextAnnotation },
                by: \.blockIndex
            )
            VStack(alignment: .leading, spacing: 12) {
            TextBlockView(
                text: article.title,
                annotations: byIndex[1, default: []],
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

            HStack(alignment: .top, spacing: 6) {
                if !article.journal.isEmpty {
                    Text(article.journal)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .layoutPriority(1)
                        .accessibilityLabel("Published in \(article.journal)")
                    Text("·")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                TextBlockView(
                    text: article.formattedPublishDate,
                    annotations: byIndex[3, default: []],
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
            .font(.caption)
        }
    }
}
}
