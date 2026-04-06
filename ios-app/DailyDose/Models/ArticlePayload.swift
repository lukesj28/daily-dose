import Foundation

struct ArticlePayload: Codable {
    let id: String
    let title: String
    let journal: String
    let fetchDate: String
    let publishDate: String
    let authors: [String]
    let abstract: String
    let content: [ContentBlock]

    enum CodingKeys: String, CodingKey {
        case id, title, journal, authors, abstract, content
        case fetchDate = "fetch_date"
        case publishDate = "publish_date"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        journal = try container.decode(String.self, forKey: .journal)
        fetchDate = try container.decode(String.self, forKey: .fetchDate)
        publishDate = try container.decode(String.self, forKey: .publishDate)
        authors = try container.decode([String].self, forKey: .authors)
        abstract = try container.decode(String.self, forKey: .abstract)

        var rawContent = try container.decode([ContentBlock].self, forKey: .content)
        for i in rawContent.indices {
            rawContent[i].index = i
        }
        content = rawContent
    }
}
