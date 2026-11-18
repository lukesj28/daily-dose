import Foundation
import SwiftData
import Observation

@Observable
final class CacheManager {
    var isLoading = false
    var isOffline = false
    var errorMessage: String?

    // Persisted to UserDefaults — avoids a SwiftData schema migration while
    // still surviving relaunches.
    private(set) var currentDailyId: String? {
        didSet {
            guard oldValue != currentDailyId else { return }
            if let currentDailyId {
                UserDefaults.standard.set(currentDailyId, forKey: Self.currentDailyIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.currentDailyIdKey)
            }
        }
    }

    private static let currentDailyIdKey = "DailyDose.currentDailyArticleId"
    private let service = ArticleService()

    init() {
        currentDailyId = UserDefaults.standard.string(forKey: Self.currentDailyIdKey)
    }

    @MainActor
    func checkAndUpdateCache(context: ModelContext, force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let payload = try await service.fetchTodayArticle(ignoreCache: force)
            isOffline = false
            try upsertDailyArticle(with: payload, context: context)
        } catch {
            let cached = (try? context.fetch(FetchDescriptor<Article>())) ?? []
            if currentArticle(in: cached) == nil {
                isOffline = true
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func currentArticle(in articles: [Article]) -> Article? {
        if let id = currentDailyId { return articles.first { $0.id == id } }
        return articles.first { !$0.isSavedToLibrary }
    }

    @MainActor
    func removeFromLibrary(_ article: Article, context: ModelContext) {
        if article.id == currentDailyId {
            article.isSavedToLibrary = false
        } else {
            context.delete(article)
        }
    }

    @MainActor
    private func upsertDailyArticle(with payload: ArticlePayload, context: ModelContext) throws {
        let payloadId = payload.id
        let contentJSON = try JSONEncoder().encode(payload)
        try purgeUnsavedArticles(exceptId: payloadId, context: context)

        let idDescriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.id == payloadId }
        )

        if let existing = try context.fetch(idDescriptor).first {
            if !existing.isSavedToLibrary {
                existing.title = payload.title
                existing.journal = payload.journal
                existing.fetchDate = payload.fetchDate
                existing.publishDate = payload.publishDate
                existing.authors = payload.authors
                existing.license = payload.license
                existing.sourceUrl = payload.sourceUrl
                existing.abstract = payload.abstract
                existing.contentJSON = contentJSON
            }
        } else {
            context.insert(Article(
                id: payload.id,
                title: payload.title,
                journal: payload.journal,
                fetchDate: payload.fetchDate,
                publishDate: payload.publishDate,
                authors: payload.authors,
                license: payload.license,
                sourceUrl: payload.sourceUrl,
                abstract: payload.abstract,
                contentJSON: contentJSON
            ))
        }

        try context.save()
        currentDailyId = payloadId
    }

    @MainActor
    private func purgeUnsavedArticles(exceptId keepId: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.isSavedToLibrary == false && $0.id != keepId }
        )
        for article in try context.fetch(descriptor) {
            context.delete(article)
        }
    }
}
