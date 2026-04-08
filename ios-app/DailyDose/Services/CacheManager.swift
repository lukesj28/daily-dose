import Foundation
import SwiftData
import Observation

@Observable
final class CacheManager {
    var isLoading = false
    var isOffline = false
    var errorMessage: String?

    private let service = ArticleService()

    @MainActor
    func checkAndUpdateCache(context: ModelContext, force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let payload = try await service.fetchTodayArticle(ignoreCache: force)
            isOffline = false

            if force {
                try replaceDailyArticle(with: payload, context: context)
            } else {
                let fetchDate = payload.fetchDate
                let descriptor = FetchDescriptor<Article>(
                    predicate: #Predicate { $0.fetchDate == fetchDate }
                )
                let existing = try context.fetch(descriptor)
                if existing.isEmpty {
                    try replaceDailyArticle(with: payload, context: context)
                }
            }
        } catch {
            let cachedCount = (try? context.fetchCount(FetchDescriptor<Article>())) ?? 0
            if cachedCount == 0 {
                isOffline = true
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func replaceDailyArticle(
        with payload: ArticlePayload,
        context: ModelContext
    ) throws {
        let payloadId = payload.id
        let idDescriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.id == payloadId }
        )
        let contentJSON = try JSONEncoder().encode(payload)

        if let existing = try context.fetch(idDescriptor).first {
            existing.title = payload.title
            existing.journal = payload.journal
            existing.fetchDate = payload.fetchDate
            existing.publishDate = payload.publishDate
            existing.authors = payload.authors
            existing.abstract = payload.abstract
            existing.contentJSON = contentJSON
            try context.save()
            return
        }

        try purgeUnsavedDailyArticles(context: context)
        context.insert(Article(
            id: payload.id,
            title: payload.title,
            journal: payload.journal,
            fetchDate: payload.fetchDate,
            publishDate: payload.publishDate,
            authors: payload.authors,
            abstract: payload.abstract,
            contentJSON: contentJSON
        ))
        try context.save()
    }

    // Guard against midnight rollover: a daily article the user is mid-read must not be deleted.
    @MainActor
    private func purgeUnsavedDailyArticles(context: ModelContext) throws {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.isSavedToLibrary == false }
        )
        let unsaved = try context.fetch(descriptor)
        for article in unsaved {
            context.delete(article)
        }
    }

    @MainActor
    func currentDailyArticle(context: ModelContext) -> Article? {
        var descriptor = FetchDescriptor<Article>(
            sortBy: [SortDescriptor(\.fetchDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
