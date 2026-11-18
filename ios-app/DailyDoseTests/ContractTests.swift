import Foundation
import Testing
@testable import DailyDose

private func fixtureData() throws -> Data {
    let url = try #require(Bundle(for: StubURLProtocol.self).url(forResource: "today", withExtension: "json"))
    return try Data(contentsOf: url)
}

extension AppTests {
    @Suite struct ContractTests {
        @Test func backendTodayJSONDecodesIntoPayload() throws {
            let payload = try JSONDecoder().decode(ArticlePayload.self, from: fixtureData())
            #expect(payload.id == "PMC123")
            #expect(payload.authors == ["Jane Smith", "Doe"])
            #expect(payload.content.map(\.type) == [.heading, .paragraph, .paragraph, .heading, .paragraph, .heading, .paragraph, .image, .table, .math])
        }

        @Test func backendTodayJSONBecomesReadableArticleContent() throws {
            let payload = try JSONDecoder().decode(ArticlePayload.self, from: fixtureData())
            let article = Article(
                id: payload.id, title: payload.title, journal: payload.journal,
                fetchDate: payload.fetchDate, publishDate: payload.publishDate,
                authors: payload.authors, license: payload.license, sourceUrl: payload.sourceUrl,
                abstract: payload.abstract, contentJSON: try JSONEncoder().encode(payload)
            )
            #expect(article.contentBlocks.count == 10)
        }

        @Test func serviceFetchesBackendTodayJSON() async throws {
            let data = try fixtureData()
            StubURLProtocol.install { _ in (200, data) }
            let payload = try await ArticleService().fetchTodayArticle()
            #expect(payload.title == "A Novel Approach")
        }
    }
}
