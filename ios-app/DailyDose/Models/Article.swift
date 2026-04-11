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
    var license: String = ""
    var sourceUrl: String = ""
    var abstract: String
    var contentJSON: Data
    var isSavedToLibrary: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Annotation.article)
    var annotations: [Annotation] = []

    @Transient private var _cachedContentBlocks: [ContentBlock]?
    @Transient private var _cachedContentJSONHash: Int?

    init(
        id: String,
        title: String,
        journal: String,
        fetchDate: String,
        publishDate: String,
        authors: [String],
        license: String,
        sourceUrl: String,
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
        self.license = license
        self.sourceUrl = sourceUrl
        self.abstract = abstract
        self.contentJSON = contentJSON
        self.isSavedToLibrary = isSavedToLibrary
    }

    var contentBlocks: [ContentBlock] {
        let currentHash = contentJSON.hashValue
        if let cached = _cachedContentBlocks, _cachedContentJSONHash == currentHash {
            return cached
        }
        guard !contentJSON.isEmpty,
              let payload = try? JSONDecoder().decode(ArticlePayload.self, from: contentJSON) else {
            _cachedContentBlocks = []
            _cachedContentJSONHash = currentHash
            return []
        }
        _cachedContentBlocks = payload.content
        _cachedContentJSONHash = currentHash
        return payload.content
    }

    var formattedPublishDate: String {
        guard let date = Article.publishDateParser.date(from: publishDate) else { return publishDate }
        return Article.publishDateDisplay.string(from: date)
    }

    private static let publishDateParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let publishDateDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
}
