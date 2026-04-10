import SwiftUI

struct ArticleFooterView: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            if !article.authors.isEmpty {
                Text(article.authors.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(article.journal) · \(formattedDate)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !article.license.isEmpty {
                Text(article.license)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: article.publishDate) else {
            return article.publishDate
        }
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
