import Foundation
import SwiftData

@Model
final class Annotation {
    var id: UUID
    var paragraphIndex: Int
    var startIndex: Int
    var length: Int
    var noteText: String

    var article: Article?

    init(
        id: UUID = UUID(),
        paragraphIndex: Int,
        startIndex: Int,
        length: Int,
        noteText: String,
        article: Article? = nil
    ) {
        self.id = id
        self.paragraphIndex = paragraphIndex
        self.startIndex = startIndex
        self.length = length
        self.noteText = noteText
        self.article = article
    }

    var range: NSRange {
        NSRange(location: startIndex, length: length)
    }
}
