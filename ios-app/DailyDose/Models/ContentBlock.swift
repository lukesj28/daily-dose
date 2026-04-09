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

    enum CodingKeys: String, CodingKey {
        case type, text, url, caption, html, mathml
    }
}
