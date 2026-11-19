import SwiftUI
import SwiftData

struct DailyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CacheManager.self) private var cacheManager
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Article.fetchDate, order: .reverse)
    private var allArticles: [Article]

    @State private var hasAppeared = false

    private var currentArticle: Article? {
        cacheManager.currentArticle(in: allArticles)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                if cacheManager.isLoading && currentArticle == nil {
                    loadingState
                } else if let article = currentArticle, !article.isDeleted {
                    articleReader(article)
                } else if cacheManager.isOffline {
                    messageState(systemImage: "wifi.slash", title: "No Connection",
                                 message: "Read your saved articles in the Library,\nor try again.")
                } else {
                    messageState(systemImage: "newspaper", title: "No article yet",
                                 message: "Try again, or wait\nfor tomorrow's delivery.")
                }
            }
            .refreshable { await refresh() }
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            Task { await cacheManager.checkAndUpdateCache(context: modelContext) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await cacheManager.checkAndUpdateCache(context: modelContext) }
            }
        }
    }

    // MARK: - Article Reader

    private func articleReader(_ article: Article) -> some View {
        ArticleReaderView(article: article, showsSaveButton: true)
            .id(article.id)
    }

    private func refresh() async {
        await cacheManager.checkAndUpdateCache(context: modelContext, force: true)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Fetching today's science...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func messageState(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    Task { await refresh() }
                }
                .buttonStyle(.bordered)
                .disabled(cacheManager.isLoading)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .containerRelativeFrame(.vertical)
        }
    }
}
