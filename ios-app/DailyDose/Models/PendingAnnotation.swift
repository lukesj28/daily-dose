import Foundation

nonisolated struct PendingAnnotation: Equatable {
    let blockSection: String
    let blockIndex: Int
    let range: NSRange
    let cellRow: Int
    let cellColumn: Int

    var isCellAnnotation: Bool { cellRow >= 0 }
    var isEquationAnnotation: Bool { range.location < 0 }

    static func text(section: String, index: Int, range: NSRange) -> PendingAnnotation {
        PendingAnnotation(blockSection: section, blockIndex: index, range: range, cellRow: -1, cellColumn: -1)
    }

    static func cell(index: Int, row: Int, col: Int) -> PendingAnnotation {
        PendingAnnotation(blockSection: BlockSection.content, blockIndex: index, range: NSRange(location: 0, length: 0), cellRow: row, cellColumn: col)
    }

    static func equation(index: Int) -> PendingAnnotation {
        PendingAnnotation(blockSection: BlockSection.content, blockIndex: index, range: NSRange(location: -1, length: 0), cellRow: -1, cellColumn: -1)
    }
}

extension Annotation {
    convenience init(pending: PendingAnnotation, noteText: String, color: HighlightColor = .yellow, article: Article? = nil) {
        self.init(blockIndex: pending.blockIndex, blockSection: pending.blockSection,
                  startIndex: pending.range.location, length: pending.range.length,
                  cellRow: pending.cellRow, cellColumn: pending.cellColumn,
                  noteText: noteText, article: article)
        highlightColor = color
    }

    var anchor: PendingAnnotation {
        PendingAnnotation(blockSection: blockSection, blockIndex: blockIndex, range: range, cellRow: cellRow, cellColumn: cellColumn)
    }
}

extension Article {
    func annotation(at anchor: PendingAnnotation) -> Annotation? {
        annotations.first { $0.anchor == anchor }
    }
}
