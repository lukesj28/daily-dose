import SwiftUI

struct ArticleHeaderView: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(article.journal)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(.tint))

            Text(article.title)
                .font(.title)
                .fontWeight(.bold)

            Text(article.authors.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Label(formattedDate(article.publishDate), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func formattedDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
