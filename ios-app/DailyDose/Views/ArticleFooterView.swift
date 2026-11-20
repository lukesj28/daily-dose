import SwiftUI
import UIKit
import SwiftData

struct ArticleFooterView: View {
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
                grouping: article.annotations.filter { $0.blockSection == BlockSection.footer && $0.isTextAnnotation },
                by: \.blockIndex
            )
            VStack(alignment: .leading, spacing: 12) {
            Divider()

            if !article.authors.isEmpty {
                TextBlockView(
                    text: article.authors.joined(separator: ", "),
                    annotations: byIndex[0, default: []],
                    baseFont: UIFont.preferredFont(forTextStyle: .caption1),
                    textColor: .secondaryLabel,
                    enableMarkdown: false,
                    onAnnotate: { range in
                        onAnnotate?(.text(section: BlockSection.footer, index: 0, range: range))
                    },
                    onEditAnnotation: { onEditAnnotation?($0) },
                    onDeleteAnnotation: { onDeleteAnnotation?($0) }
                )
                .id("footer_0")
            }

            TextBlockView(
                text: "\(article.journal) · \(article.formattedPublishDate)",
                annotations: byIndex[1, default: []],
                baseFont: UIFont.preferredFont(forTextStyle: .caption1),
                textColor: .secondaryLabel,
                enableMarkdown: false,
                onAnnotate: { range in
                    onAnnotate?(.text(section: BlockSection.footer, index: 1, range: range))
                },
                onEditAnnotation: { onEditAnnotation?($0) },
                onDeleteAnnotation: { onDeleteAnnotation?($0) }
            )
            .id("footer_1")

            if !article.license.isEmpty {
                TextBlockView(
                    text: article.license,
                    annotations: byIndex[2, default: []],
                    baseFont: UIFont.preferredFont(forTextStyle: .caption2),
                    textColor: .tertiaryLabel,
                    enableMarkdown: false,
                    onAnnotate: { range in
                        onAnnotate?(.text(section: BlockSection.footer, index: 2, range: range))
                    },
                    onEditAnnotation: { onEditAnnotation?($0) },
                    onDeleteAnnotation: { onDeleteAnnotation?($0) }
                )
                .id("footer_2")
            }

            if let url = URL(string: article.sourceUrl) {
                Link(destination: url) {
                    Text(article.sourceUrl)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .underline()
                }
            }
        }
        .padding(.top, 24)
    }
}
}
