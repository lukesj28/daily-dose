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
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
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
        ArticleSkeletonView()
    }

    private func messageState(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        ScrollView {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await refresh() }
                }
                .buttonStyle(.bordered)
                .disabled(cacheManager.isLoading)
            }
            .containerRelativeFrame(.vertical)
        }
    }
}
