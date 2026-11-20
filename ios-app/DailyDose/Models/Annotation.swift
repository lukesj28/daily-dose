import Foundation
import SwiftData

nonisolated enum BlockSection {
    static let header = "header"
    static let content = "content"
    static let footer = "footer"

    static func scrollID(_ section: String, _ index: Int) -> String { "\(section)_\(index)" }
}

@Model
final class Annotation {
    var id: UUID
    @Attribute(originalName: "paragraphIndex") var blockIndex: Int
    var blockSection: String = "content"
    var startIndex: Int
    var length: Int
    var cellRow: Int
    var cellColumn: Int
    var noteText: String
    var colorName: String = HighlightColor.yellow.rawValue

    var article: Article?

    init(
        id: UUID = UUID(),
        blockIndex: Int,
        blockSection: String = "content",
        startIndex: Int,
        length: Int,
        cellRow: Int = -1,
        cellColumn: Int = -1,
        noteText: String,
        article: Article? = nil
    ) {
        self.id = id
        self.blockIndex = blockIndex
        self.blockSection = blockSection
        self.startIndex = startIndex
        self.length = length
        self.cellRow = cellRow
        self.cellColumn = cellColumn
        self.noteText = noteText
        self.article = article
    }

    var range: NSRange {
        NSRange(location: startIndex, length: length)
    }

    var scrollID: String { BlockSection.scrollID(blockSection, blockIndex) }

    var highlightColor: HighlightColor {
        get { HighlightColor(rawValue: colorName) ?? .yellow }
        set { colorName = newValue.rawValue }
    }

    var highlightKey: HighlightKey { HighlightKey(id: id, color: highlightColor) }

    var isTextAnnotation: Bool { cellRow < 0 && startIndex >= 0 && length > 0 }
    var isCellAnnotation: Bool { cellRow >= 0 }
    var isEquationAnnotation: Bool { startIndex < 0 }
}

struct HighlightKey: Hashable {
    let id: UUID
    let color: HighlightColor
}
