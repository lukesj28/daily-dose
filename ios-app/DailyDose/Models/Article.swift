import Foundation
import SwiftData

@Model
final class Article {
    @Attribute(.unique) var id: String
    var title: String
    var journal: String
    var fetchDate: String
    var publishDate: String
    var authors: [String]
    var abstract: String
    var contentJSON: Data
    var isSavedToLibrary: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Annotation.article)
    var annotations: [Annotation] = []

    init(
        id: String,
        title: String,
        journal: String,
        fetchDate: String,
        publishDate: String,
        authors: [String],
        abstract: String,
        contentJSON: Data,
        isSavedToLibrary: Bool = false
    ) {
        self.id = id
        self.title = title
        self.journal = journal
        self.fetchDate = fetchDate
        self.publishDate = publishDate
        self.authors = authors
        self.abstract = abstract
        self.contentJSON = contentJSON
        self.isSavedToLibrary = isSavedToLibrary
    }

    // CodingKeys in ArticlePayload already handle snake_case mapping.
    // Do NOT use .convertFromSnakeCase here — it double-converts and breaks decoding.
    var contentBlocks: [ContentBlock] {
        guard !contentJSON.isEmpty,
              let payload = try? JSONDecoder().decode(ArticlePayload.self, from: contentJSON) else {
            return []
        }
        return payload.content
    }
}
