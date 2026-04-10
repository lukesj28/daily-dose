import SwiftUI
import UIKit

struct ArticleFooterView: View {
    let article: Article
    var highlightColorR: Double = 1.0
    var highlightColorG: Double = 0.93
    var highlightColorB: Double = 0.27
    var onAnnotate: ((PendingAnnotation) -> Void)? = nil
    var onEditAnnotation: ((Annotation) -> Void)? = nil
    var onDeleteAnnotation: ((Annotation) -> Void)? = nil

    var body: some View {
        let byIndex = Dictionary(
            grouping: article.annotations.filter { $0.blockSection == BlockSection.footer && $0.isTextAnnotation },
            by: \.blockIndex
        )
        return VStack(alignment: .leading, spacing: 12) {
            Divider()

            if !article.authors.isEmpty {
                TextBlockView(
                    text: article.authors.joined(separator: ", "),
                    annotations: byIndex[0, default: []],
                    highlightColorR: highlightColorR,
                    highlightColorG: highlightColorG,
                    highlightColorB: highlightColorB,
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
                highlightColorR: highlightColorR,
                highlightColorG: highlightColorG,
                highlightColorB: highlightColorB,
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
                    highlightColorR: highlightColorR,
                    highlightColorG: highlightColorG,
                    highlightColorB: highlightColorB,
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
