import Foundation

enum ContentBlockType: String, Codable {
    case heading
    case paragraph
    case image
    case table
    case math
}

struct ContentBlock: Codable, Identifiable {
    let type: ContentBlockType
    let text: String?
    let url: String?
    let caption: String?
    let html: String?
    let mathml: String?

    var index: Int = 0
    var id: Int { index }

    static func scrollID(forIndex index: Int) -> String { BlockSection.scrollID(BlockSection.content, index) }
    var scrollID: String { Self.scrollID(forIndex: index) }

    var searchableText: String? {
        guard type == .paragraph || type == .heading, let text else { return nil }
        return type == .paragraph ? InlineMarkdown.plain(text) : text
    }

    enum CodingKeys: String, CodingKey {
        case type, text, url, caption, html, mathml
    }
}
