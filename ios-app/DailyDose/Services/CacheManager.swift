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
    func checkAndUpdateCache(context: ModelContext) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let payload = try await service.fetchTodayArticle()
            isOffline = false

            let fetchDate = payload.fetchDate
            let descriptor = FetchDescriptor<Article>(
                predicate: #Predicate { $0.fetchDate == fetchDate }
            )
            let existing = try context.fetch(descriptor)

            if existing.isEmpty {
                try purgeUnsavedDailyArticles(context: context)

                let encoder = JSONEncoder()
                let jsonData = try encoder.encode(payload)

                let article = Article(
                    id: payload.id,
                    title: payload.title,
                    journal: payload.journal,
                    fetchDate: payload.fetchDate,
                    publishDate: payload.publishDate,
                    authors: payload.authors,
                    abstract: payload.abstract,
                    contentJSON: jsonData
                )
                context.insert(article)
                try context.save()
            }
        } catch {
            let cachedCount = (try? context.fetchCount(FetchDescriptor<Article>())) ?? 0
            if cachedCount == 0 {
                isOffline = true
            }
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
        try context.save()
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
