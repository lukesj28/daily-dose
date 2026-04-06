import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Article> { $0.isSavedToLibrary == true },
        sort: \Article.fetchDate,
        order: .reverse
    )
    private var savedArticles: [Article]

    var body: some View {
        NavigationStack {
            Group {
                if savedArticles.isEmpty {
                    emptyLibrary
                } else {
                    articleList
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Article List

    private var articleList: some View {
        List {
            ForEach(savedArticles) { article in
                NavigationLink(destination: ArticleReaderView(article: article)) {
                    articleRow(article)
                }
            }
            .onDelete(perform: deleteArticles)
        }
        .listStyle(.plain)
    }

    private func articleRow(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(article.journal)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)

            Text(article.title)
                .font(.headline)
                .lineLimit(2)

            HStack {
                Text(article.authors.prefix(3).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer()

                Text(article.fetchDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            let annotationCount = article.annotations.count
            if annotationCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.caption2)
                    Text("\(annotationCount) note\(annotationCount == 1 ? "" : "s")")
                        .font(.caption2)
                }
                .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 4)
    }

    private func deleteArticles(at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(savedArticles[index])
            }
        }
    }

    // MARK: - Empty State

    private var emptyLibrary: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Saved Articles")
                .font(.title2)
                .fontWeight(.bold)
            Text("Articles you save from the Daily tab\nwill appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
